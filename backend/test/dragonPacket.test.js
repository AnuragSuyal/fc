process.env.JWT_SECRET = process.env.JWT_SECRET || 'dragon-packet-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

require('../src/models/User');
const User = require('../src/models/User');
const Room = require('../src/models/Room');
const Transaction = require('../src/models/Transaction');
const DragonPacketInventory = require('../src/models/DragonPacketInventory');
const RoomDragonEvent = require('../src/models/RoomDragonEvent');
const DragonClaimParticipant = require('../src/models/DragonClaimParticipant');
const DragonEventLedgerEntry = require('../src/models/DragonEventLedgerEntry');
const dragonPacketRoutes = require('../src/routes/dragonPacketRoutes');
const dragonEventRoutes = require('../src/routes/dragonEventRoutes');
const roomRoutes = require('../src/routes/roomRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');
const {
    buildDragonTapScoreIncrement,
    calculateDragonDistribution,
    clearDragonEventLifecycle,
    handleDragonTapSocket,
    settleDragonEvent
} = require('../src/services/dragonPacketService');
const {
    clearDragonPacketConfigForTests,
    setDragonPacketConfigForTests
} = require('../src/config/dragonPacketConfig');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.store = new Map();
    }

    async get(key) {
        return this.store.has(key) ? this.store.get(key) : null;
    }

    async set(key, value, options = {}) {
        if (options?.NX && this.store.has(key)) {
            return null;
        }
        this.store.set(key, String(value));
        return 'OK';
    }

    async del(...keys) {
        let removed = 0;
        for (const key of keys.flat()) {
            if (this.store.delete(key)) {
                removed += 1;
            }
        }
        return removed;
    }

    async expire() {
        return 1;
    }

    async exists(key) {
        return this.store.has(key) ? 1 : 0;
    }

    async incr(key) {
        const next = Number.parseInt(await this.get(key), 10) || 0;
        const value = next + 1;
        this.store.set(key, String(value));
        return value;
    }

    async decr(key) {
        const next = Number.parseInt(await this.get(key), 10) || 0;
        const value = next - 1;
        this.store.set(key, String(value));
        return value;
    }

    async incrByFloat(key, amount) {
        const next = Number.parseFloat(await this.get(key)) || 0;
        const value = next + Number(amount || 0);
        this.store.set(key, String(value));
        return value;
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

const makeUsername = () => `dragon_user_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 8,
    coins: overrides.coins ?? 0,
    gems: overrides.gems ?? 0,
    isGuest: overrides.isGuest ?? false,
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`,
    createdAt: overrides.createdAt || new Date(Date.now() - (20 * 24 * 60 * 60 * 1000))
});

const createRoomFixture = async () => {
    const host = await createUser({ coins: 200, username: makeUsername() });
    const listenerA = await createUser({ coins: 10, username: makeUsername() });
    const listenerB = await createUser({ coins: 20, username: makeUsername() });

    const joinedAt = new Date(Date.now() - 60 * 1000);
    const room = await Room.create({
        name: 'Dragon Arena',
        description: 'Room dragon packet test',
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
            maxActiveSpeakers: 8,
            banRedPacket: false
        },
        participants: [
            {
                userId: host._id,
                role: 'host',
                seatIndex: 1,
                isPresent: true,
                joinedAt,
                lastActive: joinedAt
            },
            {
                userId: listenerA._id,
                role: 'listener',
                seatIndex: -1,
                isPresent: true,
                joinedAt,
                lastActive: joinedAt
            },
            {
                userId: listenerB._id,
                role: 'listener',
                seatIndex: -1,
                isPresent: true,
                joinedAt,
                lastActive: joinedAt
            }
        ]
    });

    return { room, host, listenerA, listenerB };
};

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
    app.use('/api/dragon-packets', dragonPacketRoutes);
    app.use('/api/dragon-events', dragonEventRoutes);
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

const createAuthHeaders = async (user, extraHeaders = {}) => {
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET);
    await redis.set(`session:${user._id}`, 'active', { EX: 3600 });
    return {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...extraHeaders
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

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const makeSocketUser = (userId) => ({
    userId: userId.toString(),
    handshake: {
        address: '127.0.0.1',
        headers: {
            'user-agent': 'dragon-test',
            'x-device-id': 'device-1',
            'x-session-id': 'session-1'
        }
    }
});

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), {
        dbName: 'dragon-packet-test'
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
    for (const collection of Object.values(mongoose.connection.collections)) {
        await collection.deleteMany({});
    }
    clearDragonPacketConfigForTests();
    setDragonPacketConfigForTests({
        allowMockPurchases: true,
        eventDurationMs: 1200,
        participantJoinCutoffRemainingMs: 500,
        minimumRoomPresenceSeconds: 0,
        minimumAccountAgeDaysToClaim: 0,
        requireVerifiedAccountToClaim: false,
        activatorCanClaim: false,
        reconcileIntervalMs: 100000
    });
    await stopApiServer();
    await startApiServer();
});

test.afterEach(async () => {
    const eventIds = await RoomDragonEvent.find({}).distinct('_id');
    eventIds.forEach((eventId) => clearDragonEventLifecycle(eventId));
    clearDragonPacketConfigForTests();
    await stopApiServer();
});

test('buildDragonTapScoreIncrement follows diminishing return bands', () => {
    assert.equal(buildDragonTapScoreIncrement(1), 1);
    assert.equal(buildDragonTapScoreIncrement(10), 1);
    assert.equal(buildDragonTapScoreIncrement(11), 0.7);
    assert.equal(buildDragonTapScoreIncrement(21), 0.4);
    assert.equal(buildDragonTapScoreIncrement(40), 0.2);
    assert.equal(buildDragonTapScoreIncrement(60), 0);
});

test('calculateDragonDistribution exhausts packet total and gives every valid claimant a non-zero share', () => {
    const result = calculateDragonDistribution({
        eventId: 'dragon-event-1',
        packetTotalCoins: 800,
        participants: [
            {
                userId: 'user-a',
                acceptedTapCount: 12,
                computedScore: 12,
                firstTapAt: new Date('2026-03-31T10:00:00.000Z')
            },
            {
                userId: 'user-b',
                acceptedTapCount: 8,
                computedScore: 8,
                firstTapAt: new Date('2026-03-31T10:00:00.500Z')
            },
            {
                userId: 'user-c',
                acceptedTapCount: 4,
                computedScore: 4,
                firstTapAt: new Date('2026-03-31T10:00:01.000Z')
            }
        ]
    });

    const distributed = [...result.allocations.values()].reduce((sum, value) => sum + value, 0);
    assert.equal(distributed, 800);
    assert.ok([...result.allocations.values()].every((value) => value > 0));
});

test('mock purchase creates inventory and activation starts a live event', async () => {
    const { room, host } = await createRoomFixture();

    const purchase = await apiRequest({
        method: 'POST',
        path: '/api/dragon-packets/purchase',
        user: host,
        body: {
            productSku: 'dragon_packet_small_199_inr',
            purchaseSource: 'mock'
        },
        headers: {
            'X-Idempotency-Key': 'dragon-mock-purchase'
        }
    });

    assert.equal(purchase.status, 200);
    assert.equal(purchase.body.success, true);
    assert.equal(purchase.body.pendingCheckout, false);
    assert.equal(purchase.body.inventoryItem.inventoryStatus, 'available');

    const activate = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/dragon-events/activate`,
        user: host,
        body: {
            purchaseInventoryId: purchase.body.inventoryItem.id
        },
        headers: {
            'X-Idempotency-Key': 'dragon-activate-1'
        }
    });

    assert.equal(activate.status, 200);
    assert.equal(activate.body.success, true);
    assert.equal(activate.body.event.packetTotalCoins, 800);

    const active = await apiRequest({
        method: 'GET',
        path: `/api/rooms/${room._id}/dragon-events/active`,
        user: host
    });

    assert.equal(active.status, 200);
    assert.equal(active.body.active, true);
    assert.equal(active.body.event.roomId, room._id.toString());
  });

test('activation is blocked when the user has no available dragon packet', async () => {
    const { room, host } = await createRoomFixture();

    const response = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/dragon-events/activate`,
        user: host,
        body: {
            productSku: 'dragon_packet_small_199_inr'
        },
        headers: {
            'X-Idempotency-Key': 'dragon-activate-missing'
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'DRAGON_PACKET_NOT_AVAILABLE');
});

test('duplicate tap sequence is ignored and settlement writes winner ledger entries once', async () => {
    const { room, host, listenerA, listenerB } = await createRoomFixture();

    const purchase = await apiRequest({
        method: 'POST',
        path: '/api/dragon-packets/purchase',
        user: host,
        body: {
            productSku: 'dragon_packet_small_199_inr',
            purchaseSource: 'mock'
        },
        headers: {
            'X-Idempotency-Key': 'dragon-mock-purchase-2'
        }
    });
    const activate = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/dragon-events/activate`,
        user: host,
        body: {
            purchaseInventoryId: purchase.body.inventoryItem.id
        },
        headers: {
            'X-Idempotency-Key': 'dragon-activate-2'
        }
    });

    await wait(750);

    const eventId = activate.body.event.eventId;
    const activatorTap = await handleDragonTapSocket({
        roomId: room._id.toString(),
        eventId,
        seq: 1,
        socket: makeSocketUser(host._id),
        redis
    });
    assert.equal(activatorTap.accepted, false);
    assert.equal(activatorTap.riskState, 'activator_cannot_claim');

    const firstTap = await handleDragonTapSocket({
        roomId: room._id.toString(),
        eventId,
        seq: 1,
        socket: makeSocketUser(listenerA._id),
        redis
    });
    const duplicateTap = await handleDragonTapSocket({
        roomId: room._id.toString(),
        eventId,
        seq: 1,
        socket: makeSocketUser(listenerA._id),
        redis
    });
    await handleDragonTapSocket({
        roomId: room._id.toString(),
        eventId,
        seq: 2,
        socket: makeSocketUser(listenerA._id),
        redis
    });
    await handleDragonTapSocket({
        roomId: room._id.toString(),
        eventId,
        seq: 1,
        socket: makeSocketUser(listenerB._id),
        redis
    });

    assert.equal(firstTap.tapCounted, true);
    assert.equal(duplicateTap.tapCounted, false);
    assert.equal(duplicateTap.riskState, 'duplicate_sequence');

    const result = await settleDragonEvent({
        eventId,
        io,
        redis,
        reason: 'test'
    });

    assert.equal(result.totalDistributed, 800);
    assert.equal(result.eventStatus, 'settled');
    assert.equal(result.winners.length, 2);

    const listenerAFresh = await User.findById(listenerA._id);
    const listenerBFresh = await User.findById(listenerB._id);
    const participants = await DragonClaimParticipant.find({ eventId });
    const ledgerEntries = await DragonEventLedgerEntry.find({ eventId });
    const inventory = await DragonPacketInventory.findById(purchase.body.inventoryItem.id);
    const rewardTransactions = await Transaction.find({
        type: 'dragon_packet_reward',
        'reference.dragonEventId': eventId
    });

    assert.equal(
        participants.find((entry) => entry.userId.toString() === listenerA._id.toString()).acceptedTapCount,
        2
    );
    assert.equal(
        participants.find((entry) => entry.userId.toString() === listenerB._id.toString()).acceptedTapCount,
        1
    );
    assert.equal(rewardTransactions.length, 2);
    assert.equal(
        ledgerEntries.filter((entry) => entry.entryType === 'winner_credit').length,
        2
    );
    assert.equal(
        ledgerEntries.filter((entry) => entry.entryType === 'inventory_consumed').length,
        1
    );
    assert.equal(inventory.inventoryStatus, 'consumed');
    assert.ok(listenerAFresh.coins + listenerBFresh.coins > 30);
});

test('no-claim settlement restores the reserved inventory item', async () => {
    const { room, host } = await createRoomFixture();

    const purchase = await apiRequest({
        method: 'POST',
        path: '/api/dragon-packets/purchase',
        user: host,
        body: {
            productSku: 'dragon_packet_small_199_inr',
            purchaseSource: 'mock'
        },
        headers: {
            'X-Idempotency-Key': 'dragon-mock-purchase-3'
        }
    });
    const activate = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/dragon-events/activate`,
        user: host,
        body: {
            purchaseInventoryId: purchase.body.inventoryItem.id
        },
        headers: {
            'X-Idempotency-Key': 'dragon-activate-3'
        }
    });

    const result = await settleDragonEvent({
        eventId: activate.body.event.eventId,
        io,
        redis,
        reason: 'test_no_claim'
    });

    const inventory = await DragonPacketInventory.findById(purchase.body.inventoryItem.id);
    const restoredLedger = await DragonEventLedgerEntry.findOne({
        eventId: activate.body.event.eventId,
        entryType: 'inventory_restored'
    });

    assert.equal(result.eventStatus, 'no_claim');
    assert.equal(result.totalDistributed, 0);
    assert.equal(inventory.inventoryStatus, 'available');
    assert.ok(restoredLedger);
});
