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
const ColorClashMatch = require('../src/models/ColorClashMatch');
const ColorClashRound = require('../src/models/ColorClashRound');
const ColorClashMove = require('../src/models/ColorClashMove');
const ColorClashSeason = require('../src/models/ColorClashSeason');
const ColorClashSeasonProgress = require('../src/models/ColorClashSeasonProgress');
const WalletEscrow = require('../src/models/WalletEscrow');
const AuditLog = require('../src/models/AuditLog');
const AntiFraudFlag = require('../src/models/AntiFraudFlag');
const colorClashRoutes = require('../src/routes/colorClashRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');
const matchService = require('../src/services/colorClashMatchService');
const matchmakingService = require('../src/services/colorClashMatchmakingService');
const settlementService = require('../src/services/colorClashSettlementService');

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

    async sRem(key, ...values) {
        const set = this.sets.get(key) || new Set();
        let removed = 0;
        for (const value of values.flat()) {
            if (set.delete(value)) {
                removed += 1;
            }
        }
        this.sets.set(key, set);
        return removed;
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

const makeUsername = () => `stake_${Math.random().toString(36).slice(2, 10)}`;

const buildStakeConfig = (entryFee = 100) => ({
    currency: entryFee > 0 ? 'coins' : 'none',
    entryFee,
    payouts: [{ place: 1, bps: 10000 }],
    houseFeeBps: 500,
    sinkFeeBps: 200
});

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

const buildRoundResult = (winner, loser) => ({
    winnerSeat: 0,
    endReason: 'hand_empty',
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
            status: 'active',
            handPoints: 42,
            handCount: 3,
            timeoutStrikes: 0
        }
    ],
    scoreDeltas: [
        { seatIndex: 0, userId: winner._id, scoreDelta: 42 },
        { seatIndex: 1, userId: loser._id, scoreDelta: -42 }
    ],
    rankInputs: [
        { seatIndex: 0, userId: winner._id, placement: 1, outcome: 'win', handPointsRemaining: 0, timeoutStrikes: 0 },
        { seatIndex: 1, userId: loser._id, placement: 2, outcome: 'loss', handPointsRemaining: 42, timeoutStrikes: 0 }
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

const createPaidMatchShell = async ({ entryFee = 100, host = null, guest = null } = {}) => {
    const firstUser = host || await createUser({ coins: 500 });
    const secondUser = guest || await createUser({ coins: 500 });
    const stake = buildStakeConfig(entryFee);

    const room = await Room.create({
        name: 'Stake Shell',
        description: 'Wallet-safe test room',
        hostId: firstUser._id,
        type: 'game',
        category: 'battle',
        showInExplore: false,
        participants: [
            { userId: firstUser._id, role: 'host', seatIndex: -1 },
            { userId: secondUser._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'open',
            tableMode: 'gold_stake',
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
            stake
        }
    });

    const match = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'pending',
        tableMode: 'gold_stake',
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
                userId: firstUser._id,
                seatIndex: 0,
                usernameSnapshot: firstUser.username,
                avatarSnapshot: firstUser.avatar || '',
                status: 'active'
            },
            {
                userId: secondUser._id,
                seatIndex: 1,
                usernameSnapshot: secondUser.username,
                avatarSnapshot: secondUser.avatar || '',
                status: 'active'
            }
        ],
        currentRoundNumber: 1,
        version: 0
    });

    return {
        room,
        match,
        firstUser,
        secondUser,
        stake
    };
};

const setupStartedPaidMatch = async ({ entryFee = 100 } = {}) => {
    const host = await createUser({ coins: 500 });
    const guest = await createUser({ coins: 500 });
    const stake = buildStakeConfig(entryFee);
    const room = await Room.create({
        name: 'Started Stake Match',
        description: 'Runtime hold integration',
        hostId: host._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: host._id, role: 'host', seatIndex: -1 },
            { userId: guest._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'open',
            tableMode: 'gold_stake',
            visibility: 'private',
            allowSpectators: false,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 20,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: {
                startingHandSize: 7,
                timeoutStrikeLimit: 3
            },
            stake
        }
    });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        seatIndex: 0,
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        seatIndex: 1,
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        ready: true,
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        ready: true,
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });

    matchService.clearCountdownTimer(room._id.toString());
    const lobby = await matchService.getOrCreateLobby(room._id.toString());
    lobby.status = 'open';
    lobby.countdownEndsAt = null;
    await matchService.saveLobbyState(room._id.toString(), lobby);

    const started = await matchService.createMatchFromLobby({
        roomId: room._id.toString()
    });

    return { room, host, guest, started, stake };
};

test.before(async () => {
    replSet = await MongoMemoryReplSet.create({
        replSet: {
            count: 1
        }
    });
    await mongoose.connect(replSet.getUri(), {
        dbName: 'color-clash-settlement-test'
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

test('insufficient balance blocks paid queue entry', async () => {
    const user = await createUser({ coins: 25 });
    const response = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: {
            mode: 'gold_stake',
            stakeAmount: 50
        }
    });

    assert.equal(response.status, 403);
    assert.equal(response.body.error.code, 'INSUFFICIENT_COINS');
});

test('createEntryHold deducts once and is idempotent-safe', async () => {
    const { room, match, firstUser } = await createPaidMatchShell();

    const first = await settlementService.createEntryHold({
        userId: firstUser._id,
        roomId: room._id,
        matchId: match._id,
        amount: 100,
        tableMode: 'gold_stake'
    });
    const second = await settlementService.createEntryHold({
        userId: firstUser._id,
        roomId: room._id,
        matchId: match._id,
        amount: 100,
        tableMode: 'gold_stake'
    });

    const refreshedUser = await User.findById(firstUser._id).lean();
    assert.equal(first.duplicate, false);
    assert.equal(second.duplicate, true);
    assert.equal(Number(refreshedUser.coins || 0), 400);
    assert.equal(await WalletEscrow.countDocuments({ matchId: match._id }), 1);
    assert.equal(await Transaction.countDocuments({ 'reference.matchId': match._id, type: 'game_escrow_hold' }), 1);
});

test('refund before valid start restores held balance', async () => {
    const { room, match, firstUser } = await createPaidMatchShell();

    await settlementService.createEntryHold({
        userId: firstUser._id,
        roomId: room._id,
        matchId: match._id,
        amount: 100,
        tableMode: 'gold_stake'
    });

    const summary = await settlementService.refundHeldEscrowsForMatch({
        matchId: match._id,
        reason: 'manual_refund_test'
    });

    const refreshedUser = await User.findById(firstUser._id).lean();
    const escrow = await WalletEscrow.findOne({ matchId: match._id, userId: firstUser._id }).lean();
    assert.equal(Number(refreshedUser.coins || 0), 500);
    assert.equal(escrow.status, 'refunded');
    assert.equal(summary.status, 'refunded');
    assert.equal(summary.refundedAmount, 100);
});

test('valid start lock transitions held escrows to locked', async () => {
    const { room, match, firstUser, secondUser } = await createPaidMatchShell();

    await settlementService.ensureEntryHoldsForMatch({
        roomId: room._id,
        matchId: match._id,
        tableMode: 'gold_stake',
        players: [
            { userId: firstUser._id, seatIndex: 0 },
            { userId: secondUser._id, seatIndex: 1 }
        ],
        stakeConfig: buildStakeConfig(100)
    });

    const result = await settlementService.lockEscrowsForValidStart({
        matchId: match._id,
        playerUserIds: [firstUser._id, secondUser._id]
    });

    const escrows = await WalletEscrow.find({ matchId: match._id }).lean();
    const refreshedMatch = await ColorClashMatch.findById(match._id).lean();
    assert.equal(result.summary.status, 'locked');
    assert.equal(escrows.every((entry) => entry.status === 'locked'), true);
    assert.equal(refreshedMatch.settlement.status, 'locked');
    assert.ok(refreshedMatch.validStartedAt);
});

test('cancelled-before-start paid match refunds all held escrows', async () => {
    const { room, match, firstUser, secondUser } = await createPaidMatchShell();

    await settlementService.ensureEntryHoldsForMatch({
        roomId: room._id,
        matchId: match._id,
        tableMode: 'gold_stake',
        players: [
            { userId: firstUser._id, seatIndex: 0 },
            { userId: secondUser._id, seatIndex: 1 }
        ],
        stakeConfig: buildStakeConfig(100)
    });

    const summary = await settlementService.refundHeldEscrowsForMatch({
        matchId: match._id,
        reason: 'cancelled_before_start'
    });

    const users = await User.find({ _id: { $in: [firstUser._id, secondUser._id] } }).lean();
    assert.equal(summary.status, 'refunded');
    assert.equal(summary.refundedAmount, 200);
    assert.equal(users.every((entry) => Number(entry.coins || 0) === 500), true);
});

test('settleMatch pays winners once with correct house and sink amounts', async () => {
    const { room, match, firstUser, secondUser } = await createPaidMatchShell();

    await settlementService.ensureEntryHoldsForMatch({
        roomId: room._id,
        matchId: match._id,
        tableMode: 'gold_stake',
        players: [
            { userId: firstUser._id, seatIndex: 0 },
            { userId: secondUser._id, seatIndex: 1 }
        ],
        stakeConfig: buildStakeConfig(100)
    });
    await settlementService.lockEscrowsForValidStart({
        matchId: match._id,
        playerUserIds: [firstUser._id, secondUser._id]
    });
    await ColorClashMatch.findByIdAndUpdate(match._id, {
        $set: {
            status: 'completed',
            roundResult: buildRoundResult(firstUser, secondUser)
        }
    });

    const firstSettlement = await settlementService.settleMatch({ matchId: match._id });
    const secondSettlement = await settlementService.settleMatch({ matchId: match._id });

    const winner = await User.findById(firstUser._id).lean();
    const loser = await User.findById(secondUser._id).lean();
    assert.equal(firstSettlement.status, 'settled');
    assert.equal(firstSettlement.houseFee, 10);
    assert.equal(firstSettlement.sinkAmount, 4);
    assert.equal(firstSettlement.totalPaidOut, 186);
    assert.equal(Number(winner.coins || 0), 586);
    assert.equal(Number(loser.coins || 0), 400);
    assert.equal(secondSettlement.totalPaidOut, 186);
    assert.equal(await Transaction.countDocuments({ type: 'game_payout', 'reference.matchId': match._id }), 1);
});

test('failed settlement rolls back wallet and escrow writes', async () => {
    const { room, match, firstUser, secondUser } = await createPaidMatchShell();

    await settlementService.ensureEntryHoldsForMatch({
        roomId: room._id,
        matchId: match._id,
        tableMode: 'gold_stake',
        players: [
            { userId: firstUser._id, seatIndex: 0 },
            { userId: secondUser._id, seatIndex: 1 }
        ],
        stakeConfig: buildStakeConfig(100)
    });
    await settlementService.lockEscrowsForValidStart({
        matchId: match._id,
        playerUserIds: [firstUser._id, secondUser._id]
    });
    await ColorClashMatch.findByIdAndUpdate(match._id, {
        $set: {
            status: 'completed',
            roundResult: buildRoundResult(firstUser, secondUser)
        }
    });

    const originalAuditCreate = AuditLog.create;
    AuditLog.create = async () => {
        throw new Error('forced_audit_failure');
    };

    await assert.rejects(
        settlementService.settleMatch({ matchId: match._id }),
        /forced_audit_failure/
    );

    AuditLog.create = originalAuditCreate;

    const winner = await User.findById(firstUser._id).lean();
    const escrows = await WalletEscrow.find({ matchId: match._id }).lean();
    const refreshedMatch = await ColorClashMatch.findById(match._id).lean();
    assert.equal(Number(winner.coins || 0), 400);
    assert.equal(escrows.every((entry) => entry.status === 'locked'), true);
    assert.equal(refreshedMatch.settlement.status, 'failed');
    assert.equal(await Transaction.countDocuments({ type: 'game_payout', 'reference.matchId': match._id }), 0);
});

test('casual tables skip escrow and payout flow safely', async () => {
    const firstUser = await createUser({ coins: 500 });
    const secondUser = await createUser({ coins: 500 });
    const room = await Room.create({
        name: 'Casual Room',
        description: 'No stake',
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
            tableMode: 'casual_free',
            visibility: 'public',
            allowSpectators: true,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 3,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: { startingHandSize: 7, timeoutStrikeLimit: 3 },
            stake: buildStakeConfig(0)
        }
    });
    const match = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'completed',
        tableMode: 'casual_free',
        configSnapshot: {
            roomGameConfig: room.gameConfig
        },
        players: [
            { userId: firstUser._id, seatIndex: 0, usernameSnapshot: firstUser.username, avatarSnapshot: '', status: 'finished' },
            { userId: secondUser._id, seatIndex: 1, usernameSnapshot: secondUser.username, avatarSnapshot: '', status: 'finished' }
        ],
        roundResult: buildRoundResult(firstUser, secondUser),
        version: 3
    });

    const summary = await settlementService.settleMatch({ matchId: match._id });
    assert.equal(summary.status, 'skipped');
    assert.equal(await WalletEscrow.countDocuments({ matchId: match._id }), 0);
    assert.equal(await Transaction.countDocuments({ 'reference.matchId': match._id }), 0);
});

test('invalidated paid match refunds held escrows instead of paying out', async () => {
    const { room, match, firstUser, secondUser } = await createPaidMatchShell();

    await settlementService.ensureEntryHoldsForMatch({
        roomId: room._id,
        matchId: match._id,
        tableMode: 'gold_stake',
        players: [
            { userId: firstUser._id, seatIndex: 0 },
            { userId: secondUser._id, seatIndex: 1 }
        ],
        stakeConfig: buildStakeConfig(100)
    });
    await ColorClashMatch.findByIdAndUpdate(match._id, {
        $set: { status: 'invalidated' }
    });

    const summary = await settlementService.settleMatch({ matchId: match._id });
    const users = await User.find({ _id: { $in: [firstUser._id, secondUser._id] } }).lean();
    assert.equal(summary.status, 'refunded');
    assert.equal(users.every((entry) => Number(entry.coins || 0) === 500), true);
    assert.equal(await Transaction.countDocuments({ type: 'game_payout', 'reference.matchId': match._id }), 0);
});

test('paid queue formation creates locked escrows and deducts balances', async () => {
    const first = await createUser({ coins: 500 });
    const second = await createUser({ coins: 500 });

    const firstJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: first,
        body: { mode: 'gold_stake', stakeAmount: 50 }
    });
    const secondJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: second,
        body: { mode: 'gold_stake', stakeAmount: 50 }
    });

    assert.equal(firstJoin.status, 200);
    assert.equal(firstJoin.body.status, 'queued');
    assert.equal(secondJoin.status, 200);
    assert.equal(secondJoin.body.status, 'matched');

    const matchId = secondJoin.body.match.matchId;
    const escrows = await WalletEscrow.find({ matchId }).lean();
    const users = await User.find({ _id: { $in: [first._id, second._id] } }).lean();
    const refreshedMatch = await ColorClashMatch.findById(matchId).lean();
    assert.equal(escrows.length, 2);
    assert.equal(escrows.every((entry) => entry.status === 'locked'), true);
    assert.equal(users.every((entry) => Number(entry.coins || 0) === 450), true);
    assert.equal(refreshedMatch.settlement.status, 'locked');
});

test('valid-start lock failure refunds held escrows and invalidates the match', async () => {
    const originalLock = settlementService.lockEscrowsForValidStart.bind(settlementService);
    settlementService.lockEscrowsForValidStart = async () => {
        throw Object.assign(new Error('forced_lock_failure'), {
            code: 'FORCED_LOCK_FAILURE',
            status: 409
        });
    };

    const host = await createUser({ coins: 500 });
    const guest = await createUser({ coins: 500 });
    const stake = buildStakeConfig(100);
    const room = await Room.create({
        name: 'Failure Room',
        description: 'Start should abort safely',
        hostId: host._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: host._id, role: 'host', seatIndex: -1 },
            { userId: guest._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'open',
            tableMode: 'gold_stake',
            visibility: 'private',
            allowSpectators: false,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 3,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: { startingHandSize: 7, timeoutStrikeLimit: 3 },
            stake
        }
    });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        seatIndex: 0,
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        seatIndex: 1,
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: host._id.toString(),
        ready: true,
        profile: { username: host.username, avatar: host.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: guest._id.toString(),
        ready: true,
        profile: { username: guest.username, avatar: guest.avatar || '' }
    });

    matchService.clearCountdownTimer(room._id.toString());
    const lobby = await matchService.getOrCreateLobby(room._id.toString());
    lobby.status = 'open';
    lobby.countdownEndsAt = null;
    await matchService.saveLobbyState(room._id.toString(), lobby);

    await assert.rejects(
        matchService.createMatchFromLobby({ roomId: room._id.toString() }),
        /forced_lock_failure/
    );

    settlementService.lockEscrowsForValidStart = originalLock;

    const users = await User.find({ _id: { $in: [host._id, guest._id] } }).lean();
    const invalidatedMatch = await ColorClashMatch.findOne({ roomId: room._id }).lean();
    assert.equal(users.every((entry) => Number(entry.coins || 0) === 500), true);
    assert.equal(invalidatedMatch.status, 'invalidated');
    assert.equal(await WalletEscrow.countDocuments({ matchId: invalidatedMatch._id, status: 'refunded' }), 2);
});
