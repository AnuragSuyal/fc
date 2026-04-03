process.env.JWT_SECRET = process.env.JWT_SECRET || 'mini-draw-test-secret';
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
const Transaction = require('../src/models/Transaction');
const roomRoutes = require('../src/routes/roomRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.strings = new Map();
        this.sets = new Map();
    }

    async get(key) {
        return this.strings.has(key) ? this.strings.get(key) : null;
    }

    async set(key, value) {
        this.strings.set(key, value);
        return 'OK';
    }

    async del(keys) {
        const keyList = Array.isArray(keys) ? keys : Array.from(arguments);
        let removed = 0;
        for (const key of keyList) {
            if (this.strings.delete(key)) removed += 1;
            if (this.sets.delete(key)) removed += 1;
        }
        return removed;
    }

    async expire() {
        return 1;
    }

    async exists(key) {
        return this.strings.has(key) ? 1 : 0;
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
}

class FakeIo {
    constructor() {
        this.events = [];
    }

    emit(event, payload) {
        this.events.push({ target: 'broadcast', event, payload });
    }

    to(target) {
        return {
            emit: (event, payload) => {
                this.events.push({ target, event, payload });
            }
        };
    }
}

const makeUsername = () => `mini_draw_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 5,
    coins: overrides.coins ?? 1000,
    isGuest: overrides.isGuest ?? false,
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`
});

let mongoServer;
let redis;
let io;
let server;
let baseUrl;

const startApiServer = async () => {
    redis = new FakeRedis();
    io = new FakeIo();

    const app = express();
    app.use(express.json());
    app.set('redis', redis);
    app.set('io', io);
    app.use('/api/rooms', roomRoutes);
    app.use(errorMiddleware);

    await new Promise((resolve) => {
        server = http.createServer(app);
        server.listen(0, '127.0.0.1', resolve);
    });

    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
};

const stopApiServer = async () => {
    if (!server) return;
    await new Promise((resolve) => server.close(resolve));
    server = null;
    baseUrl = null;
};

const createAuthHeaders = async (user, headers = {}) => {
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET);
    await redis.set(`session:${user._id}`, 'active');
    return {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...headers
    };
};

const apiRequest = async ({
    method = 'GET',
    path,
    user,
    body,
    headers = {}
}) => {
    const requestHeaders = user
        ? await createAuthHeaders(user, headers)
        : { 'Content-Type': 'application/json', ...headers };
    const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: requestHeaders,
        body: body === undefined ? undefined : JSON.stringify(body)
    });
    const json = await response.json();
    return {
        status: response.status,
        body: json
    };
};

const createRoomFixture = async () => {
    const host = await createUser({ username: makeUsername(), coins: 1000 });
    const listener = await createUser({ username: makeUsername(), coins: 400 });
    const room = await Room.create({
        name: 'Mini Draw Test Room',
        description: 'Realtime canvas room',
        ownerId: host._id,
        hostId: host._id,
        type: 'voice',
        mode: 'normal',
        category: 'voice',
        settings: {
            maxParticipants: 20,
            allowGifts: true,
            stageJoinsLocked: false,
            allowAdminSeatControl: true,
            requireApproval: false,
            maxActiveSpeakers: 8
        },
        theme: {
            background: 'default'
        },
        participants: [
            {
                userId: host._id,
                role: 'host',
                seatIndex: 1,
                isPresent: true,
                joinedAt: new Date(),
                lastActive: new Date()
            },
            {
                userId: listener._id,
                role: 'listener',
                seatIndex: -1,
                isPresent: true,
                joinedAt: new Date(),
                lastActive: new Date()
            }
        ]
    });

    return { room, host, listener };
};

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), { dbName: 'mini-draw-tests' });
    await startApiServer();
});

test.after(async () => {
    await stopApiServer();
    await mongoose.disconnect();
    if (mongoServer) {
        await mongoServer.stop();
        mongoServer = null;
    }
});

test.beforeEach(async () => {
    io.events = [];
    for (const collection of Object.values(mongoose.connection.collections)) {
        await collection.deleteMany({});
    }
});

test('mini draw unlock charges the host once and returns duplicate on replay', async () => {
    const { room, host } = await createRoomFixture();
    const idempotencyKey = 'mini-draw-unlock-same-key';
    const postUnlockKey = 'mini-draw-unlock-after-active';

    const firstResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/unlock`,
        user: host,
        body: {},
        headers: { 'Idempotency-Key': idempotencyKey }
    });
    const replayedResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/unlock`,
        user: host,
        body: {},
        headers: { 'Idempotency-Key': idempotencyKey }
    });
    const duplicateAfterUnlockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/unlock`,
        user: host,
        body: {},
        headers: { 'Idempotency-Key': postUnlockKey }
    });

    assert.equal(firstResponse.status, 200);
    assert.equal(firstResponse.body.duplicate, false);
    assert.equal(firstResponse.body.chargedCoins, 300);
    assert.equal(firstResponse.body.summary.isUnlocked, true);
    assert.equal(firstResponse.body.summary.unlockCostCoins, 300);

    assert.equal(replayedResponse.status, 200);
    assert.equal(replayedResponse.body.summary.isUnlocked, true);
    assert.equal(replayedResponse.body.transactionId, firstResponse.body.transactionId);

    assert.equal(duplicateAfterUnlockResponse.status, 200);
    assert.equal(duplicateAfterUnlockResponse.body.duplicate, true);
    assert.equal(duplicateAfterUnlockResponse.body.chargedCoins, 0);
    assert.equal(duplicateAfterUnlockResponse.body.summary.isUnlocked, true);

    const persistedHost = await User.findById(host._id).lean();
    assert.equal(persistedHost.coins, 700);

    const unlockTransactions = await Transaction.find({
        userId: host._id,
        type: 'room_feature_unlock'
    }).lean();
    assert.equal(unlockTransactions.length, 1);

    const unlockEvent = io.events.find((entry) => entry.event === 'room:draw:meta');
    assert.ok(unlockEvent);
    assert.equal(unlockEvent.payload.summary.isUnlocked, true);
  });

test('listener sees view-only snapshot but cannot clear or undo the shared board', async () => {
    const { room, host, listener } = await createRoomFixture();

    const unlockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/unlock`,
        user: host,
        body: {},
        headers: { 'Idempotency-Key': 'mini-draw-view-only-unlock' }
    });
    assert.equal(unlockResponse.status, 200);

    const settingsResponse = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}/draw/settings`,
        user: host,
        body: {
            enabled: true,
            accessPolicy: 'view_only'
        }
    });
    assert.equal(settingsResponse.status, 200);
    assert.equal(settingsResponse.body.summary.accessPolicy, 'view_only');

    const snapshotResponse = await apiRequest({
        method: 'GET',
        path: `/api/rooms/${room._id}/draw`,
        user: listener
    });

    assert.equal(snapshotResponse.status, 200);
    assert.equal(snapshotResponse.body.summary.permissions.canView, true);
    assert.equal(snapshotResponse.body.summary.permissions.canDraw, false);
    assert.deepEqual(snapshotResponse.body.strokes, []);

    const clearResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/clear`,
        user: listener,
        body: {}
    });
    assert.equal(clearResponse.status, 403);

    const undoResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/draw/undo`,
        user: listener,
        body: {}
    });
    assert.equal(undoResponse.status, 403);
});
