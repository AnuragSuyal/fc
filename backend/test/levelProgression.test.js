process.env.JWT_SECRET = process.env.JWT_SECRET || 'level-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const User = require('../src/models/User');
const XpLog = require('../src/models/XpLog');
const {
    awardUserXp,
    buildProgressPayload
} = require('../src/services/levelProgressionService');

class FakeRedis {
    constructor() {
        this.isReady = true;
        this.isOpen = true;
        this.strings = new Map();
    }

    async get(key) {
        return this.strings.has(key) ? this.strings.get(key) : null;
    }

    async set(key, value, options = {}) {
        const useNx = options && options.NX === true;
        if (useNx && this.strings.has(key)) {
            return null;
        }
        this.strings.set(key, value);
        return 'OK';
    }

    async incr(key) {
        const next = Number(this.strings.get(key) || 0) + 1;
        this.strings.set(key, String(next));
        return next;
    }

    async expire() {
        return 1;
    }
}

const makeUsername = () => `lvl_${Math.random().toString(36).slice(2, 10)}`;

let mongoServer;

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), { dbName: 'level-progression-tests' });
});

test.after(async () => {
    await mongoose.disconnect();
    if (mongoServer) {
        await mongoServer.stop();
        mongoServer = null;
    }
});

test.beforeEach(async () => {
    for (const collection of Object.values(mongoose.connection.collections)) {
        await collection.deleteMany({});
    }
});

test('awardUserXp promotes milestone tier and records xp log', async () => {
    const user = await User.create({
        username: makeUsername(),
        password: 'Password1',
        referralCode: `ref_${Math.random().toString(36).slice(2, 10)}`
    });

    const result = await awardUserXp({
        userId: user._id,
        amount: 21660,
        sourceType: 'quest_reward',
        sourceReferenceId: 'quest-level-20',
        dedupeKey: 'quest:level20'
    });

    const refreshedUser = await User.findById(user._id);
    const xpLogs = await XpLog.find({ userId: user._id });

    assert.equal(result?.xpGained, 21660);
    assert.equal(result?.newLevel, 20);
    assert.equal(result?.newTier, 'parrot_green');
    assert.equal(result?.leveledUp, true);
    assert.equal(result?.tierChanged, true);
    assert.equal(refreshedUser.level, 20);
    assert.equal(refreshedUser.levelMilestoneTier, 'parrot_green');
    assert.equal(refreshedUser.xpStats.rewardXp, 21660);
    assert.equal(xpLogs.length, 1);
    assert.equal(xpLogs[0].sourceType, 'quest_reward');
    assert.equal(xpLogs[0].newLevel, 20);

    const progressPayload = buildProgressPayload(refreshedUser);
    assert.equal(progressPayload.level, 20);
    assert.equal(progressPayload.levelMilestoneTier, 'parrot_green');
    assert.equal(progressPayload.levelInfo.milestoneStartLevel, 20);
    assert.equal(progressPayload.levelInfo.nextMilestoneLevel, 40);
});

test('awardUserXp deduplicates repeated quest reward keys', async () => {
    const user = await User.create({
        username: makeUsername(),
        password: 'Password1',
        referralCode: `ref_${Math.random().toString(36).slice(2, 10)}`
    });

    const first = await awardUserXp({
        userId: user._id,
        amount: 48,
        sourceType: 'quest_reward',
        sourceReferenceId: 'quest-1',
        dedupeKey: 'quest:1'
    });
    const second = await awardUserXp({
        userId: user._id,
        amount: 48,
        sourceType: 'quest_reward',
        sourceReferenceId: 'quest-1',
        dedupeKey: 'quest:1'
    });
    const refreshedUser = await User.findById(user._id);

    assert.equal(first?.duplicate, false);
    assert.equal(second?.duplicate, true);
    assert.equal(refreshedUser.xp, 48);
    assert.equal(await XpLog.countDocuments({ userId: user._id }), 1);
});

test('room heartbeat source respects cooldown anti-abuse guard', async () => {
    const redis = new FakeRedis();
    const user = await User.create({
        username: makeUsername(),
        password: 'Password1',
        referralCode: `ref_${Math.random().toString(36).slice(2, 10)}`
    });

    const first = await awardUserXp({
        userId: user._id,
        amount: 2,
        sourceType: 'room_heartbeat',
        sourceReferenceId: 'room-alpha',
        redis
    });
    const second = await awardUserXp({
        userId: user._id,
        amount: 2,
        sourceType: 'room_heartbeat',
        sourceReferenceId: 'room-alpha',
        redis
    });
    const refreshedUser = await User.findById(user._id);

    assert.equal(first?.xpGained, 2);
    assert.equal(second?.skipped, true);
    assert.equal(second?.reason, 'cooldown');
    assert.equal(refreshedUser.xp, 2);
    assert.equal(await XpLog.countDocuments({ userId: user._id }), 1);
});
