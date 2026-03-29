const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

require('../src/models/User');
const Room = require('../src/models/Room');
const ColorClashMatch = require('../src/models/ColorClashMatch');
const ColorClashRound = require('../src/models/ColorClashRound');
const ColorClashMove = require('../src/models/ColorClashMove');
const matchService = require('../src/services/colorClashMatchService');
const snapshotService = require('../src/services/colorClashSnapshotService');
const { KEYS } = require('../src/services/colorClashMatchService');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.strings = new Map();
        this.lists = new Map();
        this.sets = new Map();
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
        }
        return removed;
    }

    async expire() {
        return 1;
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

    find(eventName) {
        return this.events.filter((entry) => entry.event === eventName);
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

let mongoServer;

const makeUserId = () => new mongoose.Types.ObjectId();

const createGameRoom = async ({
    userIds,
    countdownSec = 30,
    allowSpectators = true,
    maxPlayers = 4
}) => Room.create({
    name: 'Color Clash Room',
    description: 'Runtime test room',
    hostId: userIds[0],
    type: 'game',
    category: 'battle',
    participants: userIds.map((userId, index) => ({
        userId,
        role: index === 0 ? 'host' : 'listener'
    })),
    gameConfig: {
        gameId: 'color_clash',
        lobbyStatus: 'open',
        tableMode: 'friend_room',
        visibility: 'private',
        allowSpectators,
        minPlayersToStart: 2,
        maxPlayers,
        countdownSec,
        turnTimeoutSec: 25,
        rules: {
            startingHandSize: 7,
            timeoutStrikeLimit: 3
        }
    }
});

const configureRuntime = () => {
    const redis = new FakeRedis();
    const io = new FakeIo();
    for (const timer of matchService.countdownTimers.values()) clearTimeout(timer);
    for (const timer of matchService.turnTimers.values()) clearTimeout(timer);
    matchService.countdownTimers.clear();
    matchService.turnTimers.clear();
    matchService.configure({ redis, io });
    return { redis, io };
};

const setupStartedMatch = async ({ spectatorAllowed = true } = {}) => {
    const userIds = [makeUserId(), makeUserId(), makeUserId(), makeUserId()];
    const room = await createGameRoom({
        userIds,
        allowSpectators: spectatorAllowed
    });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        profile: { username: 'Beta', avatar: 'b.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        seatIndex: 0,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        seatIndex: 1,
        profile: { username: 'Beta', avatar: 'b.png' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        ready: true,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        ready: true,
        profile: { username: 'Beta', avatar: 'b.png' }
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
        userIds,
        started
    };
};

const firstPlayableMove = async (matchId, userId) => {
    const snapshot = await snapshotService.getMatchSnapshot(matchId, userId, 'player');
    return snapshot.privateState.legalMoves.find((move) => move.type === 'play_card') ||
        snapshot.privateState.legalMoves[0];
};

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), {
        dbName: 'color-clash-runtime-test'
    });
});

test.after(async () => {
    for (const timer of matchService.countdownTimers.values()) clearTimeout(timer);
    for (const timer of matchService.turnTimers.values()) clearTimeout(timer);
    await mongoose.disconnect();
    if (mongoServer) {
        await mongoServer.stop();
    }
});

test.beforeEach(async () => {
    configureRuntime();
    await Room.deleteMany({});
    await ColorClashMatch.deleteMany({});
    await ColorClashRound.deleteMany({});
    await ColorClashMove.deleteMany({});
});

test.afterEach(() => {
    for (const timer of matchService.countdownTimers.values()) clearTimeout(timer);
    for (const timer of matchService.turnTimers.values()) clearTimeout(timer);
    matchService.countdownTimers.clear();
    matchService.turnTimers.clear();
});

test('lobby ready flow starts countdown', async () => {
    const userIds = [makeUserId(), makeUserId()];
    const room = await createGameRoom({ userIds, countdownSec: 30 });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        profile: { username: 'Beta', avatar: 'b.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        seatIndex: 0,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        seatIndex: 1,
        profile: { username: 'Beta', avatar: 'b.png' }
    });

    await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        ready: true,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    const lobby = await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        ready: true,
        profile: { username: 'Beta', avatar: 'b.png' }
    });

    assert.equal(lobby.status, 'countdown');
    assert.ok(lobby.countdownEndsAt > Date.now());
    assert.ok(matchService.io.find('cc:room:countdown_started').length >= 1);
});

test('countdown cancels when eligibility drops', async () => {
    const userIds = [makeUserId(), makeUserId()];
    const room = await createGameRoom({ userIds, countdownSec: 30 });

    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.subscribeRoom({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        profile: { username: 'Beta', avatar: 'b.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        seatIndex: 0,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.claimSeat({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        seatIndex: 1,
        profile: { username: 'Beta', avatar: 'b.png' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[0].toString(),
        ready: true,
        profile: { username: 'Alpha', avatar: 'a.png' }
    });
    await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        ready: true,
        profile: { username: 'Beta', avatar: 'b.png' }
    });

    const lobby = await matchService.setReady({
        roomId: room._id.toString(),
        userId: userIds[1].toString(),
        ready: false,
        profile: { username: 'Beta', avatar: 'b.png' }
    });

    assert.equal(lobby.status, 'open');
    assert.equal(lobby.countdownEndsAt, null);
    assert.ok(matchService.io.find('cc:room:countdown_cancelled').length >= 1);
});

test('match start writes Redis state and Mongo projection', async () => {
    const { room, userIds, started } = await setupStartedMatch();

    const matchDoc = await ColorClashMatch.findById(started.matchId).lean();
    const roundDoc = await ColorClashRound.findOne({ matchId: started.matchId }).lean();
    const runtimeState = await matchService.readJson(KEYS.matchState(started.matchId));
    const handSnapshot = await matchService.readJson(KEYS.hand(started.matchId, userIds[0].toString()));
    const playerSnapshot = await matchService.readJson(KEYS.snapshot(started.matchId, userIds[0].toString()));
    const updatedRoom = await Room.findById(room._id).lean();

    assert.equal(matchDoc.status, 'active');
    assert.equal(roundDoc.roundNumber, 1);
    assert.equal(runtimeState.version, 1);
    assert.equal(Array.isArray(handSnapshot), true);
    assert.equal(playerSnapshot.viewerRole, 'player');
    assert.equal(updatedRoom.gameConfig.activeMatchId.toString(), started.matchId);
});

test('submit valid move increments version and persists move audit', async () => {
    const { room, userIds, started } = await setupStartedMatch();
    const move = await firstPlayableMove(started.matchId, userIds[0].toString());

    const result = await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'move-1',
        expectedVersion: 1,
        move
    });

    const runtimeState = await matchService.readJson(KEYS.matchState(started.matchId));
    const moves = await ColorClashMove.find({ matchId: started.matchId }).lean();

    assert.equal(result.accepted, true);
    assert.equal(runtimeState.version, 2);
    assert.equal(moves.length, 1);
    assert.equal(moves[0].versionAfter, 2);
    assert.ok(matchService.io.find('cc:match:state_patch').some((entry) => entry.payload.version === 2));
    assert.equal(room.type, 'game');
});

test('duplicate clientMoveId is handled idempotently', async () => {
    const { userIds, started } = await setupStartedMatch();
    const move = await firstPlayableMove(started.matchId, userIds[0].toString());

    const first = await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'dup-move',
        expectedVersion: 1,
        move
    });
    const second = await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'dup-move',
        expectedVersion: 1,
        move
    });

    assert.equal(first.accepted, true);
    assert.equal(second.accepted, true);
    assert.equal(second.duplicate, true);
});

test('stale version is rejected with snapshotRequired', async () => {
    const { userIds, started } = await setupStartedMatch();
    const move = await firstPlayableMove(started.matchId, userIds[0].toString());

    await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'fresh',
        expectedVersion: 1,
        move
    });

    const stale = await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[1].toString(),
        clientMoveId: 'stale',
        expectedVersion: 1,
        move: { type: 'draw_card' }
    });

    assert.equal(stale.accepted, false);
    assert.equal(stale.errorCode, 'VERSION_MISMATCH');
    assert.equal(stale.snapshotRequired, true);
});

test('private hand never appears in spectator snapshot', async () => {
    const { userIds, started } = await setupStartedMatch();
    const playerSnapshot = await snapshotService.getMatchSnapshot(started.matchId, userIds[0].toString(), 'player');
    const spectatorSnapshot = await snapshotService.getMatchSnapshot(started.matchId, userIds[2].toString(), 'spectator');

    assert.equal(Boolean(playerSnapshot.privateState), true);
    assert.equal(Boolean(spectatorSnapshot.privateState), false);
    assert.equal(
        JSON.stringify(spectatorSnapshot).includes(playerSnapshot.privateState.hand[0].id),
        false
    );
});

test('timeout auto-action advances version', async () => {
    const { userIds, started } = await setupStartedMatch();
    const runtimeState = await matchService.readJson(KEYS.matchState(started.matchId));
    const beforeVersion = runtimeState.version;

    const timeoutResult = await matchService.handleTimeout({
        matchId: started.matchId,
        expectedVersion: runtimeState.version,
        expectedSeat: runtimeState.currentTurnSeat
    });

    const afterState = await matchService.readJson(KEYS.matchState(started.matchId));
    assert.equal(timeoutResult.accepted, true);
    assert.equal(afterState.version, beforeVersion + 1);
    assert.ok(matchService.io.find('cc:match:state_patch').some((entry) => entry.payload.version === beforeVersion + 1));
    assert.ok(userIds.length >= 2);
});

test('reconnect returns replay for a small version gap', async () => {
    const { userIds, started } = await setupStartedMatch();
    const move = await firstPlayableMove(started.matchId, userIds[0].toString());

    await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'replay-1',
        expectedVersion: 1,
        move
    });

    const reconnect = await snapshotService.getReconnectPayload(
        started.matchId,
        userIds[0].toString(),
        1
    );

    assert.equal(reconnect.mode, 'replay');
    assert.ok(reconnect.replay.length >= 1);
});

test('spectator subscription is tracked without private hand state', async () => {
    const { userIds, started } = await setupStartedMatch();
    const access = await matchService.subscribeMatch({
        matchId: started.matchId,
        userId: userIds[2].toString()
    });
    const spectatorSnapshot = await snapshotService.getMatchSnapshot(started.matchId, userIds[2].toString(), 'spectator');
    const presenceCount = await matchService.redis.sCard(KEYS.spectatorsPresence(started.matchId));

    assert.equal(access.viewerRole, 'spectator');
    assert.equal(Boolean(spectatorSnapshot.privateState), false);
    assert.equal(presenceCount, 1);
});

test('replay list stores ordered public events', async () => {
    const { userIds, started } = await setupStartedMatch();
    const move = await firstPlayableMove(started.matchId, userIds[0].toString());

    await matchService.submitMove({
        matchId: started.matchId,
        userId: userIds[0].toString(),
        clientMoveId: 'ordered-1',
        expectedVersion: 1,
        move
    });

    const replay = await matchService.getReplaySinceVersion(started.matchId, 0);
    assert.equal(replay.snapshotRequired, false);
    assert.ok(replay.replay.length >= 2);
    for (let index = 1; index < replay.replay.length; index += 1) {
        assert.ok(replay.replay[index].version >= replay.replay[index - 1].version);
    }
});
