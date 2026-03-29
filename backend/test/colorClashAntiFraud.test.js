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
const antiFraudService = require('../src/services/colorClashAntiFraudService');
const { hashValue } = require('../src/services/colorClashAntiFraudService');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.strings = new Map();
        this.lists = new Map();
        this.sets = new Map();
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
            if (this.lists.delete(key)) removed += 1;
            if (this.sets.delete(key)) removed += 1;
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

    async rPush(key, value) {
        const list = this.lists.get(key) || [];
        list.push(value);
        this.lists.set(key, list);
        return list.length;
    }

    async lRange(key, start, stop) {
        const list = this.lists.get(key) || [];
        if (!list.length) return [];
        const normalized = normalizeRange(list.length, start, stop);
        return list.slice(normalized.start, normalized.stop + 1);
    }

    async lTrim(key, start, stop) {
        const list = this.lists.get(key) || [];
        if (!list.length) return 'OK';
        const normalized = normalizeRange(list.length, start, stop);
        this.lists.set(key, list.slice(normalized.start, normalized.stop + 1));
        return 'OK';
    }

    async sAdd(key, ...values) {
        const set = this.sets.get(key) || new Set();
        let added = 0;
        for (const value of values.flat()) {
            if (!set.has(value)) {
                set.add(value);
                added += 1;
            }
        }
        this.sets.set(key, set);
        return added;
    }

    async sCard(key) {
        return (this.sets.get(key) || new Set()).size;
    }

    async zAdd(key, entries) {
        const zset = this.sortedSets.get(key) || new Map();
        for (const entry of entries) {
            zset.set(entry.value, Number(entry.score));
        }
        this.sortedSets.set(key, zset);
        return entries.length;
    }

    async zRange(key, start, stop) {
        const zset = this.sortedSets.get(key) || new Map();
        const sorted = Array.from(zset.entries())
            .sort((left, right) => left[1] - right[1] || left[0].localeCompare(right[0]))
            .map(([value]) => value);
        if (!sorted.length) return [];
        const normalized = normalizeRange(sorted.length, start, stop);
        return sorted.slice(normalized.start, normalized.stop + 1);
    }

    async zRem(key, ...members) {
        const zset = this.sortedSets.get(key) || new Map();
        let removed = 0;
        for (const member of members.flat()) {
            if (zset.delete(member)) {
                removed += 1;
            }
        }
        this.sortedSets.set(key, zset);
        return removed;
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

const normalizeRange = (length, start, stop) => {
    let safeStart = start < 0 ? Math.max(length + start, 0) : Math.min(start, length - 1);
    let safeStop = stop < 0 ? length + stop : Math.min(stop, length - 1);
    if (safeStop < 0) safeStop = -1;
    if (safeStart < 0) safeStart = 0;
    if (safeStop < safeStart) {
        return { start: 0, stop: -1 };
    }
    return { start: safeStart, stop: safeStop };
};

const clearRuntimeTimers = () => {
    for (const timer of matchService.countdownTimers.values()) clearTimeout(timer);
    for (const timer of matchService.turnTimers.values()) clearTimeout(timer);
    matchService.countdownTimers.clear();
    matchService.turnTimers.clear();
};

const makeUsername = () => `risk_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 6,
    coins: overrides.coins ?? 600,
    isGuest: overrides.isGuest ?? false,
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`,
    settings: overrides.settings,
    gameStats: overrides.gameStats
});

const buildRoundResult = ({ winner, loser, loserOutcome = 'loss', timeoutStrikes = 0 }) => ({
    winnerSeat: 0,
    endReason: loserOutcome === 'forfeit' ? 'forfeit' : 'hand_empty',
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
            status: loserOutcome === 'forfeit' ? 'forfeited' : 'active',
            handPoints: 34,
            handCount: 3,
            timeoutStrikes
        }
    ],
    scoreDeltas: [
        { seatIndex: 0, userId: winner._id, scoreDelta: 34 },
        { seatIndex: 1, userId: loser._id, scoreDelta: -34 }
    ],
    rankInputs: [
        { seatIndex: 0, userId: winner._id, placement: 1, outcome: 'win', handPointsRemaining: 0, timeoutStrikes: 0, status: 'active' },
        {
            seatIndex: 1,
            userId: loser._id,
            placement: 2,
            outcome: loserOutcome,
            handPointsRemaining: 34,
            timeoutStrikes,
            status: loserOutcome === 'forfeit' ? 'forfeited' : 'active'
        }
    ]
});

const createCompetitiveMatch = async ({
    players,
    tableMode = 'ranked',
    entryFee = 0,
    winnerIndex = 0,
    loserOutcome = 'loss',
    timeoutStrikes = 0,
    endedAt = new Date(),
    ipHashes = []
} = {}) => {
    const [firstUser, secondUser] = players;
    const winner = players[winnerIndex];
    const loser = players[winnerIndex === 0 ? 1 : 0];
    const room = await Room.create({
        name: 'Risk Match',
        description: 'Risk test room',
        hostId: firstUser._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: firstUser._id, role: 'host', seatIndex: -1 },
            { userId: secondUser._id, role: 'listener', seatIndex: -1 }
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
                timeoutStrikeLimit: 3
            },
            stake: {
                currency: entryFee > 0 ? 'coins' : 'none',
                entryFee
            }
        }
    });

    return ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'completed',
        tableMode,
        configSnapshot: {
            roomGameConfig: room.gameConfig
        },
        players: [
            { userId: firstUser._id, seatIndex: 0, usernameSnapshot: firstUser.username, avatarSnapshot: '', status: 'finished' },
            { userId: secondUser._id, seatIndex: 1, usernameSnapshot: secondUser.username, avatarSnapshot: '', status: 'finished' }
        ],
        playerContexts: [
            { userId: firstUser._id, ipHash: ipHashes[0] || null, region: firstUser.region || 'Global' },
            { userId: secondUser._id, ipHash: ipHashes[1] || null, region: secondUser.region || 'Global' }
        ],
        roundResult: buildRoundResult({
            winner,
            loser,
            loserOutcome,
            timeoutStrikes
        }),
        settlement: {
            status: entryFee > 0 ? 'settled' : 'skipped',
            settlementKey: `settle:${new mongoose.Types.ObjectId()}`,
            currency: entryFee > 0 ? 'coins' : 'none',
            entryFee,
            totalEscrowed: entryFee > 0 ? entryFee * 2 : 0,
            grossPool: entryFee > 0 ? entryFee * 2 : 0,
            totalPaidOut: entryFee > 0 ? entryFee * 2 : 0,
            settledAt: endedAt
        },
        startedAt: new Date(endedAt.getTime() - 60 * 1000),
        endedAt,
        version: 3
    });
};

const createRefundedMatch = async ({ user, opponent, refundedAt, entryFee = 50 } = {}) => {
    const room = await Room.create({
        name: 'Refund Match',
        description: 'Refund risk',
        hostId: user._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: user._id, role: 'host', seatIndex: -1 },
            { userId: opponent._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'cancelled',
            tableMode: 'gold_stake',
            visibility: 'private',
            allowSpectators: false,
            minPlayersToStart: 2,
            maxPlayers: 2,
            stake: {
                currency: 'coins',
                entryFee
            }
        }
    });

    const match = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'cancelled',
        tableMode: 'gold_stake',
        configSnapshot: {
            roomGameConfig: room.gameConfig
        },
        players: [
            { userId: user._id, seatIndex: 0, usernameSnapshot: user.username, avatarSnapshot: '', status: 'finished' },
            { userId: opponent._id, seatIndex: 1, usernameSnapshot: opponent.username, avatarSnapshot: '', status: 'finished' }
        ],
        settlement: {
            status: 'refunded',
            settlementKey: `refund:${new mongoose.Types.ObjectId()}`,
            currency: 'coins',
            entryFee,
            refundedAmount: entryFee,
            refundedAt
        },
        endedAt: refundedAt,
        version: 1
    });

    await WalletEscrow.create({
        userId: user._id,
        roomId: room._id,
        matchId: match._id,
        currency: 'coins',
        amount: entryFee,
        status: 'refunded',
        reason: 'queue_stake',
        idempotencyKey: `refund:${match._id}:${user._id}`,
        refundedAt,
        heldAt: new Date(refundedAt.getTime() - 60 * 1000),
        balanceBefore: 600,
        balanceAfterHold: 550
    });

    return match;
};

const createLockedPaidMatch = async () => {
    const winner = await createUser({ coins: 400 });
    const loser = await createUser({ coins: 400 });
    const room = await Room.create({
        name: 'Settlement Risk Match',
        description: 'Fraud failure should not break settlement',
        hostId: winner._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: winner._id, role: 'host', seatIndex: -1 },
            { userId: loser._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'finished',
            tableMode: 'gold_stake',
            visibility: 'private',
            allowSpectators: false,
            minPlayersToStart: 2,
            maxPlayers: 2,
            stake: {
                currency: 'coins',
                entryFee: 100,
                payouts: [{ place: 1, bps: 10000 }],
                houseFeeBps: 500,
                sinkFeeBps: 200
            }
        }
    });

    const match = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'completed',
        tableMode: 'gold_stake',
        configSnapshot: {
            roomGameConfig: room.gameConfig
        },
        players: [
            { userId: winner._id, seatIndex: 0, usernameSnapshot: winner.username, avatarSnapshot: '', status: 'finished' },
            { userId: loser._id, seatIndex: 1, usernameSnapshot: loser.username, avatarSnapshot: '', status: 'finished' }
        ],
        roundResult: buildRoundResult({ winner, loser }),
        settlement: {
            status: 'locked',
            settlementKey: `locked:${new mongoose.Types.ObjectId()}`,
            currency: 'coins',
            entryFee: 100,
            totalEscrowed: 200
        },
        version: 5
    });

    await WalletEscrow.create([
        {
            userId: winner._id,
            roomId: room._id,
            matchId: match._id,
            currency: 'coins',
            amount: 100,
            status: 'locked',
            reason: 'queue_stake',
            idempotencyKey: `hold:${match._id}:${winner._id}`,
            heldAt: new Date(Date.now() - 60 * 1000),
            lockedAt: new Date(Date.now() - 30 * 1000),
            balanceBefore: 500,
            balanceAfterHold: 400
        },
        {
            userId: loser._id,
            roomId: room._id,
            matchId: match._id,
            currency: 'coins',
            amount: 100,
            status: 'locked',
            reason: 'queue_stake',
            idempotencyKey: `hold:${match._id}:${loser._id}`,
            heldAt: new Date(Date.now() - 60 * 1000),
            lockedAt: new Date(Date.now() - 30 * 1000),
            balanceBefore: 500,
            balanceAfterHold: 400
        }
    ]);

    return { winner, loser, match };
};

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
    antiFraudService.configure({});

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
    baseUrl = `http://127.0.0.1:${server.address().port}`;
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
    return {
        status: response.status,
        body: await response.json()
    };
};

test.before(async () => {
    replSet = await MongoMemoryReplSet.create({
        replSet: { count: 1 }
    });
    await mongoose.connect(replSet.getUri(), {
        dbName: 'color-clash-anti-fraud-test'
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
    await AntiFraudFlag.deleteMany({});
    await ColorClashMove.deleteMany({});
    await ColorClashRound.deleteMany({});
    await ColorClashMatch.deleteMany({});
    await ColorClashSeasonProgress.deleteMany({});
    await ColorClashSeason.deleteMany({});
    await Room.deleteMany({});
    await User.deleteMany({});
    await stopApiServer();
    await startApiServer();
});

test.afterEach(async () => {
    await stopApiServer();
});

test('repeated pairing creates a fraud flag', async () => {
    const first = await createUser();
    const second = await createUser();

    for (let index = 0; index < 8; index += 1) {
        await createCompetitiveMatch({
            players: [first, second],
            tableMode: 'ranked',
            winnerIndex: index % 2,
            endedAt: new Date(Date.now() - ((8 - index) * 60 * 1000))
        });
    }

    const currentMatch = await ColorClashMatch.findOne().sort({ endedAt: -1 });
    await antiFraudService.recordMatchOutcomeSignals({ matchId: currentMatch._id });

    const flag = await AntiFraudFlag.findOne({ flagType: 'repeated_pairing' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'medium');
  });

test('same-IP suspicious pairing creates a fraud flag', async () => {
    const first = await createUser();
    const second = await createUser();
    const sharedIpHash = hashValue('10.10.10.10');

    for (let index = 0; index < 8; index += 1) {
        await createCompetitiveMatch({
            players: [first, second],
            tableMode: 'ranked',
            winnerIndex: index % 2,
            ipHashes: [sharedIpHash, sharedIpHash],
            endedAt: new Date(Date.now() - ((8 - index) * 60 * 1000))
        });
    }

    const currentMatch = await ColorClashMatch.findOne().sort({ endedAt: -1 });
    await antiFraudService.recordMatchOutcomeSignals({ matchId: currentMatch._id });

    const flag = await AntiFraudFlag.findOne({ flagType: 'same_ip_pairing' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'high');
  });

test('timeout abuse creates a fraud flag', async () => {
    const target = await createUser();
    const opponents = [];
    for (let index = 0; index < 10; index += 1) {
        opponents.push(await createUser());
    }

    let currentMatch = null;
    for (let index = 0; index < 10; index += 1) {
        currentMatch = await createCompetitiveMatch({
            players: [opponents[index], target],
            tableMode: 'ranked',
            winnerIndex: 0,
            timeoutStrikes: index < 4 ? 1 : 0,
            endedAt: new Date(Date.now() - ((10 - index) * 60 * 1000))
        });
    }

    await antiFraudService.recordTimeoutSignal({ matchId: currentMatch._id, userId: target._id });
    const flag = await AntiFraudFlag.findOne({ flagType: 'timeout_abuse' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'medium');
});

test('surrender abuse creates a fraud flag', async () => {
    const target = await createUser();
    const opponents = [];
    for (let index = 0; index < 10; index += 1) {
        opponents.push(await createUser());
    }

    let currentMatch = null;
    for (let index = 0; index < 10; index += 1) {
        currentMatch = await createCompetitiveMatch({
            players: [opponents[index], target],
            tableMode: 'ranked',
            winnerIndex: 0,
            loserOutcome: index < 4 ? 'forfeit' : 'loss',
            endedAt: new Date(Date.now() - ((10 - index) * 60 * 1000))
        });
    }

    await antiFraudService.recordForfeitSignal({ matchId: currentMatch._id, userId: target._id });
    const flag = await AntiFraudFlag.findOne({ flagType: 'surrender_abuse' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'medium');
});

test('refund abuse creates a fraud flag', async () => {
    const target = await createUser();
    const firstOpponent = await createUser();
    const secondOpponent = await createUser();
    const thirdOpponent = await createUser();

    await createRefundedMatch({
        user: target,
        opponent: firstOpponent,
        refundedAt: new Date(Date.now() - (40 * 60 * 1000))
    });
    await createRefundedMatch({
        user: target,
        opponent: secondOpponent,
        refundedAt: new Date(Date.now() - (20 * 60 * 1000))
    });
    const currentMatch = await createRefundedMatch({
        user: target,
        opponent: thirdOpponent,
        refundedAt: new Date()
    });

    await antiFraudService.recordRefundSignal({ matchId: currentMatch._id });
    const flag = await AntiFraudFlag.findOne({ flagType: 'refund_abuse' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'medium');
});

test('low opponent diversity creates a fraud flag', async () => {
    const target = await createUser();
    const opponents = [await createUser(), await createUser(), await createUser()];

    let currentMatch = null;
    for (let index = 0; index < 10; index += 1) {
        currentMatch = await createCompetitiveMatch({
            players: [target, opponents[index % 3]],
            tableMode: 'ranked',
            winnerIndex: index % 2,
            endedAt: new Date(Date.now() - ((10 - index) * 60 * 1000))
        });
    }

    await antiFraudService.recordMatchOutcomeSignals({ matchId: currentMatch._id });
    const flag = await AntiFraudFlag.findOne({ flagType: 'low_opponent_diversity' }).lean();
    assert.ok(flag);
    assert.equal(flag.severity, 'medium');
});

test('high severity can apply ranked_lock and stake_lock', async () => {
    const rankedA = await createUser();
    const rankedB = await createUser();

    for (let index = 0; index < 12; index += 1) {
        await createCompetitiveMatch({
            players: [rankedA, rankedB],
            tableMode: 'ranked',
            winnerIndex: 0,
            endedAt: new Date(Date.now() - ((12 - index) * 60 * 1000))
        });
    }

    const rankedCurrent = await ColorClashMatch.findOne({ tableMode: 'ranked' }).sort({ endedAt: -1 });
    await antiFraudService.recordMatchOutcomeSignals({ matchId: rankedCurrent._id });

    const rankedUser = await User.findById(rankedA._id).lean();
    assert.equal(Boolean(rankedUser.settings?.colorClash?.rankedLock?.active), true);

    const stakeTarget = await createUser();
    const stakeOpponents = [await createUser(), await createUser(), await createUser(), await createUser(), await createUser()];
    let currentRefundMatch = null;
    for (let index = 0; index < 5; index += 1) {
        currentRefundMatch = await createRefundedMatch({
            user: stakeTarget,
            opponent: stakeOpponents[index],
            refundedAt: new Date(Date.now() - ((5 - index) * 30 * 60 * 1000))
        });
    }

    await antiFraudService.recordRefundSignal({ matchId: currentRefundMatch._id });
    const stakeUser = await User.findById(stakeTarget._id).lean();
    assert.equal(Boolean(stakeUser.settings?.colorClash?.stakeLock?.active), true);
});

test('low severity logs without applying locks', async () => {
    const user = await createUser();
    const result = await antiFraudService.maybeCreateFlag({
        signal: {
            flagType: 'timeout_abuse',
            severity: 'low',
            score: 10,
            subjectType: 'user',
            subjectId: user._id.toString(),
            userIds: [user._id],
            evidence: {
                sampleSize: 2,
                timeoutMatches: 1
            }
        },
        scope: 'ranked'
    });

    const refreshedUser = await User.findById(user._id).lean();
    assert.equal(result.logged, true);
    assert.equal(await AntiFraudFlag.countDocuments({}), 0);
    assert.equal(Boolean(refreshedUser.settings?.colorClash?.rankedLock?.active), false);
    assert.equal(await AuditLog.countDocuments({ action: 'fraud_signal_logged' }), 1);
});

test('matchmaking join is blocked when ranked lock is active', async () => {
    const user = await createUser({
        settings: {
            colorClash: {
                rankedLock: {
                    active: true,
                    reason: 'Risk review',
                    flagId: null,
                    appliedAt: new Date()
                },
                rankedAccessLocked: true,
                rankedAccessLockReason: 'Risk review'
            }
        }
    });

    const response = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: { mode: 'ranked' }
    });

    assert.equal(response.status, 403);
    assert.equal(response.body.error.code, 'RANKED_ACCESS_LOCKED');
});

test('fraud service failure does not break settlement finalization', async () => {
    const { winner, match } = await createLockedPaidMatch();
    const originalHandler = antiFraudService.recordMatchOutcomeSignals;
    antiFraudService.recordMatchOutcomeSignals = async () => {
        throw Object.assign(new Error('forced_risk_failure'), { code: 'FORCED_RISK_FAILURE' });
    };

    const summary = await settlementService.settleMatch({ matchId: match._id });

    antiFraudService.recordMatchOutcomeSignals = originalHandler;

    const refreshedMatch = await ColorClashMatch.findById(match._id).lean();
    const refreshedWinner = await User.findById(winner._id).lean();
    assert.equal(summary.status, 'settled');
    assert.equal(refreshedMatch.settlement.status, 'settled');
    assert.equal(refreshedMatch.riskEvaluation.error, 'FORCED_RISK_FAILURE');
    assert.equal(Number(refreshedWinner.coins || 0), 586);
});

test('audit logs are created for fraud flags and auto actions', async () => {
    const first = await createUser();
    const second = await createUser();

    for (let index = 0; index < 12; index += 1) {
        await createCompetitiveMatch({
            players: [first, second],
            tableMode: 'ranked',
            winnerIndex: 0,
            endedAt: new Date(Date.now() - ((12 - index) * 60 * 1000))
        });
    }

    const currentMatch = await ColorClashMatch.findOne({ tableMode: 'ranked' }).sort({ endedAt: -1 });
    await antiFraudService.recordMatchOutcomeSignals({ matchId: currentMatch._id });

    const auditActions = await AuditLog.find({}).select('action').lean();
    const actions = new Set(auditActions.map((entry) => entry.action));
    assert.equal(actions.has('fraud_flag_created'), true);
    assert.equal(actions.has('risk_auto_action_applied'), true);
});
