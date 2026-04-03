process.env.JWT_SECRET = process.env.JWT_SECRET || 'room-settings-test-secret';
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
const Message = require('../src/models/Message');
const roomRoutes = require('../src/routes/roomRoutes');
const messageRoutes = require('../src/routes/messageRoutes');
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

const makeUsername = () => `room_tester_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 5,
    coins: overrides.coins ?? 500,
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
    app.use('/api/messages', (req, _res, next) => {
        req.io = io;
        next();
    }, messageRoutes);
    app.use(errorMiddleware);

    await new Promise((resolve) => {
        server = http.createServer(app);
        server.listen(0, '127.0.0.1', resolve);
    });
    const { port } = server.address();
    baseUrl = `http://127.0.0.1:${port}`;
};

const stopApiServer = async () => {
    if (server) {
        await new Promise((resolve) => server.close(resolve));
        server = null;
        baseUrl = null;
    }
};

const createAuthHeaders = async (user) => {
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET);
    await redis.set(`session:${user._id}`, 'active');
    return {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
    };
};

const apiRequest = async ({ method = 'GET', path, user, body }) => {
    const headers = user ? await createAuthHeaders(user) : { 'Content-Type': 'application/json' };
    const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body)
    });
    const json = await response.json();
    return {
        status: response.status,
        body: json
    };
};

const createRoomFixture = async ({ withAdmin = true } = {}) => {
    const host = await createUser({ username: makeUsername() });
    const admin = await createUser({ username: makeUsername() });
    const listener = await createUser({ username: makeUsername() });
    const room = await Room.create({
        name: 'Settings Test Room',
        description: 'Governed room',
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
        moderators: withAdmin ? [admin._id] : [],
        participants: [
            { userId: host._id, role: 'host', seatIndex: 1, joinedAt: new Date(), lastActive: new Date() },
            {
                userId: admin._id,
                role: withAdmin ? 'moderator' : 'listener',
                seatIndex: -1,
                joinedAt: new Date(),
                lastActive: new Date()
            },
            { userId: listener._id, role: 'listener', seatIndex: -1, joinedAt: new Date(), lastActive: new Date() }
        ]
    });

    return { room, host, admin, listener };
};

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), { dbName: 'room-settings-tests' });
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

test('host room toggles persist and emit realtime settings updates', async () => {
    const { room, host } = await createRoomFixture();

    const response = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}`,
        user: host,
        body: { settings: { banTextChat: true, allowGifts: false } }
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.roomSettings.permissions.banTextChat, true);
    assert.equal(response.body.roomSettings.permissions.allowGifting, false);

    const persisted = await Room.findById(room._id).lean();
    assert.equal(persisted.settings.banTextChat, true);
    assert.equal(persisted.settings.allowGifts, false);

    const realtimeEvent = io.events.find((entry) => entry.event === 'room:update_settings');
    assert.ok(realtimeEvent);
    assert.equal(realtimeEvent.payload.roomSettings.permissions.banTextChat, true);
    assert.equal(realtimeEvent.payload.roomSettings.permissions.allowGifting, false);
});

test('listener cannot change room settings', async () => {
    const { room, listener } = await createRoomFixture();

    const response = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}`,
        user: listener,
        body: { settings: { banTextChat: true } }
    });

    assert.equal(response.status, 403);
});

test('admin can update announcement and announcement sync emits identity event', async () => {
    const { room, admin } = await createRoomFixture();

    const response = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/announcement`,
        user: admin,
        body: { announcement: 'Welcome to the moderated room' }
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.announcement, 'Welcome to the moderated room');

    const persisted = await Room.findById(room._id).lean();
    assert.equal(persisted.announcement.text, 'Welcome to the moderated room');

    const realtimeEvent = io.events.find((entry) => entry.event === 'room:update_identity');
    assert.ok(realtimeEvent);
    assert.equal(
        realtimeEvent.payload.roomSettings.identity.announcement,
        'Welcome to the moderated room'
    );
});

test('seat locking blocks listener seat join attempts', async () => {
    const { room, host, listener } = await createRoomFixture();

    const lockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/2/lock`,
        user: host,
        body: {}
    });
    assert.equal(lockResponse.status, 200);

    const takeSeatResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat`,
        user: listener,
        body: { seatIndex: 2 }
    });

    assert.equal(takeSeatResponse.status, 403);
    const seatEvent = io.events.find((entry) => entry.event === 'room:update_seats');
    assert.ok(seatEvent);
});

test('host can lock and unlock a seat with detailed realtime events', async () => {
    const { room, host } = await createRoomFixture();

    const lockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/3/lock`,
        user: host,
        body: { reason: 'Reserved for guests' }
    });
    assert.equal(lockResponse.status, 200);
    assert.equal(lockResponse.body.seat.seatIndex, 3);
    assert.equal(lockResponse.body.seat.isLocked, true);
    assert.equal(lockResponse.body.lockedSeatCount, 1);

    const lockedEvent = io.events.find((entry) => entry.event === 'room:seat_locked');
    assert.ok(lockedEvent);
    assert.equal(lockedEvent.payload.seatIndex, 3);
    assert.equal(lockedEvent.payload.isLocked, true);
    assert.equal(lockedEvent.payload.lockedSeatCount, 1);
    assert.ok(Array.isArray(lockedEvent.payload.updatedSeats));

    const unlockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/3/unlock`,
        user: host,
        body: {}
    });
    assert.equal(unlockResponse.status, 200);
    assert.equal(unlockResponse.body.seat.isLocked, false);
    assert.equal(unlockResponse.body.lockedSeatCount, 0);

    const unlockedEvent = io.events.find((entry) => entry.event === 'room:seat_unlocked');
    assert.ok(unlockedEvent);
    assert.equal(unlockedEvent.payload.seatIndex, 3);
    assert.equal(unlockedEvent.payload.isLocked, false);
    assert.equal(unlockedEvent.payload.lockedSeatCount, 0);

    const seatsUpdatedEvent = io.events.find((entry) => entry.event === 'room:seats_updated');
    assert.ok(seatsUpdatedEvent);
});

test('admin seat locking respects room policy and listeners are rejected', async () => {
    const { room, host, admin, listener } = await createRoomFixture();

    const adminLockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/4/lock`,
        user: admin,
        body: {}
    });
    assert.equal(adminLockResponse.status, 200);

    const listenerLockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/5/lock`,
        user: listener,
        body: {}
    });
    assert.equal(listenerLockResponse.status, 403);

    const disableAdminSeatControl = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}`,
        user: host,
        body: {
            settings: {
                allowAdminSeatControl: false
            }
        }
    });
    assert.equal(disableAdminSeatControl.status, 200);

    const deniedAdminLock = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/6/lock`,
        user: admin,
        body: {}
    });
    assert.equal(deniedAdminLock.status, 403);
});

test('locked seats block promotion and auto-assignment skips them', async () => {
    const { room, host, admin, listener } = await createRoomFixture();
    const extraListener = await createUser({ username: makeUsername() });
    await Room.findByIdAndUpdate(room._id, {
        $push: {
            participants: {
                userId: extraListener._id,
                role: 'listener',
                seatIndex: -1,
                joinedAt: new Date(),
                lastActive: new Date()
            }
        }
    });

    const lockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/2/lock`,
        user: host,
        body: {}
    });
    assert.equal(lockResponse.status, 200);

    const blockedPromote = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/promote/${listener._id}`,
        user: admin,
        body: { seatIndex: 2 }
    });
    assert.equal(blockedPromote.status, 403);

    const autoPromote = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/promote/${extraListener._id}`,
        user: admin,
        body: {}
    });
    assert.equal(autoPromote.status, 200);

    const refreshed = await Room.findById(room._id).lean();
    const promoted = refreshed.participants.find(
        (participant) => participant.userId.toString() === extraListener._id.toString()
    );
    assert.ok(promoted);
    assert.equal(promoted.seatIndex, 3);
});

test('unlock restores seat join behavior and occupied seats cannot be locked', async () => {
    const { room, host, listener } = await createRoomFixture();

    const lockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/2/lock`,
        user: host,
        body: {}
    });
    assert.equal(lockResponse.status, 200);

    const unlockResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/2/unlock`,
        user: host,
        body: {}
    });
    assert.equal(unlockResponse.status, 200);

    const takeSeatResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat`,
        user: listener,
        body: { seatIndex: 2 }
    });
    assert.equal(takeSeatResponse.status, 200);

    const lockOccupiedSeat = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat/2/lock`,
        user: host,
        body: {}
    });
    assert.equal(lockOccupiedSeat.status, 409);
});

test('mic approval flow keeps listener off stage and raises a request', async () => {
    const { room, host, listener } = await createRoomFixture();

    const settingsResponse = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}`,
        user: host,
        body: { settings: { requireApproval: true } }
    });
    assert.equal(settingsResponse.status, 200);

    const seatResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat`,
        user: listener,
        body: { seatIndex: 2 }
    });

    assert.equal(seatResponse.status, 200);
    const listenerParticipant = seatResponse.body.participants.find(
        (participant) => {
            const participantUserId = typeof participant.userId === 'object'
                ? participant.userId?._id?.toString()
                : participant.userId?.toString();
            return participantUserId === listener._id.toString();
        }
    );
    assert.ok(listenerParticipant);
    assert.equal(listenerParticipant.seatIndex, -1);
    assert.equal(listenerParticipant.raisedHand, true);
});

test('banned users cannot rejoin the room', async () => {
    const { room, host, listener } = await createRoomFixture();

    const banResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/ban/${listener._id}`,
        user: host,
        body: { reason: 'spam' }
    });
    assert.equal(banResponse.status, 200);

    const rejoinResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/join`,
        user: listener,
        body: {}
    });
    assert.equal(rejoinResponse.status, 403);
});

test('auction mode updates capabilities and blocks audience room chat', async () => {
    const { room, host, listener } = await createRoomFixture();

    const modeResponse = await apiRequest({
        method: 'PUT',
        path: `/api/rooms/${room._id}`,
        user: host,
        body: { mode: 'auction' }
    });
    assert.equal(modeResponse.status, 200);
    assert.equal(modeResponse.body.mode, 'auction');

    const getRoomResponse = await apiRequest({
        method: 'GET',
        path: `/api/rooms/${room._id}`,
        user: listener
    });
    assert.equal(getRoomResponse.status, 200);
    assert.equal(getRoomResponse.body.mode, 'auction');
    assert.equal(getRoomResponse.body.capabilities.canSendRoomGifts, false);

    const chatResponse = await apiRequest({
        method: 'POST',
        path: '/api/messages/room',
        user: listener,
        body: {
            roomId: room._id.toString(),
            content: 'hello room',
            type: 'text'
        }
    });
    assert.equal(chatResponse.status, 403);

    const modeEvent = io.events.find((entry) => entry.event === 'room:update_mode');
    assert.ok(modeEvent);
    assert.equal(modeEvent.payload.mode, 'auction');
});

test('room feed starts at the participant latest join and emits one welcome system message', async () => {
    const { room, host } = await createRoomFixture({ withAdmin: false });
    const lateJoiner = await createUser({ username: makeUsername() });

    const historicalMessage = await Message.create({
        roomId: room._id,
        senderId: host._id,
        content: 'old room event',
        type: 'text',
        createdAt: new Date(Date.now() - 60_000),
        updatedAt: new Date(Date.now() - 60_000)
    });

    const joinResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/join`,
        user: lateJoiner,
        body: {}
    });

    assert.equal(joinResponse.status, 200);

    const welcomeEvents = io.events.filter(
        (entry) =>
            entry.event === 'room:message' &&
            entry.payload?.type === 'system' &&
            entry.payload?.content === `Welcome ${lateJoiner.username}`
    );
    assert.equal(welcomeEvents.length, 1);

    const feedResponse = await apiRequest({
        method: 'GET',
        path: `/api/messages/room/${room._id}`,
        user: lateJoiner
    });

    assert.equal(feedResponse.status, 200);
    const feedContents = feedResponse.body.messages.map((message) => message.content);
    assert.ok(feedContents.includes(`Welcome ${lateJoiner.username}`));
    assert.ok(!feedContents.includes(historicalMessage.content));

    const duplicateJoinResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/join`,
        user: lateJoiner,
        body: {}
    });

    assert.equal(duplicateJoinResponse.status, 200);
    const duplicateWelcomeEvents = io.events.filter(
        (entry) =>
            entry.event === 'room:message' &&
            entry.payload?.type === 'system' &&
            entry.payload?.content === `Welcome ${lateJoiner.username}`
    );
    assert.equal(duplicateWelcomeEvents.length, 1);
});

test('permanent room allocation creates exactly one owned room and reuses it on repeat requests', async () => {
    const owner = await createUser({ username: makeUsername() });

    const firstResponse = await apiRequest({
        method: 'POST',
        path: '/api/rooms/my-room',
        user: owner,
        body: {
            name: 'Owner Hub',
            topic: 'Always on',
            type: 'voice',
            category: 'voice'
        }
    });

    assert.equal(firstResponse.status, 201);
    assert.equal(firstResponse.body.created, true);
    assert.equal(firstResponse.body.room.isPermanent, true);
    assert.equal(firstResponse.body.room.ownerId, owner._id.toString());

    const secondResponse = await apiRequest({
        method: 'POST',
        path: '/api/rooms/my-room',
        user: owner,
        body: {}
    });

    assert.equal(secondResponse.status, 200);
    assert.equal(secondResponse.body.created, false);
    assert.equal(secondResponse.body.room._id, firstResponse.body.room._id);

    const permanentRooms = await Room.find({
        ownerId: owner._id,
        isPermanent: true
    });
    assert.equal(permanentRooms.length, 1);

    const persistedUser = await User.findById(owner._id).lean();
    assert.equal(
        persistedUser.permanentRoomId.toString(),
        firstResponse.body.room._id
    );
    assert.equal(persistedUser.hasPermanentRoom, true);
});

test('my-room allocate flow creates one permanent room named New Room for first-time users', async () => {
    const owner = await createUser({ username: makeUsername() });

    const firstResponse = await apiRequest({
        method: 'GET',
        path: '/api/rooms/my-room?allocate=true',
        user: owner
    });

    assert.equal(firstResponse.status, 200);
    assert.equal(firstResponse.body.created, true);
    assert.equal(firstResponse.body.room.name, 'New Room');
    assert.equal(firstResponse.body.room.isPermanent, true);
    assert.equal(firstResponse.body.room.ownerId, owner._id.toString());
    assert.equal(firstResponse.body.room.hostId._id, owner._id.toString());
    assert.equal(firstResponse.body.room.hostPresent, true);
    assert.equal(firstResponse.body.room.roomActive, true);
    assert.equal(firstResponse.body.room.activeControllersCount, 1);
    assert.equal(firstResponse.body.room.capabilities.isOwner, true);
    assert.equal(firstResponse.body.room.capabilities.isAdmin, true);
    assert.equal(firstResponse.body.room.capabilities.canManageRoom, true);
    assert.equal(firstResponse.body.room.capabilities.canManageStage, true);
    assert.equal(firstResponse.body.room.capabilities.canSendRoomMessages, true);

    const secondResponse = await apiRequest({
        method: 'GET',
        path: '/api/rooms/my-room?allocate=true',
        user: owner
    });

    assert.equal(secondResponse.status, 200);
    assert.equal(secondResponse.body.room._id, firstResponse.body.room._id);

    const permanentRooms = await Room.find({
        ownerId: owner._id,
        isPermanent: true
    });
    assert.equal(permanentRooms.length, 1);
});

test('legacy host rooms migrate into one permanent room and archive extra owned rooms', async () => {
    const owner = await createUser({ username: makeUsername() });
    const primaryRoom = await Room.create({
        name: 'Primary Legacy Room',
        description: 'Keep me',
        hostId: owner._id,
        type: 'voice',
        category: 'voice',
        updatedAt: new Date('2026-03-29T10:00:00.000Z'),
        participants: [
            {
                userId: owner._id,
                role: 'host',
                seatIndex: 1,
                joinedAt: new Date(),
                lastActive: new Date()
            }
        ]
    });
    const secondaryRoom = await Room.create({
        name: 'Secondary Legacy Room',
        description: 'Archive me',
        hostId: owner._id,
        type: 'music',
        category: 'music',
        updatedAt: new Date('2026-03-29T09:00:00.000Z'),
        participants: [
            {
                userId: owner._id,
                role: 'host',
                seatIndex: -1,
                joinedAt: new Date(),
                lastActive: new Date()
            }
        ]
    });
    await Room.findByIdAndUpdate(primaryRoom._id, {
        $set: { updatedAt: new Date('2026-03-29T11:00:00.000Z') }
    });
    await Room.findByIdAndUpdate(secondaryRoom._id, {
        $set: { updatedAt: new Date('2026-03-29T09:00:00.000Z') }
    });

    const response = await apiRequest({
        method: 'GET',
        path: '/api/rooms/my-room',
        user: owner
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.migrated, true);
    assert.equal(response.body.room._id, primaryRoom._id.toString());
    assert.equal(response.body.room.isPermanent, true);
    assert.equal(response.body.archivedLegacyRoomCount, 1);

    const migratedPrimary = await Room.findById(primaryRoom._id).lean();
    const archivedSecondary = await Room.findById(secondaryRoom._id).lean();
    const persistedUser = await User.findById(owner._id).lean();

    assert.equal(migratedPrimary.isPermanent, true);
    assert.equal(migratedPrimary.ownerId.toString(), owner._id.toString());
    assert.equal(migratedPrimary.endedAt, null);
    assert.equal(archivedSecondary.isPermanent, false);
    assert.ok(archivedSecondary.endedAt);
    assert.equal(archivedSecondary.showInExplore, false);
    assert.equal(
        persistedUser.permanentRoomId.toString(),
        primaryRoom._id.toString()
    );
});

test('owners cannot delete their permanent room', async () => {
    const owner = await createUser({ username: makeUsername() });

    const allocation = await apiRequest({
        method: 'POST',
        path: '/api/rooms/my-room',
        user: owner,
        body: {
            name: 'Keep Forever',
            type: 'voice'
        }
    });

    assert.equal(allocation.status, 201);

    const deleteResponse = await apiRequest({
        method: 'DELETE',
        path: `/api/rooms/${allocation.body.room._id}`,
        user: owner
    });

    assert.equal(deleteResponse.status, 403);
    const persistedRoom = await Room.findById(allocation.body.room._id).lean();
    assert.ok(persistedRoom);
    assert.equal(persistedRoom.isPermanent, true);
    assert.equal(persistedRoom.endedAt, null);
});

test('room stays active with an admin present and becomes inactive with seats cleared after the last controller leaves', async () => {
    const { room, host, admin, listener } = await createRoomFixture();
    await Room.findByIdAndUpdate(room._id, {
        $set: {
            'participants.2.role': 'speaker',
            'participants.2.seatIndex': 2,
            'participants.2.isSpeaking': true
        }
    });

    const hostLeave = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/leave`,
        user: host,
        body: {}
    });
    assert.equal(hostLeave.status, 200);

    let persistedRoom = await Room.findById(room._id).lean();
    assert.equal(persistedRoom.roomActive, true);
    assert.equal(persistedRoom.activeControllersCount, 1);
    const speakerAfterHostLeave = persistedRoom.participants.find(
        (participant) => participant.userId.toString() === listener._id.toString()
    );
    assert.equal(speakerAfterHostLeave.seatIndex, 2);

    const adminLeave = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/leave`,
        user: admin,
        body: {}
    });
    assert.equal(adminLeave.status, 200);

    persistedRoom = await Room.findById(room._id).lean();
    assert.equal(persistedRoom.roomActive, false);
    assert.equal(persistedRoom.activeControllersCount, 0);
    const audienceListener = persistedRoom.participants.find(
        (participant) => participant.userId.toString() === listener._id.toString()
    );
    assert.equal(audienceListener.seatIndex, -1);
    assert.equal(audienceListener.role, 'listener');
    assert.equal(audienceListener.isSpeaking, false);

    const deniedSeatJoin = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${room._id}/seat`,
        user: listener,
        body: { seatIndex: 2 }
    });
    assert.equal(deniedSeatJoin.status, 403);
});

test('discover excludes inactive rooms while followed rooms keep active rooms first and offline rooms below', async () => {
    const follower = await createUser({ username: makeUsername() });
    const host = await createUser({ username: makeUsername() });
    const admin = await createUser({ username: makeUsername() });

    const activeRoom = await Room.create({
        name: 'Active Followed Room',
        description: 'Live now',
        hostId: host._id,
        type: 'voice',
        category: 'voice',
        followers: [follower._id],
        participants: [
            { userId: host._id, role: 'host', seatIndex: 1, joinedAt: new Date(), lastActive: new Date(), isPresent: true },
            { userId: follower._id, role: 'listener', seatIndex: -1, joinedAt: new Date(), lastActive: new Date(), isPresent: true }
        ]
    });
    const inactiveRoom = await Room.create({
        name: 'Inactive Followed Room',
        description: 'Waiting for controller',
        hostId: admin._id,
        type: 'voice',
        category: 'voice',
        followers: [follower._id],
        participants: [
            { userId: admin._id, role: 'host', seatIndex: -1, joinedAt: new Date(), lastActive: new Date(0), isPresent: false },
            { userId: follower._id, role: 'listener', seatIndex: -1, joinedAt: new Date(), lastActive: new Date(), isPresent: true }
        ]
    });

    const trendingResponse = await apiRequest({
        method: 'GET',
        path: '/api/rooms/trending'
    });
    assert.equal(trendingResponse.status, 200);
    const trendingIds = trendingResponse.body.map((entry) => entry._id);
    assert.ok(trendingIds.includes(activeRoom._id.toString()));
    assert.ok(!trendingIds.includes(inactiveRoom._id.toString()));

    const followedResponse = await apiRequest({
        method: 'GET',
        path: '/api/rooms/followed',
        user: follower
    });
    assert.equal(followedResponse.status, 200);
    assert.equal(followedResponse.body.length, 2);
    assert.equal(followedResponse.body[0]._id, activeRoom._id.toString());
    assert.equal(followedResponse.body[0].roomActive, true);
    assert.equal(followedResponse.body[1]._id, inactiveRoom._id.toString());
    assert.equal(followedResponse.body[1].roomActive, false);
});

test('recent rooms keep the latest 10 unique visits in most-recent-first order', async () => {
    const visitor = await createUser({ username: makeUsername() });
    const host = await createUser({ username: makeUsername() });
    const rooms = [];

    for (let index = 0; index < 11; index += 1) {
        const room = await Room.create({
            name: `Recent Room ${index + 1}`,
            description: 'Recent visit test',
            hostId: host._id,
            type: 'voice',
            category: 'voice',
            participants: [
                {
                    userId: host._id,
                    role: 'host',
                    seatIndex: 1,
                    joinedAt: new Date(),
                    lastActive: new Date(),
                    isPresent: true
                }
            ]
        });
        rooms.push(room);

        const joinResponse = await apiRequest({
            method: 'POST',
            path: `/api/rooms/${room._id}/join`,
            user: visitor,
            body: {}
        });
        assert.equal(joinResponse.status, 200);
    }

    const revisitResponse = await apiRequest({
        method: 'POST',
        path: `/api/rooms/${rooms[2]._id}/join`,
        user: visitor,
        body: {}
    });
    assert.equal(revisitResponse.status, 200);

    const recentResponse = await apiRequest({
        method: 'GET',
        path: '/api/rooms/recent',
        user: visitor
    });
    assert.equal(recentResponse.status, 200);
    assert.equal(recentResponse.body.rooms.length, 10);
    assert.equal(recentResponse.body.rooms[0]._id, rooms[2]._id.toString());
    assert.ok(
        !recentResponse.body.rooms.some(
            (room) => room._id === rooms[0]._id.toString()
        )
    );
});
