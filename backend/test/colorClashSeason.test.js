process.env.JWT_SECRET = process.env.JWT_SECRET || 'color-clash-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const { MongoMemoryReplSet } = require('mongodb-memory-server');

const User = require('../src/models/User');
const Room = require('../src/models/Room');
const Transaction = require('../src/models/Transaction');
const WalletEscrow = require('../src/models/WalletEscrow');
const AuditLog = require('../src/models/AuditLog');
const AntiFraudFlag = require('../src/models/AntiFraudFlag');
const ColorClashMatch = require('../src/models/ColorClashMatch');
const ColorClashRound = require('../src/models/ColorClashRound');
const ColorClashMove = require('../src/models/ColorClashMove');
const ColorClashSeason = require('../src/models/ColorClashSeason');
const ColorClashSeasonProgress = require('../src/models/ColorClashSeasonProgress');
const colorClashRoutes = require('../src/routes/colorClashRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');
const matchService = require('../src/services/colorClashMatchService');
const matchmakingService = require('../src/services/colorClashMatchmakingService');
const settlementService = require('../src/services/colorClashSettlementService');
const seasonService = require('../src/services/colorClashSeasonService');
const rankingService = require('../src/services/rankingService');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.strings = new Map();
        this.sortedSets = new Map();
    }

    async get(key) {
        return this.strings.has(key) ? this.strings.get(key) : null;
    }

    async set(key, value, options = undefined) {
        if (options?.NX && this.strings.has(key)) {
            return null;
        }
        this.strings.set(key, value);
        return 'OK';
    }

    async del(keys) {
        const keyList = Array.isArray(keys) ? keys : Array.from(arguments);
        let removed = 0;
        for (const key of keyList) {
            if (this.strings.delete(key)) removed += 1;
            if (this.sortedSets.delete(key)) removed += 1;
        }
        return removed;
    }

    async expire() {
        return 1;
    }

    async exists(key) {
        return this.strings.has(key) ? 1 : 0;
    }

    async ping() {
        return 'PONG';
    }

    async zAdd(key, entries) {
        const zset = this.sortedSets.get(key) || new Map();
        for (const entry of entries) {
            zset.set(entry.value, Number(entry.score));
        }
        this.sortedSets.set(key, zset);
        return entries.length;
    }

    getSortedEntries(key, reverse = false) {
        const zset = this.sortedSets.get(key) || new Map();
        const entries = Array.from(zset.entries())
            .sort((left, right) => left[1] - right[1] || left[0].localeCompare(right[0]));
        if (reverse) {
            entries.reverse();
        }
        return entries;
    }

    async zRangeWithScores(key, start, stop, options = {}) {
        const reverse = Boolean(options?.REV);
        const sorted = this.getSortedEntries(key, reverse);
        if (!sorted.length) return [];
        return sorted.slice(start, stop + 1).map(([value, score]) => ({ value, score }));
    }

    async zScore(key, member) {
        const zset = this.sortedSets.get(key) || new Map();
        if (!zset.has(member)) return null;
        return zset.get(member);
    }

    async zRevRank(key, member) {
        const sorted = this.getSortedEntries(key, true);
        const index = sorted.findIndex(([value]) => value === member);
        return index >= 0 ? index : null;
    }
}

class FakeIo {
    constructor() {
        this.events = [];
    }

    to(target) {
        return {
            emit: (event, payload) => {
                this.events.push({ target, event, payload });
            }
        };
    }
}

const clearRuntimeTimers = () => {
    for (const timer of matchService.countdownTimers.values()) clearTimeout(timer);
    for (const timer of matchService.turnTimers.values()) clearTimeout(timer);
    matchService.countdownTimers.clear();
    matchService.turnTimers.clear();
};

const makeUsername = () => `rank_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 5,
    coins: overrides.coins ?? 500,
    isGuest: overrides.isGuest ?? false,
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`,
    settings: overrides.settings,
    gameStats: overrides.gameStats
});

const buildStakeConfig = (entryFee = 100) => ({
    currency: entryFee > 0 ? 'coins' : 'none',
    entryFee,
    payouts: [{ place: 1, bps: 10000 }],
    houseFeeBps: 500,
    sinkFeeBps: 200
});

const buildRoundResult = (winner, loser, overrides = {}) => ({
    winnerSeat: 0,
    endReason: overrides.endReason || 'hand_empty',
    placements: [
        {
            placement: 1,
            seatIndex: 0,
            userId: winner._id,
            status: 'active',
            handPoints: 0,
            handCount: 0,
            timeoutStrikes: 0
        },
        {
            placement: 2,
            seatIndex: 1,
            userId: loser._id,
            status: overrides.loserStatus || 'active',
            handPoints: 42,
            handCount: 3,
            timeoutStrikes: overrides.timeoutStrikes || 0
        }
    ],
    scoreDeltas: [
        { seatIndex: 0, userId: winner._id, scoreDelta: 42 },
        { seatIndex: 1, userId: loser._id, scoreDelta: -42 }
    ],
    rankInputs: [
        { seatIndex: 0, userId: winner._id, placement: 1, outcome: 'win', handPointsRemaining: 0, timeoutStrikes: 0, status: 'active' },
        {
            seatIndex: 1,
            userId: loser._id,
            placement: 2,
            outcome: overrides.loserOutcome || 'loss',
            handPointsRemaining: 42,
            timeoutStrikes: overrides.timeoutStrikes || 0,
            status: overrides.loserStatus || 'active'
        }
    ]
});

let replSet;
let redis;
let io;
let server;
let baseUrl;

const startApiServer = async () => {
    redis = new FakeRedis();
    io = new FakeIo();
    clearRuntimeTimers();
    matchService.configure({ redis, io });
    matchmakingService.configure({ redis, io });
    settlementService.configure({ redis, io });
    seasonService.configure({ redis });
    rankingService.configure({ redisClient: redis });

    const app = express();
    app.use(express.json());
    app.set('redis', redis);
    app.set('io', io);
    app.use('/api/color-clash', colorClashRoutes);
    app.use(errorMiddleware);

    await new Promise((resolve) => {
        server = http.createServer(app);
        server.listen(0, '127.0.0.1', resolve);
    });
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
};

const stopApiServer = async () => {
    clearRuntimeTimers();
    if (server) {
        await new Promise((resolve) => server.close(resolve));
        server = null;
        baseUrl = null;
    }
};

const createAuthHeaders = async (user, extraHeaders = {}) => {
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET);
    await redis.set(`session:${user._id}`, 'refresh-token', { EX: 60 * 60 });
    return {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...extraHeaders
    };
};

const apiRequest = async ({ method = 'GET', path, user, body, headers = {} }) => {
    const resolvedHeaders = user
        ? await createAuthHeaders(user, headers)
        : headers;
    const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: resolvedHeaders,
        body: body === undefined ? undefined : JSON.stringify(body)
    });
    const json = await response.json();
    return {
        status: response.status,
        body: json
    };
};

const createCompletedMatch = async ({ tableMode = 'ranked', entryFee = 0, loserOutcome = 'loss', timeoutStrikes = 0 } = {}) => {
    const winner = await createUser({ coins: 500 });
    const loser = await createUser({ coins: 500 });
    const season = tableMode === 'ranked'
        ? await seasonService.getCurrentSeason({ allowProvision: true })
        : null;
    const stake = buildStakeConfig(entryFee);

    const room = await Room.create({
        name: `${tableMode} room`,
        description: 'Color Clash test room',
        hostId: winner._id,
        type: 'game',
        category: 'battle',
        showInExplore: false,
        participants: [
            { userId: winner._id, role: 'host', seatIndex: -1 },
            { userId: loser._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'finished',
            tableMode,
            visibility: 'private',
            allowSpectators: false,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 3,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: {
                startingHandSize: 7,
                timeoutStrikeLimit: 3,
                customCards: {}
            },
            stake,
            seasonId: season?._id || null
        }
    });

    const match = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: entryFee > 0 ? 'pending' : 'completed',
        tableMode,
        seasonId: season?._id || null,
        configSnapshot: {
            roomGameConfig: room.gameConfig,
            roomSettings: {
                allowSpectators: false,
                countdownSec: 3,
                turnTimeoutSec: 25
            }
        },
        players: [
            {
                userId: winner._id,
                seatIndex: 0,
                usernameSnapshot: winner.username,
                avatarSnapshot: winner.avatar || '',
                status: 'finished'
            },
            {
                userId: loser._id,
                seatIndex: 1,
                usernameSnapshot: loser.username,
                avatarSnapshot: loser.avatar || '',
                status: 'finished'
            }
        ],
        currentRoundNumber: 1,
        version: 3,
        roundResult: entryFee > 0 ? null : buildRoundResult(winner, loser, { loserOutcome, timeoutStrikes })
    });

    if (entryFee > 0) {
        await settlementService.ensureEntryHoldsForMatch({
            roomId: room._id,
            matchId: match._id,
            tableMode,
            seasonId: season?._id || null,
            players: [
                { userId: winner._id, seatIndex: 0 },
                { userId: loser._id, seatIndex: 1 }
            ],
            stakeConfig: stake
        });
        await settlementService.lockEscrowsForValidStart({
            matchId: match._id,
            playerUserIds: [winner._id, loser._id]
        });
        await ColorClashMatch.findByIdAndUpdate(match._id, {
            $set: {
                status: 'completed',
                roundResult: buildRoundResult(winner, loser, { loserOutcome, timeoutStrikes })
            }
        });
    }

    return {
        room,
        match: await ColorClashMatch.findById(match._id),
        winner,
        loser,
        season
    };
};

test.before(async () => {
    replSet = await MongoMemoryReplSet.create({
        replSet: { count: 1 }
    });
    await mongoose.connect(replSet.getUri(), {
        dbName: 'color-clash-season-test'
    });
});

test.after(async () => {
    await stopApiServer();
    await mongoose.disconnect();
    if (replSet) {
        await replSet.stop();
    }
});

test.beforeEach(async () => {
    await Transaction.deleteMany({});
    await WalletEscrow.deleteMany({});
    await AuditLog.deleteMany({});
    await ColorClashMove.deleteMany({});
    await ColorClashRound.deleteMany({});
    await ColorClashMatch.deleteMany({});
    await ColorClashSeasonProgress.deleteMany({});
    await ColorClashSeason.deleteMany({});
    await AntiFraudFlag.deleteMany({});
    await Room.deleteMany({});
    await User.deleteMany({});
    await stopApiServer();
    await startApiServer();
});

test.afterEach(async () => {
    await stopApiServer();
});

test('current season resolution provisions an active season', async () => {
    const season = await seasonService.getCurrentSeason({ allowProvision: true });

    assert.ok(season);
    assert.equal(season.status, 'active');
    assert.ok(String(season.key).startsWith('color_clash-'));
    assert.ok(Array.isArray(season.tiers));
    assert.ok(season.tiers.length >= 5);
});

test('user season progress creation uses season defaults', async () => {
    const season = await seasonService.getCurrentSeason({ allowProvision: true });
    const user = await createUser();
    const progress = await seasonService.getOrCreateSeasonProgress({
        season,
        userId: user._id
    });

    assert.equal(progress.rating, season.ratingConfig.baseRating);
    assert.equal(progress.placementMatchesRemaining, season.placementMatches);
    assert.ok(progress.tierId);
});

test('ranked settlement applies rating once and updates ranked stats', async () => {
    const { match, winner, loser, season } = await createCompletedMatch({ tableMode: 'ranked' });

    const summary = await settlementService.settleMatch({ matchId: match._id });
    const refreshedMatch = await ColorClashMatch.findById(match._id).lean();
    const progresses = await ColorClashSeasonProgress.find({ seasonId: season._id }).sort({ rating: -1 }).lean();
    const winnerUser = await User.findById(winner._id).lean();
    const loserUser = await User.findById(loser._id).lean();

    assert.equal(summary.status, 'skipped');
    assert.equal(refreshedMatch.rankProgression.status, 'applied');
    assert.equal(progresses.length, 2);
    assert.ok(progresses[0].rating !== progresses[1].rating);
    assert.equal(Number(winnerUser.gameStats?.colorClash?.rankedPlayed || 0), 1);
    assert.equal(Number(winnerUser.gameStats?.colorClash?.rankedWon || 0), 1);
    assert.equal(Number(loserUser.gameStats?.colorClash?.rankedPlayed || 0), 1);
    assert.equal(Number(loserUser.gameStats?.colorClash?.rankedWon || 0), 0);
});

test('duplicate ranked application is prevented on repeated settlement', async () => {
    const { match, winner, season } = await createCompletedMatch({ tableMode: 'ranked' });

    const first = await settlementService.settleMatch({ matchId: match._id });
    const second = await settlementService.settleMatch({ matchId: match._id });
    const winnerProgress = await ColorClashSeasonProgress.findOne({
        seasonId: season._id,
        userId: winner._id
    }).lean();
    const winnerUser = await User.findById(winner._id).lean();

    assert.equal(first.rankProgression.result.alreadyApplied, false);
    assert.equal(second.rankProgression.result.alreadyApplied, true);
    assert.equal(Number(winnerUser.gameStats?.colorClash?.rankedPlayed || 0), 1);
    assert.equal(Number(winnerProgress.wins || 0), 1);
});

test('casual match settlement skips ranking and updates casual stats only', async () => {
    const { match, winner, loser } = await createCompletedMatch({ tableMode: 'casual_free' });

    const summary = await settlementService.settleMatch({ matchId: match._id });
    const winnerUser = await User.findById(winner._id).lean();
    const loserUser = await User.findById(loser._id).lean();

    assert.equal(summary.status, 'skipped');
    assert.equal(await ColorClashSeasonProgress.countDocuments({}), 0);
    assert.equal(Number(winnerUser.gameStats?.colorClash?.casualPlayed || 0), 1);
    assert.equal(Number(winnerUser.gameStats?.colorClash?.casualWon || 0), 1);
    assert.equal(Number(loserUser.gameStats?.colorClash?.rankedPlayed || 0), 0);
});

test('leaderboard Redis write and read paths stay aligned with Mongo progress', async () => {
    const { match, winner, season } = await createCompletedMatch({ tableMode: 'ranked' });
    await settlementService.settleMatch({ matchId: match._id });

    const leaderboard = await seasonService.getLeaderboard({
        seasonId: season._id,
        limit: 10,
        offset: 0,
        userId: winner._id.toString()
    });
    const redisRank = await rankingService.getColorClashUserSeasonRank({
        seasonId: season._id.toString(),
        userId: winner._id.toString()
    });

    assert.equal(leaderboard.rankings.length, 2);
    assert.ok(leaderboard.rankings[0].rating >= leaderboard.rankings[1].rating);
    assert.ok(redisRank);
    assert.equal(leaderboard.userRank.rank, redisRank.rank);
});

test('tier, division, and stars derive from rating bands deterministically', async () => {
    const season = await seasonService.getCurrentSeason({ allowProvision: true });

    const low = seasonService.deriveTierState({ season, rating: 950 });
    const high = seasonService.deriveTierState({ season, rating: 1850 });

    assert.equal(low.tierId, 'spark');
    assert.equal(high.tierId, 'zenith');
    assert.ok(low.division >= 1);
    assert.ok(high.stars >= 0);
});

test('placement matches decrement after a ranked result', async () => {
    const { match, winner, season } = await createCompletedMatch({ tableMode: 'ranked' });
    await settlementService.settleMatch({ matchId: match._id });

    const progress = await ColorClashSeasonProgress.findOne({
        seasonId: season._id,
        userId: winner._id
    }).lean();

    assert.equal(progress.placementMatchesRemaining, season.placementMatches - 1);
});

test('ranked access gating blocks guests low-level users and locked accounts', async () => {
    const guest = await createUser({ isGuest: true });
    const lowLevel = await createUser({ level: 1 });
    const locked = await createUser({
        settings: {
            colorClash: {
                equippedThemePackId: 'forest_picnic',
                ownedThemePackIds: ['forest_picnic'],
                rankedAccessLocked: true,
                rankedAccessLockReason: 'review',
                tutorialCompletedVersions: []
            }
        }
    });

    const guestJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: guest,
        body: { mode: 'ranked' }
    });
    const lowLevelJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: lowLevel,
        body: { mode: 'ranked' }
    });
    const lockedJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: locked,
        body: { mode: 'ranked' }
    });

    assert.equal(guestJoin.status, 403);
    assert.equal(guestJoin.body.error.code, 'ACCOUNT_UPGRADE_REQUIRED');
    assert.equal(lowLevelJoin.status, 403);
    assert.equal(lowLevelJoin.body.error.code, 'RANKED_LOCKED');
    assert.equal(lockedJoin.status, 403);
    assert.equal(lockedJoin.body.error.code, 'RANKED_ACCESS_LOCKED');
});

test('season current endpoint returns real season progress payload', async () => {
    const user = await createUser();

    const response = await apiRequest({
        method: 'GET',
        path: '/api/color-clash/seasons/current',
        user
    });

    assert.equal(response.status, 200);
    assert.ok(response.body.season);
    assert.ok(response.body.userProgress);
    assert.ok(Array.isArray(response.body.leaderboardPreview));
    assert.ok(Array.isArray(response.body.rewardPreview));
});

test('leaderboards endpoint returns ranked data from season progress', async () => {
    const { match, winner } = await createCompletedMatch({ tableMode: 'ranked' });
    await settlementService.settleMatch({ matchId: match._id });

    const response = await apiRequest({
        method: 'GET',
        path: '/api/color-clash/leaderboards?limit=10&offset=0',
        user: winner
    });

    assert.equal(response.status, 200);
    assert.ok(response.body.season);
    assert.equal(response.body.rankings.length, 2);
    assert.ok(response.body.userRank);
});

test('profile stats update correctly for ranked casual and stake match paths', async () => {
    const ranked = await createCompletedMatch({ tableMode: 'ranked' });
    const casual = await createCompletedMatch({ tableMode: 'casual_free' });
    const stake = await createCompletedMatch({ tableMode: 'gold_stake', entryFee: 100 });

    await settlementService.settleMatch({ matchId: ranked.match._id });
    await settlementService.settleMatch({ matchId: casual.match._id });
    await settlementService.settleMatch({ matchId: stake.match._id });

    const rankedWinner = await User.findById(ranked.winner._id).lean();
    const casualWinner = await User.findById(casual.winner._id).lean();
    const stakeWinner = await User.findById(stake.winner._id).lean();

    assert.equal(Number(rankedWinner.gameStats?.colorClash?.played || 0), 1);
    assert.equal(Number(rankedWinner.gameStats?.colorClash?.rankedPlayed || 0), 1);
    assert.equal(Number(casualWinner.gameStats?.colorClash?.casualPlayed || 0), 1);
    assert.equal(Number(casualWinner.gameStats?.colorClash?.casualWon || 0), 1);
    assert.equal(Number(stakeWinner.gameStats?.colorClash?.stakePlayed || 0), 1);
    assert.ok(Number(stakeWinner.gameStats?.colorClash?.stakeNetCoins || 0) > 0);
});
