process.env.JWT_SECRET = process.env.JWT_SECRET || 'gift-catalog-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');
const jwt = require('jsonwebtoken');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

require('../src/models/User');
require('../src/models/Gift');
require('../src/models/Transaction');
require('../src/models/Message');
const Gift = require('../src/models/Gift');
const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const giftRoutes = require('../src/routes/giftRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.values = new Map();
    }

    async get(key) {
        return this.values.has(key) ? this.values.get(key) : null;
    }

    async set(key, value) {
        this.values.set(key, value);
        return 'OK';
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

const makeUsername = () => `gift_tester_${Math.random().toString(36).slice(2, 10)}`;

let mongoServer;
let server;
let baseUrl;
let redis;
let io;

const startApiServer = async () => {
    redis = new FakeRedis();
    io = new FakeIo();

    const app = express();
    app.use(express.json());
    app.set('redis', redis);
    app.set('io', io);
    app.use('/api/gifts', giftRoutes);
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

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 5,
    coins: overrides.coins ?? 500,
    gems: overrides.gems ?? 0,
    friends: overrides.friends || [],
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`
});

const createAuthHeaders = async (user) => {
    const token = jwt.sign({ userId: user._id.toString() }, process.env.JWT_SECRET);
    await redis.set(`session:${user._id}`, 'active');
    return {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
    };
};

const apiRequest = async ({ method = 'GET', path, user, body }) => {
    const headers = user
        ? await createAuthHeaders(user)
        : { 'Content-Type': 'application/json' };

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

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), { dbName: 'gift-catalog-tests' });
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

test('catalog sync returns only Simple, Premium, Luxury, and Limited gifts in the new order', async () => {
    await Gift.create({
        name: 'Dragon',
        description: 'Old premium gift',
        icon: 'dragon.png',
        price: { coins: 2000, gems: 0 },
        category: 'premium',
        tier: 2,
        active: true
    });

    const response = await apiRequest({
        path: '/api/gifts/catalog'
    });

    assert.equal(response.status, 200);
    assert.deepEqual(Object.keys(response.body), ['simple', 'premium', 'luxury', 'limited']);
    assert.equal(response.body.simple.length, 15);
    assert.equal(response.body.premium.length, 15);
    assert.equal(response.body.luxury.length, 15);
    assert.equal(response.body.limited.length, 9);
    assert.equal(response.body.simple[0].giftId, 'simple_microphone');
    assert.equal(response.body.simple[0].assetPath, 'assets/gifts/simple_microphone.png');
    assert.equal(response.body.limited[0].giftId, 'limited_sweet_bag');
    assert.equal(response.body.legendary, undefined);
    assert.ok(response.body.limited.every((gift) => gift.category === 'limited'));
    assert.ok(response.body.simple.every((gift) => !gift.giftId.startsWith('limited_')));

    const staleGift = await Gift.findOne({ name: 'Dragon' }).lean();
    assert.equal(staleGift.active, false);
});

test('sending a gift by stable catalog id uses the configured price and transaction reference', async () => {
    const recipient = await createUser({ coins: 0 });
    const sender = await createUser({
        coins: 250,
        friends: [recipient._id]
    });

    await User.findByIdAndUpdate(recipient._id, {
        $set: {
            friends: [sender._id]
        }
    });

    const catalogResponse = await apiRequest({
        path: '/api/gifts/catalog'
    });
    assert.equal(catalogResponse.status, 200);

    const sendResponse = await apiRequest({
        method: 'POST',
        path: '/api/gifts/send',
        user: sender,
        body: {
            toUserId: recipient._id.toString(),
            giftId: 'simple_microphone',
            message: 'Enjoy the room'
        }
    });

    assert.equal(sendResponse.status, 200);
    assert.equal(sendResponse.body.success, true);
    assert.equal(sendResponse.body.gift.giftId, 'simple_microphone');
    assert.equal(sendResponse.body.gift.price.coins, 40);
    assert.equal(sendResponse.body.newBalance.coins, 210);

    const refreshedSender = await User.findById(sender._id).lean();
    const refreshedRecipient = await User.findById(recipient._id).lean();
    assert.equal(refreshedSender.coins, 210);
    assert.equal(refreshedRecipient.coins, 32);

    const transaction = await Transaction.findOne({
        userId: sender._id,
        type: 'gift_sent'
    }).populate('reference.giftId');
    assert.ok(transaction);
    assert.equal(transaction.reference.giftId.giftId, 'simple_microphone');
    assert.equal(transaction.reference.giftId.price.coins, 40);
  });
