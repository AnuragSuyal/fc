process.env.JWT_SECRET = process.env.JWT_SECRET || 'color-clash-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

require('../src/models/User');
const Room = require('../src/models/Room');
const User = require('../src/models/User');
const ColorClashMatch = require('../src/models/ColorClashMatch');
const ColorClashRound = require('../src/models/ColorClashRound');
const ColorClashMove = require('../src/models/ColorClashMove');
const ColorClashSeason = require('../src/models/ColorClashSeason');
const ColorClashSeasonProgress = require('../src/models/ColorClashSeasonProgress');
const AntiFraudFlag = require('../src/models/AntiFraudFlag');
const colorClashRoutes = require('../src/routes/colorClashRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');
const matchService = require('../src/services/colorClashMatchService');
const snapshotService = require('../src/services/colorClashSnapshotService');
const matchmakingService = require('../src/services/colorClashMatchmakingService');
const { KEYS: RUNTIME_KEYS } = require('../src/services/colorClashMatchService');
const { KEYS: MATCHMAKING_KEYS } = require('../src/services/colorClashMatchmakingService');

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

    async sMembers(key) {
        return Array.from(this.sets.get(key) || []);
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

const makeUsername = () => `tester_${Math.random().toString(36).slice(2, 10)}`;

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

let mongoServer;
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

const setupStartedMatch = async ({ spectatorAllowed = true } = {}) => {
    const firstUser = await createUser({ username: makeUsername() });
    const secondUser = await createUser({ username: makeUsername() });
    const room = await Room.create({
        name: 'Started Clash Room',
        description: 'Test room',
        hostId: firstUser._id,
        type: 'game',
        category: 'battle',
        participants: [
            { userId: firstUser._id, role: 'host', seatIndex: -1 },
            { userId: secondUser._id, role: 'listener', seatIndex: -1 }
        ],
        gameConfig: {
            gameId: 'color_clash',
            lobbyStatus: 'open',
            tableMode: 'friend_room',
            visibility: 'public',
            allowSpectators: spectatorAllowed,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 20,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: {
                startingHandSize: 7,
                timeoutStrikeLimit: 3
            }
        }
    });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: firstUser._id.toString(),
        profile: { username: firstUser.username, avatar: firstUser.avatar || '' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: secondUser._id.toString(),
        profile: { username: secondUser.username, avatar: secondUser.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: firstUser._id.toString(),
        seatIndex: 0,
        profile: { username: firstUser.username, avatar: firstUser.avatar || '' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: secondUser._id.toString(),
        seatIndex: 1,
        profile: { username: secondUser.username, avatar: secondUser.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: firstUser._id.toString(),
        ready: true,
        profile: { username: firstUser.username, avatar: firstUser.avatar || '' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: secondUser._id.toString(),
        ready: true,
        profile: { username: secondUser.username, avatar: secondUser.avatar || '' }
    });

    matchService.clearCountdownTimer(room._id.toString());
    const lobby = await matchService.getOrCreateLobby(room._id.toString());
    lobby.status = 'open';
    lobby.countdownEndsAt = null;
    await matchService.saveLobbyState(room._id.toString(), lobby);

    const started = await matchService.createMatchFromLobby({
        roomId: room._id.toString()
    });

    return {
        room,
        firstUser,
        secondUser,
        started
    };
};

const setupCompletedMatch = async () => {
    const firstUser = await createUser({ username: makeUsername() });
    const secondUser = await createUser({ username: makeUsername() });
    const room = await Room.create({
        name: 'Completed Clash Room',
        description: 'Rematch room',
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
            tableMode: 'friend_room',
            visibility: 'public',
            allowSpectators: true,
            minPlayersToStart: 2,
            maxPlayers: 2,
            countdownSec: 6,
            turnTimeoutSec: 25,
            themePackId: 'forest_picnic',
            rules: {
                startingHandSize: 7,
                timeoutStrikeLimit: 3
            }
        }
    });

    const completedMatch = await ColorClashMatch.create({
        roomId: room._id,
        gameId: 'color_clash',
        status: 'completed',
        tableMode: 'friend_room',
        players: [
            {
                userId: firstUser._id,
                seatIndex: 0,
                usernameSnapshot: firstUser.username,
                avatarSnapshot: firstUser.avatar || '',
                status: 'finished'
            },
            {
                userId: secondUser._id,
                seatIndex: 1,
                usernameSnapshot: secondUser.username,
                avatarSnapshot: secondUser.avatar || '',
                status: 'finished'
            }
        ],
        version: 4,
        publicState: { currentTurnSeat: 1 }
    });

    await Room.findByIdAndUpdate(room._id, {
        $set: {
            'gameConfig.lastCompletedMatchId': completedMatch._id,
            'gameConfig.activeMatchId': null,
            'gameConfig.lobbyStatus': 'finished'
        }
    });

    let lobby = matchService.buildLobbyFromRoom({
        _id: room._id,
        gameConfig: room.gameConfig
    });
    lobby.status = 'finished';
    lobby.playersByUserId[firstUser._id.toString()] = {
        userId: firstUser._id.toString(),
        username: firstUser.username,
        avatar: firstUser.avatar || '',
        seatIndex: 0,
        ready: false,
        role: 'player',
        joinedAtMs: Date.now(),
        lastSeenAtMs: Date.now()
    };
    lobby.playersByUserId[secondUser._id.toString()] = {
        userId: secondUser._id.toString(),
        username: secondUser.username,
        avatar: secondUser.avatar || '',
        seatIndex: 1,
        ready: false,
        role: 'player',
        joinedAtMs: Date.now(),
        lastSeenAtMs: Date.now()
    };
    await matchService.saveLobbyState(room._id.toString(), lobby);

    return {
        room,
        firstUser,
        secondUser,
        completedMatch
    };
};

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), {
        dbName: 'color-clash-api-test'
    });
});

test.after(async () => {
    await stopApiServer();
    await mongoose.disconnect();
    if (mongoServer) {
        await mongoServer.stop();
    }
});

test.beforeEach(async () => {
    await Room.deleteMany({});
    await User.deleteMany({});
    await ColorClashMatch.deleteMany({});
    await ColorClashRound.deleteMany({});
    await ColorClashMove.deleteMany({});
    await ColorClashSeasonProgress.deleteMany({});
    await ColorClashSeason.deleteMany({});
    await AntiFraudFlag.deleteMany({});
    await stopApiServer();
    await startApiServer();
});

test.afterEach(async () => {
    await stopApiServer();
});

test('create friend room returns lobby shell', async () => {
    const user = await createUser();
    const response = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user,
        body: {
            name: 'My Clash Room',
            visibility: 'invite_only',
            maxPlayers: 4,
            themePackId: 'forest_picnic'
        }
    });

    assert.equal(response.status, 201);
    assert.equal(response.body.room.name, 'My Clash Room');
    assert.equal(response.body.room.tableMode, 'friend_room');
    assert.equal(response.body.viewerRole, 'player');
    assert.equal(response.body.lobby.status, 'open');
});

test('join friend room adds player to lobby', async () => {
    const host = await createUser();
    const guest = await createUser();

    const created = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Public Clash',
            visibility: 'public'
        }
    });

    const joined = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/join`,
        user: guest,
        body: {
            spectator: false
        }
    });

    assert.equal(joined.status, 200);
    assert.equal(joined.body.viewerRole, 'player');
    assert.ok(joined.body.lobby.playersByUserId[guest._id.toString()]);
});

test('spectator join respects allowSpectators', async () => {
    const host = await createUser();
    const viewer = await createUser();

    const allowedRoom = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Spectator On',
            visibility: 'public',
            allowSpectators: true
        }
    });
    const allowedJoin = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${allowedRoom.body.room.roomId}/join`,
        user: viewer,
        body: { spectator: true }
    });
    assert.equal(allowedJoin.status, 200);
    assert.equal(allowedJoin.body.viewerRole, 'spectator');

    const deniedRoom = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Spectator Off',
            visibility: 'public',
            allowSpectators: false
        }
    });
    const deniedJoin = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${deniedRoom.body.room.roomId}/join`,
        user: viewer,
        body: { spectator: true }
    });

    assert.equal(deniedJoin.status, 403);
    assert.equal(deniedJoin.body.error.code, 'SPECTATORS_DISABLED');
});

test('matchmaking join creates queue ticket', async () => {
    const user = await createUser();
    const response = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: { mode: 'casual_free' }
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.status, 'queued');
    assert.ok(response.body.queueTicketId);
    assert.ok(await redis.get(MATCHMAKING_KEYS.user(user._id.toString())));
});

test('duplicate matchmaking join is deduped safely', async () => {
    const user = await createUser();

    const first = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: { mode: 'casual_free' }
    });
    const second = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: { mode: 'casual_free' }
    });

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(second.body.duplicate, true);
    assert.equal(second.body.queueTicketId, first.body.queueTicketId);
});

test('leave matchmaking removes active ticket', async () => {
    const user = await createUser();

    const joined = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user,
        body: { mode: 'casual_free' }
    });
    const left = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/leave',
        user,
        body: { queueTicketId: joined.body.queueTicketId }
    });

    assert.equal(left.status, 200);
    assert.equal(left.body.removed, true);
    assert.equal(await redis.get(MATCHMAKING_KEYS.user(user._id.toString())), null);
});

test('matched queue users create room and active match', async () => {
    const first = await createUser();
    const second = await createUser();

    const firstJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: first,
        body: { mode: 'casual_free' }
    });
    const secondJoin = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/matchmaking/join',
        user: second,
        body: { mode: 'casual_free' }
    });

    assert.equal(firstJoin.status, 200);
    assert.equal(firstJoin.body.status, 'queued');
    assert.equal(secondJoin.status, 200);
    assert.equal(secondJoin.body.status, 'matched');
    assert.ok(secondJoin.body.room.roomId);
    assert.ok(secondJoin.body.match.matchId);

    const rooms = await Room.find({ type: 'game', 'gameConfig.gameId': 'color_clash' }).lean();
    const matches = await ColorClashMatch.find({ status: 'active' }).lean();
    assert.equal(rooms.length, 1);
    assert.equal(matches.length, 1);
});

test('ready endpoint triggers countdown-compatible lobby state', async () => {
    const host = await createUser();
    const guest = await createUser();

    const created = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Countdown Room',
            visibility: 'public'
        }
    });

    await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/join`,
        user: guest,
        body: { spectator: false }
    });

    await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/ready`,
        user: host,
        body: { ready: true, seatIndex: 0 }
    });
    const readyGuest = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/ready`,
        user: guest,
        body: { ready: true, seatIndex: 1 }
    });

    assert.equal(readyGuest.status, 200);
    assert.equal(readyGuest.body.lobby.status, 'countdown');
    assert.ok(readyGuest.body.lobby.countdownEndsAt > Date.now());
});

test('lobby fetch enforces access control', async () => {
    const host = await createUser();
    const outsider = await createUser();

    const created = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Locked Lobby',
            visibility: 'invite_only',
            allowSpectators: false
        }
    });

    const response = await apiRequest({
        method: 'GET',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/lobby`,
        user: outsider
    });

    assert.equal(response.status, 403);
    assert.equal(response.body.error.code, 'SPECTATORS_DISABLED');
});

test('match snapshot access control blocks unauthorized spectator', async () => {
    const { started, firstUser } = await setupStartedMatch({ spectatorAllowed: false });
    const outsider = await createUser();

    const playerSnapshot = await apiRequest({
        method: 'GET',
        path: `/api/color-clash/matches/${started.matchId}/snapshot`,
        user: firstUser
    });
    const outsiderSnapshot = await apiRequest({
        method: 'GET',
        path: `/api/color-clash/matches/${started.matchId}/snapshot`,
        user: outsider
    });

    assert.equal(playerSnapshot.status, 200);
    assert.equal(Boolean(playerSnapshot.body.privateState), true);
    assert.equal(outsiderSnapshot.status, 403);
});

test('settlement summary endpoint returns authorized match settlement shape', async () => {
    const { firstUser, completedMatch } = await setupCompletedMatch();

    const response = await apiRequest({
        method: 'GET',
        path: `/api/color-clash/matches/${completedMatch._id}/settlement`,
        user: firstUser
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.matchId, completedMatch._id.toString());
    assert.equal(typeof response.body.status, 'string');
    assert.equal(Array.isArray(response.body.payouts), true);
});

test('reconnect endpoint returns replay payload when available', async () => {
    const { firstUser, secondUser, started } = await setupStartedMatch();
    const snapshot = await snapshotService.getMatchSnapshot(started.matchId, firstUser._id.toString(), 'player');
    const move = snapshot.privateState.legalMoves.find((entry) => entry.type === 'play_card') || snapshot.privateState.legalMoves[0];

    await matchService.submitMove({
        matchId: started.matchId,
        userId: firstUser._id.toString(),
        clientMoveId: 'reconnect-move',
        expectedVersion: 1,
        move
    });

    const reconnect = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/matches/${started.matchId}/reconnect`,
        user: secondUser,
        body: { lastKnownVersion: 1 }
    });

    assert.equal(reconnect.status, 200);
    assert.equal(reconnect.body.mode, 'replay');
    assert.ok(reconnect.body.replay.length >= 1);
});

test('rematch vote endpoint creates a new match when all players agree', async () => {
    const { firstUser, secondUser, completedMatch } = await setupCompletedMatch();

    const firstVote = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/matches/${completedMatch._id}/rematch`,
        user: firstUser,
        body: { vote: true }
    });
    const secondVote = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/matches/${completedMatch._id}/rematch`,
        user: secondUser,
        body: { vote: true }
    });

    assert.equal(firstVote.status, 200);
    assert.equal(firstVote.body.status, 'waiting');
    assert.equal(secondVote.status, 200);
    assert.equal(secondVote.body.status, 'matched');
    assert.notEqual(secondVote.body.matchId, completedMatch._id.toString());
});

test('home endpoint returns sane payload shape', async () => {
    const user = await createUser();
    const response = await apiRequest({
        method: 'GET',
        path: '/api/color-clash/home',
        user
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.gameId, 'color_clash');
    assert.ok(Array.isArray(response.body.queuePresets));
    assert.ok(response.body.themes);
    assert.ok(response.body.tutorial);
    assert.ok(Object.prototype.hasOwnProperty.call(response.body, 'activeMatch'));
    assert.equal(typeof response.body.userProgress?.eligibility?.riskState?.severity, 'string');
    assert.equal(
        Object.prototype.hasOwnProperty.call(
            response.body.userProgress?.eligibility?.riskState || {},
            'score'
        ),
        false
    );
});

test('tables endpoint returns queue presets and public rooms', async () => {
    const host = await createUser();
    const viewer = await createUser();

    await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        body: {
            name: 'Discoverable Clash',
            visibility: 'public'
        }
    });

    const response = await apiRequest({
        method: 'GET',
        path: '/api/color-clash/tables?limit=10',
        user: viewer
    });

    assert.equal(response.status, 200);
    assert.ok(Array.isArray(response.body.queuePresets));
    assert.ok(Array.isArray(response.body.rooms));
    assert.ok(response.body.rooms.some((room) => room.name === 'Discoverable Clash'));
});

test('lobby payload strips internal player risk context fields', async () => {
    const host = await createUser();
    const guest = await createUser();

    const created = await apiRequest({
        method: 'POST',
        path: '/api/color-clash/rooms',
        user: host,
        headers: { 'x-forwarded-for': '10.20.30.40' },
        body: {
            name: 'Privacy Clash',
            visibility: 'public'
        }
    });

    const joined = await apiRequest({
        method: 'POST',
        path: `/api/color-clash/rooms/${created.body.room.roomId}/join`,
        user: guest,
        headers: { 'x-forwarded-for': '10.20.30.41' },
        body: {}
    });

    assert.equal(joined.status, 200);
    const hostEntry = joined.body.lobby.playersByUserId[host._id.toString()];
    const guestEntry = joined.body.lobby.playersByUserId[guest._id.toString()];
    assert.ok(hostEntry);
    assert.ok(guestEntry);
    assert.equal(Object.prototype.hasOwnProperty.call(hostEntry, 'ipHash'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(hostEntry, 'deviceHash'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(guestEntry, 'ipHash'), false);
    assert.equal(Object.prototype.hasOwnProperty.call(guestEntry, 'deviceHash'), false);
});
