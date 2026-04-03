process.env.JWT_SECRET = process.env.JWT_SECRET || 'coin-transfer-test-secret';
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
const Message = require('../src/models/Message');
const Transaction = require('../src/models/Transaction');
const CoinTransfer = require('../src/models/CoinTransfer');
const CoinTransferLedgerEntry = require('../src/models/CoinTransferLedgerEntry');
const FriendConnection = require('../src/models/FriendConnection');
const PlatformAccount = require('../src/models/PlatformAccount');
const PremiumEntitlement = require('../src/models/PremiumEntitlement');
const coinTransferRoutes = require('../src/routes/coinTransferRoutes');
const { errorMiddleware } = require('../src/middleware/errorMiddleware');
const {
    ENTITLEMENT_KEYS,
    calculateCoinTransferBreakdown
} = require('../src/services/coinTransferService');
const {
    activatePremiumEntitlement,
    revokePremiumEntitlement
} = require('../src/services/premiumEntitlementService');
const {
    clearCoinTransferConfigForTests,
    setCoinTransferConfigForTests
} = require('../src/config/coinTransferConfig');

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
        this.store.set(key, value);
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

    async exists(key) {
        return this.store.has(key) ? 1 : 0;
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

const makeUsername = () => `coin_user_${Math.random().toString(36).slice(2, 10)}`;

const createUser = async (overrides = {}) => User.create({
    username: overrides.username || makeUsername(),
    password: overrides.password || 'Password1',
    avatar: overrides.avatar || '',
    region: overrides.region || 'Global',
    level: overrides.level ?? 5,
    coins: overrides.coins ?? 0,
    gems: overrides.gems ?? 0,
    isGuest: overrides.isGuest ?? false,
    referralCode: overrides.referralCode || `ref_${Math.random().toString(36).slice(2, 10)}`,
    settings: overrides.settings,
    createdAt: overrides.createdAt || new Date(Date.now() - (30 * 24 * 60 * 60 * 1000))
});

const makeFriends = async (left, right) => {
    await User.updateOne(
        { _id: left._id },
        { $addToSet: { friends: right._id } }
    );
    await User.updateOne(
        { _id: right._id },
        { $addToSet: { friends: left._id } }
    );
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
    app.use('/api/coin-transfer', coinTransferRoutes);
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
    await redis.set(`session:${user._id}`, 'refresh-token', { EX: 60 * 60 });
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

const createUnlockedFriends = async ({
    senderCoins = 1000,
    receiverCoins = 200
} = {}) => {
    const sender = await createUser({ coins: senderCoins });
    const receiver = await createUser({ coins: receiverCoins });
    await makeFriends(sender, receiver);
    await activatePremiumEntitlement({
        userId: sender._id,
        entitlementKey: ENTITLEMENT_KEYS.CHAT_COIN_TRANSFER_UNLOCK,
        purchaseSource: 'test',
        purchaseAmountInr: 599,
        currency: 'INR'
    });

    return { sender, receiver };
};

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), {
        dbName: 'coin-transfer-test'
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
    await Promise.all([
        User.deleteMany({}),
        Message.deleteMany({}),
        Transaction.deleteMany({}),
        CoinTransfer.deleteMany({}),
        CoinTransferLedgerEntry.deleteMany({}),
        FriendConnection.deleteMany({}),
        PlatformAccount.deleteMany({}),
        PremiumEntitlement.deleteMany({})
    ]);
    clearCoinTransferConfigForTests();
    setCoinTransferConfigForTests({
        accountAgeMinDaysForTransfer: 0,
        minFriendshipAgeHours: 0,
        cooldownSecondsBetweenTransfers: 0,
        suspiciousVelocityThresholds: {
            windowSeconds: 600,
            maxTransfers: 999,
            maxGrossAmount: 9999999,
            circularWindowHours: 24,
            circularTransferCount: 999,
            circularGrossAmount: 9999999
        }
    });
    await stopApiServer();
    await startApiServer();
});

test.afterEach(async () => {
    clearCoinTransferConfigForTests();
    await stopApiServer();
});

test('calculateCoinTransferBreakdown floors receiver amount and keeps sender equals receiver plus fee', () => {
    assert.deepEqual(calculateCoinTransferBreakdown(100), {
        grossAmount: 100,
        senderSpend: 100,
        receiverAmount: 70,
        platformFee: 30,
        receiverPercentage: 70,
        platformPercentage: 30
    });

    const uneven = calculateCoinTransferBreakdown(101);
    assert.equal(uneven.receiverAmount, 70);
    assert.equal(uneven.platformFee, 31);
    assert.equal(uneven.senderSpend, uneven.receiverAmount + uneven.platformFee);
});

test('successful transfer debits sender, credits receiver and platform, and writes history', async () => {
    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 1000,
        receiverCoins: 200
    });

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 500,
            idempotencyKey: 'success-1'
        }
    });
    const historyByChat = await apiRequest({
        method: 'GET',
        path: `/api/coin-transfer/history?chatId=${encodeURIComponent(response.body.transfer.chatId)}`,
        user: sender
    });

    assert.equal(response.status, 200);
    assert.equal(response.body.success, true);
    assert.equal(response.body.transfer.grossAmount, 500);
    assert.equal(response.body.transfer.receiverAmount, 350);
    assert.equal(response.body.transfer.platformFee, 150);
    assert.equal(response.body.newBalance.coins, 500);

    const freshSender = await User.findById(sender._id);
    const freshReceiver = await User.findById(receiver._id);
    const platform = await PlatformAccount.findOne({
        key: 'chat_coin_transfer_platform_margin'
    });
    const ledgerEntries = await CoinTransferLedgerEntry.find({});
    const transfer = await CoinTransfer.findOne({});
    const transferMessage = await Message.findOne({ type: 'coin_transfer' });
    const senderTxn = await Transaction.findOne({
        userId: sender._id,
        type: 'coin_transfer_sent'
    });
    const receiverTxn = await Transaction.findOne({
        userId: receiver._id,
        type: 'coin_transfer_received'
    });

    assert.equal(freshSender.coins, 500);
    assert.equal(freshReceiver.coins, 550);
    assert.equal(platform.balanceCoins, 150);
    assert.equal(transfer.status, 'completed');
    assert.equal(ledgerEntries.length, 3);
    assert.ok(transferMessage);
    assert.ok(senderTxn);
    assert.ok(receiverTxn);
    assert.equal(historyByChat.status, 200);
    assert.equal(historyByChat.body.transfers.length, 1);
});

test('server rejects transfers below minimum 100 coins', async () => {
    const { sender, receiver } = await createUnlockedFriends();

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 99
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'MIN_AMOUNT_NOT_MET');
});

test('unlock entitlement is required to send', async () => {
    const sender = await createUser({ coins: 500 });
    const receiver = await createUser({ coins: 100 });
    await makeFriends(sender, receiver);

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'CHAT_TRANSFER_UNLOCK_REQUIRED');
});

test('insufficient balance is blocked without corrupting balances', async () => {
    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 80,
        receiverCoins: 100
    });

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'INSUFFICIENT_BALANCE');

    const freshSender = await User.findById(sender._id);
    const freshReceiver = await User.findById(receiver._id);
    assert.equal(freshSender.coins, 80);
    assert.equal(freshReceiver.coins, 100);
    assert.equal(await CoinTransfer.countDocuments({}), 0);
});

test('self transfer is blocked', async () => {
    const sender = await createUser({ coins: 500 });
    await activatePremiumEntitlement({
        userId: sender._id,
        entitlementKey: ENTITLEMENT_KEYS.CHAT_COIN_TRANSFER_UNLOCK,
        purchaseSource: 'test',
        purchaseAmountInr: 599
    });

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: sender._id.toString(),
            amount: 100
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'SELF_TRANSFER_FORBIDDEN');
});

test('daily limit is enforced', async () => {
    setCoinTransferConfigForTests({
        accountAgeMinDaysForTransfer: 0,
        minFriendshipAgeHours: 0,
        cooldownSecondsBetweenTransfers: 0,
        dailySendLimitAmount: 150,
        dailySendLimitCount: 5,
        monthlySendLimitAmount: 999999,
        monthlySendLimitCount: 999
    });

    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 1000
    });

    const first = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100,
            idempotencyKey: 'daily-limit-first'
        }
    });
    const second = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100,
            idempotencyKey: 'daily-limit-second'
        }
    });

    assert.equal(first.status, 200);
    assert.equal(second.status, 400);
    assert.equal(second.body.error.code, 'DAILY_LIMIT_REACHED');
});

test('duplicate idempotency key is safely deduped', async () => {
    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 1000
    });

    const first = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100,
            idempotencyKey: 'duplicate-send'
        }
    });
    const second = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100,
            idempotencyKey: 'duplicate-send'
        }
    });

    const freshSender = await User.findById(sender._id);
    const transfers = await CoinTransfer.find({});

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assert.equal(second.body.duplicate, true);
    assert.equal(freshSender.coins, 900);
    assert.equal(transfers.length, 1);
});

test('concurrent sends do not double-charge a low-balance sender', async () => {
    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 150
    });

    const [first, second] = await Promise.all([
        apiRequest({
            method: 'POST',
            path: '/api/coin-transfer/send',
            user: sender,
            body: {
                receiverUserId: receiver._id.toString(),
                amount: 100,
                idempotencyKey: 'concurrent-a'
            }
        }),
        apiRequest({
            method: 'POST',
            path: '/api/coin-transfer/send',
            user: sender,
            body: {
                receiverUserId: receiver._id.toString(),
                amount: 100,
                idempotencyKey: 'concurrent-b'
            }
        })
    ]);

    const statuses = [first.status, second.status].sort((left, right) => left - right);
    const successfulCount = [first, second].filter((entry) => entry.status === 200).length;
    const freshSender = await User.findById(sender._id);
    const transfers = await CoinTransfer.find({ status: 'completed' });

    assert.deepEqual(statuses, [200, 409]);
    assert.equal(successfulCount, 1);
    assert.equal(freshSender.coins, 50);
    assert.equal(transfers.length, 1);
});

test('revoked entitlement blocks sending', async () => {
    const { sender, receiver } = await createUnlockedFriends({
        senderCoins: 500
    });

    await revokePremiumEntitlement({
        userId: sender._id,
        entitlementKey: ENTITLEMENT_KEYS.CHAT_COIN_TRANSFER_UNLOCK,
        status: 'revoked'
    });

    const response = await apiRequest({
        method: 'POST',
        path: '/api/coin-transfer/send',
        user: sender,
        body: {
            receiverUserId: receiver._id.toString(),
            amount: 100
        }
    });

    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'CHAT_TRANSFER_UNLOCK_REQUIRED');
});
