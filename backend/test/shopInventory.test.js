process.env.JWT_SECRET = process.env.JWT_SECRET || 'shop-test-secret';
process.env.BCRYPT_SALT_ROUNDS = process.env.BCRYPT_SALT_ROUNDS || '1';

const test = require('node:test');
const assert = require('node:assert/strict');
const mongoose = require('mongoose');
const { MongoMemoryServer } = require('mongodb-memory-server');

const Transaction = require('../src/models/Transaction');
const User = require('../src/models/User');
const UserInventoryItem = require('../src/models/UserInventoryItem');
const UserItemActivation = require('../src/models/UserItemActivation');
const {
    equipInventoryItem,
    purchaseCatalogItem,
    useInventoryItem
} = require('../src/services/shopInventoryService');

const makeUsername = () => `shop_${Math.random().toString(36).slice(2, 10)}`;

let mongoServer;

async function createUser({ coins = 6000 } = {}) {
    return User.create({
        username: makeUsername(),
        password: 'Password1',
        referralCode: `ref_${Math.random().toString(36).slice(2, 10)}`,
        coins
    });
}

test.before(async () => {
    mongoServer = await MongoMemoryServer.create();
    await mongoose.connect(mongoServer.getUri(), { dbName: 'shop-inventory-tests' });
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

test('purchaseCatalogItem is idempotent and first-purchase reward is granted once', async () => {
    const user = await createUser({ coins: 7000 });

    const first = await purchaseCatalogItem({
        userId: user._id.toString(),
        itemId: 'frame_neon',
        idempotencyKey: 'purchase:frame_neon'
    });
    const second = await purchaseCatalogItem({
        userId: user._id.toString(),
        itemId: 'frame_neon',
        idempotencyKey: 'purchase:frame_neon'
    });

    const refreshedUser = await User.findById(user._id);
    const inventoryEntries = await UserInventoryItem.find({ userId: user._id });
    const purchaseTransactions = await Transaction.find({
        userId: user._id,
        idempotencyKey: 'purchase:frame_neon'
    });

    assert.equal(first.success, true);
    assert.equal(second.success, true);
    assert.equal(first.reward?.itemId, 'collectible_lucky_coin_totem');
    assert.equal(refreshedUser.coins, 6350);
    assert.equal(purchaseTransactions.length, 1);
    assert.equal(
        inventoryEntries.filter((entry) => entry.itemId === 'frame_neon').length,
        1
    );
    assert.equal(
        inventoryEntries.filter((entry) => entry.itemId === 'collectible_lucky_coin_totem').length,
        1
    );
});

test('equipInventoryItem rejects unowned cosmetics', async () => {
    const user = await createUser();

    await assert.rejects(
        () => equipInventoryItem({
            userId: user._id.toString(),
            itemId: 'frame_royal'
        }),
        /do not own this item/i
    );
});

test('equipping a purchased cosmetic marks it active in inventory and shop profile', async () => {
    const user = await createUser({ coins: 7000 });
    await purchaseCatalogItem({
        userId: user._id.toString(),
        itemId: 'frame_royal',
        idempotencyKey: 'purchase:frame_royal'
    });

    const result = await equipInventoryItem({
        userId: user._id.toString(),
        itemId: 'frame_royal'
    });

    const refreshedUser = await User.findById(user._id);
    const entry = await UserInventoryItem.findOne({
        userId: user._id,
        itemId: 'frame_royal'
    });

    assert.equal(result.success, true);
    assert.equal(refreshedUser.shopProfile.equipped.profileFrameItemId, 'frame_royal');
    assert.equal(entry.isEquipped, true);
});

test('using xp booster activates boost timer and consumes one charge', async () => {
    const user = await createUser({ coins: 7000 });
    await purchaseCatalogItem({
        userId: user._id.toString(),
        itemId: 'booster_xp_2x_1h',
        idempotencyKey: 'purchase:booster_xp_2x_1h'
    });

    const result = await useInventoryItem({
        userId: user._id.toString(),
        itemId: 'booster_xp_2x_1h',
        idempotencyKey: 'use:booster_xp_2x_1h'
    });

    const refreshedUser = await User.findById(user._id);
    const entry = await UserInventoryItem.findOne({
        userId: user._id,
        itemId: 'booster_xp_2x_1h'
    });
    const activation = await UserItemActivation.findOne({
        userId: user._id,
        itemId: 'booster_xp_2x_1h',
        status: 'active'
    });

    assert.equal(result.success, true);
    assert.equal(refreshedUser.shopProfile.activeBoosts.xpBoostItemId, 'booster_xp_2x_1h');
    assert.equal(refreshedUser.shopProfile.activeBoosts.xpBoostMultiplier, 2);
    assert.equal(entry.quantity, 0);
    assert.equal(entry.isActive, true);
    assert.ok(activation);
});

test('opening a capsule consumes it and grants a reward once', async () => {
    const user = await createUser({ coins: 7000 });
    await purchaseCatalogItem({
        userId: user._id.toString(),
        itemId: 'capsule_mystery',
        idempotencyKey: 'purchase:capsule_mystery'
    });

    const result = await useInventoryItem({
        userId: user._id.toString(),
        itemId: 'capsule_mystery',
        idempotencyKey: 'use:capsule_mystery'
    });

    const capsuleEntry = await UserInventoryItem.findOne({
        userId: user._id,
        itemId: 'capsule_mystery'
    });
    const rewardEntry = result.reward?.itemId
        ? await UserInventoryItem.findOne({
            userId: user._id,
            itemId: result.reward.itemId
        })
        : null;

    assert.equal(result.success, true);
    assert.ok(result.reward?.itemId);
    assert.equal(capsuleEntry.quantity, 0);
    assert.ok(rewardEntry);
});
