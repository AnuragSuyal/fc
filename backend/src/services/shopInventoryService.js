const mongoose = require('mongoose');

const Transaction = require('../models/Transaction');
const User = require('../models/User');
const UserInventoryItem = require('../models/UserInventoryItem');
const UserItemActivation = require('../models/UserItemActivation');
const UserWishlistItem = require('../models/UserWishlistItem');
const {
    buildProgressPayload,
    buildRealtimeIdentityPayload
} = require('./levelProgressionService');
const {
    FIRST_SHOP_PURCHASE_REWARD_ITEM_ID,
    SHOP_COLLECTION_SETS,
    buildCategorySummary,
    buildOfferMap,
    getActiveCatalog,
    getCatalogItem,
    getCollectionItems,
    resolveDailyDeals,
    resolveWeekendSpotlights,
    serializeCatalogItem,
    sortByOrder
} = require('./shopCatalogService');

const withSession = (query, session) => (session ? query.session(session) : query);

const INVENTORY_MUTATION_TYPES = Object.freeze({
    PURCHASE: 'shop_purchase',
    BUNDLE_PURCHASE: 'shop_bundle_purchase',
    CAPSULE_OPEN: 'shop_capsule_open',
    REWARD_GRANT: 'shop_reward_grant'
});

const EQUIPPED_ITEM_FIELDS = Object.freeze([
    'profileFrameItemId',
    'profileGlowItemId',
    'profileBackgroundItemId',
    'avatarBorderItemId',
    'nameplateItemId',
    'levelFrameSkinItemId',
    'roomCardSkinItemId',
    'popupCardThemeItemId',
    'chatBubbleItemId',
    'messageHighlightItemId',
    'entryEffectItemId',
    'micAuraItemId',
    'speakingGlowItemId'
]);

const BOOST_SLOTS = Object.freeze({
    xp_boost: {
        itemIdField: 'xpBoostItemId',
        expiresAtField: 'xpBoostExpiresAt',
        extraField: 'xpBoostMultiplier',
        defaultExtra: 1
    },
    profile_highlight: {
        itemIdField: 'profileHighlightItemId',
        expiresAtField: 'profileHighlightExpiresAt'
    },
    discover_boost: {
        itemIdField: 'discoverBoostItemId',
        expiresAtField: 'discoverBoostExpiresAt'
    },
    voice_aura: {
        itemIdField: 'voiceAuraBoostItemId',
        expiresAtField: 'voiceAuraBoostExpiresAt'
    }
});

const ensureShopProfileShape = (user) => {
    if (!user.shopProfile || typeof user.shopProfile !== 'object') user.shopProfile = {};
    if (!user.shopProfile.equipped || typeof user.shopProfile.equipped !== 'object') user.shopProfile.equipped = {};
    if (!user.shopProfile.activeBoosts || typeof user.shopProfile.activeBoosts !== 'object') user.shopProfile.activeBoosts = {};

    for (const field of EQUIPPED_ITEM_FIELDS) {
        if (typeof user.shopProfile.equipped[field] !== 'string') user.shopProfile.equipped[field] = '';
    }
    for (const config of Object.values(BOOST_SLOTS)) {
        if (typeof user.shopProfile.activeBoosts[config.itemIdField] !== 'string') user.shopProfile.activeBoosts[config.itemIdField] = '';
        if (user.shopProfile.activeBoosts[config.expiresAtField] === undefined) user.shopProfile.activeBoosts[config.expiresAtField] = null;
        if (config.extraField && typeof user.shopProfile.activeBoosts[config.extraField] !== 'number') {
            user.shopProfile.activeBoosts[config.extraField] = config.defaultExtra;
        }
    }
    if (!Array.isArray(user.shopProfile.recentlyViewedItemIds)) user.shopProfile.recentlyViewedItemIds = [];
    return user.shopProfile;
};

const normalizeRecentlyViewed = (values) => {
    const seen = new Set();
    const result = [];
    for (const value of values || []) {
        const itemId = String(value || '').trim();
        if (!itemId || seen.has(itemId)) continue;
        seen.add(itemId);
        result.push(itemId);
        if (result.length >= 12) break;
    }
    return result;
};

const runWithOptionalTransaction = async (work) => {
    const session = await mongoose.startSession();
    try {
        session.startTransaction();
        const result = await work(session);
        await session.commitTransaction();
        return result;
    } catch (error) {
        await session.abortTransaction();
        if (error?.message?.includes('Transaction numbers are only allowed')) {
            return work(null);
        }
        throw error;
    } finally {
        await session.endSession();
    }
};

const balanceBeforeSnapshot = (user) => ({
    coins: Number(user.coins || 0),
    gems: Number(user.gems || 0)
});

const totalSoldForItem = async (itemId, session) =>
    withSession(UserInventoryItem.countDocuments({ itemId }), session);

const serializeShopProfile = (user) => {
    const shopProfile = ensureShopProfileShape(user);
    return {
        equipped: { ...shopProfile.equipped },
        activeBoosts: { ...shopProfile.activeBoosts },
        firstShopPurchaseAt: shopProfile.firstShopPurchaseAt ? new Date(shopProfile.firstShopPurchaseAt).toISOString() : null,
        lastInventoryUpdatedAt: shopProfile.lastInventoryUpdatedAt ? new Date(shopProfile.lastInventoryUpdatedAt).toISOString() : null,
        recentlyViewedItemIds: [...shopProfile.recentlyViewedItemIds]
    };
};

const buildInventoryMaps = (entries) => {
    const byItemId = new Map();
    const favoriteItemIds = new Set();
    const equippedItemIds = new Set();
    const activeItemIds = new Set();
    const quantities = {};

    for (const entry of entries) {
        const itemId = String(entry.itemId || '').trim();
        if (!itemId) continue;
        byItemId.set(itemId, entry);
        quantities[itemId] = Math.max(Number(entry.quantity || 0), 0);
        if (entry.favorited === true) favoriteItemIds.add(itemId);
        if (entry.isEquipped === true) equippedItemIds.add(itemId);
        if (entry.isActive === true) activeItemIds.add(itemId);
    }

    return {
        byItemId,
        favoriteItemIds,
        equippedItemIds,
        activeItemIds,
        quantities
    };
};

const appendRecentlyViewed = (user, itemId) => {
    const shopProfile = ensureShopProfileShape(user);
    shopProfile.recentlyViewedItemIds = normalizeRecentlyViewed([
        itemId,
        ...(shopProfile.recentlyViewedItemIds || [])
    ]);
};

const clearBoostSlot = (user, boostSlot) => {
    const slot = BOOST_SLOTS[boostSlot];
    if (!slot) return;
    const activeBoosts = ensureShopProfileShape(user).activeBoosts;
    activeBoosts[slot.itemIdField] = '';
    activeBoosts[slot.expiresAtField] = null;
    if (slot.extraField) {
        activeBoosts[slot.extraField] = slot.defaultExtra;
    }
};

const pickWeightedReward = (dropTable) => {
    const entries = Array.isArray(dropTable) ? dropTable : [];
    const totalWeight = entries.reduce((sum, entry) => sum + Math.max(Number(entry.weight || 0), 0), 0);
    if (totalWeight <= 0) return null;
    let cursor = Math.random() * totalWeight;
    for (const entry of entries) {
        cursor -= Math.max(Number(entry.weight || 0), 0);
        if (cursor <= 0) return entry;
    }
    return entries[entries.length - 1] || null;
};

const isInventoryEntryExpired = (entry, now = new Date()) => {
    if (!entry?.expiryAt) return false;
    const expiryAt = new Date(entry.expiryAt);
    return !Number.isNaN(expiryAt.getTime()) && expiryAt <= now;
};

const serializeInventoryEntry = (entry, item, context = {}) => {
    const now = context.at instanceof Date ? context.at : new Date();
    const expired = isInventoryEntryExpired(entry, now);
    return {
        inventoryEntryId: entry._id?.toString?.() || '',
        userId: entry.userId?.toString?.() || '',
        itemId: entry.itemId,
        quantity: Math.max(Number(entry.quantity || 0), 0),
        acquiredAt: entry.acquiredAt ? new Date(entry.acquiredAt).toISOString() : null,
        expiryAt: entry.expiryAt ? new Date(entry.expiryAt).toISOString() : null,
        isExpired: expired,
        isEquipped: entry.isEquipped === true && !expired,
        isActive: entry.isActive === true && !expired,
        favorited: entry.favorited === true,
        sourceType: entry.sourceType || '',
        sourceReferenceId: entry.sourceReferenceId || '',
        lastUsedAt: entry.lastUsedAt ? new Date(entry.lastUsedAt).toISOString() : null,
        usageCount: Number(entry.usageCount || 0),
        metadata: entry.metadata || {},
        item: item ? serializeCatalogItem(item, {
            at: now,
            owned: true,
            quantity: entry.quantity,
            equipped: entry.isEquipped === true,
            active: entry.isActive === true,
            favorited: entry.favorited === true,
            expired
        }) : null
    };
};

const syncUserInventoryState = async (user, { session = null } = {}) => {
    const now = new Date();
    ensureShopProfileShape(user);
    const entries = await withSession(UserInventoryItem.find({ userId: user._id }), session);
    let userChanged = false;
    let entriesChanged = false;

    for (const entry of entries) {
        const expired = isInventoryEntryExpired(entry, now);
        if (!expired) continue;
        if (entry.isEquipped === true) {
            entry.isEquipped = false;
            entriesChanged = true;
        }
        if (entry.isActive === true) {
            entry.isActive = false;
            entriesChanged = true;
        }
    }

    const validEquippedIds = new Set(
        entries
            .filter((entry) => entry.isEquipped === true && !isInventoryEntryExpired(entry, now))
            .map((entry) => String(entry.itemId || ''))
            .filter(Boolean)
    );
    for (const field of EQUIPPED_ITEM_FIELDS) {
        const currentItemId = user.shopProfile.equipped[field];
        if (currentItemId && !validEquippedIds.has(currentItemId)) {
            user.shopProfile.equipped[field] = '';
            userChanged = true;
        }
    }

    for (const [boostSlot, config] of Object.entries(BOOST_SLOTS)) {
        const expiresAt = user.shopProfile.activeBoosts[config.expiresAtField];
        const parsedExpiry = expiresAt ? new Date(expiresAt) : null;
        if (parsedExpiry && !Number.isNaN(parsedExpiry.getTime()) && parsedExpiry <= now) {
            clearBoostSlot(user, boostSlot);
            userChanged = true;
        }
    }

    if (entriesChanged) {
        await Promise.all(entries.map((entry) => entry.save(session ? { session } : undefined)));
    }
    if (userChanged) {
        user.shopProfile.lastInventoryUpdatedAt = now;
        await user.save(session ? { session } : undefined);
    }

    await withSession(
        UserItemActivation.updateMany(
            {
                userId: user._id,
                status: 'active',
                expiresAt: { $lte: now }
            },
            {
                $set: {
                    status: 'expired',
                    updatedAt: now
                }
            }
        ),
        session
    );

    return entries;
};

const grantInventoryItem = async ({
    user,
    item,
    quantity = 1,
    sourceType,
    sourceReferenceId,
    session = null
}) => {
    const now = new Date();
    const nextQuantity = Math.max(Number(quantity || 1), 1);
    let entry = await withSession(
        UserInventoryItem.findOne({ userId: user._id, itemId: item.itemId }),
        session
    );

    if (!entry) {
        entry = new UserInventoryItem({
            userId: user._id,
            itemId: item.itemId,
            quantity: item.isStackable ? nextQuantity : 1,
            acquiredAt: now,
            expiryAt: item.isTemporary && Number(item.expiryDurationSeconds || 0) > 0
                ? new Date(now.getTime() + (Number(item.expiryDurationSeconds || 0) * 1000 * nextQuantity))
                : null,
            sourceType,
            sourceReferenceId
        });
        await entry.save(session ? { session } : undefined);
        return { entry, granted: true, skipped: false };
    }

    if (!item.isStackable && !item.isTemporary && Number(entry.quantity || 0) > 0) {
        return { entry, granted: false, skipped: true, reason: 'already_owned' };
    }

    if (item.isTemporary && Number(item.expiryDurationSeconds || 0) > 0) {
        const baseTime = entry.expiryAt && new Date(entry.expiryAt) > now ? new Date(entry.expiryAt) : now;
        entry.expiryAt = new Date(baseTime.getTime() + (Number(item.expiryDurationSeconds || 0) * 1000 * nextQuantity));
        entry.quantity = 1;
    } else if (item.isStackable) {
        entry.quantity = Math.max(Number(entry.quantity || 0), 0) + nextQuantity;
    } else {
        entry.quantity = 1;
    }

    entry.sourceType = sourceType;
    entry.sourceReferenceId = sourceReferenceId || '';
    await entry.save(session ? { session } : undefined);
    return { entry, granted: true, skipped: false };
};

const createShopTransaction = async ({
    user,
    type,
    item,
    pricePaid,
    balanceBefore,
    idempotencyKey,
    session = null,
    metadata = {}
}) => {
    const transaction = new Transaction({
        userId: user._id,
        type,
        amount: { coins: -Math.max(Number(pricePaid || 0), 0) },
        balanceBefore,
        balanceAfter: balanceBeforeSnapshot(user),
        reference: {
            itemId: item.itemType === 'bundle' ? undefined : item.itemId,
            bundleId: item.itemType === 'bundle' ? item.itemId : undefined,
            shopCategory: item.itemCategory,
            collectionSetId: item.collectionSetId || ''
        },
        currencyType: 'coins',
        quantityPurchased: 1,
        idempotencyKey: idempotencyKey || undefined,
        status: 'completed',
        description: item.itemType === 'bundle'
            ? `Purchased bundle ${item.itemName}`
            : `Purchased ${item.itemName}`,
        completedAt: new Date(),
        metadata
    });
    await transaction.save(session ? { session } : undefined);
    return transaction;
};

const emitInventoryRealtime = (io, user, payload = {}) => {
    if (!io || !user?._id) return;
    const userId = user._id.toString();
    const profilePayload = {
        userId,
        timestamp: new Date().toISOString(),
        user: buildRealtimeIdentityPayload(user),
        fields: {
            shopProfile: serializeShopProfile(user)
        }
    };
    io.to(`user:${userId}`).emit('balance_update', buildProgressPayload(user, {
        shopProfile: serializeShopProfile(user)
    }));
    io.to(`user:${userId}`).emit('profile:updated', profilePayload);
    io.to(`profile:${userId}`).emit('profile:updated', profilePayload);
    io.to(`user:${userId}`).emit('inventory:updated', {
        userId,
        timestamp: profilePayload.timestamp,
        shopProfile: serializeShopProfile(user),
        ...payload
    });
};

const getOwnedItemIds = (entries) => new Set(
    entries
        .filter((entry) => Number(entry.quantity || 0) > 0 || entry.isActive === true)
        .map((entry) => String(entry.itemId || ''))
        .filter(Boolean)
);

const buildCollectionProgress = (entries, { at = new Date() } = {}) => {
    const ownedItemIds = getOwnedItemIds(entries);
    return SHOP_COLLECTION_SETS.map((setDefinition) => {
        const items = getCollectionItems(setDefinition.collectionSetId, { at });
        const ownedCount = items.filter((item) => ownedItemIds.has(item.itemId)).length;
        return {
            collectionSetId: setDefinition.collectionSetId,
            name: setDefinition.name,
            description: setDefinition.description,
            totalItems: items.length,
            ownedItems: ownedCount,
            progressPercent: items.length > 0
                ? Number(((ownedCount / items.length) * 100).toFixed(1))
                : 0,
            complete: items.length > 0 && ownedCount >= items.length
        };
    });
};

const buildInventorySummary = (entries) => ({
    totalEntries: entries.length,
    ownedEntries: entries.filter((entry) => Number(entry.quantity || 0) > 0).length,
    equippedEntries: entries.filter((entry) => entry.isEquipped === true).length,
    activeEntries: entries.filter((entry) => entry.isActive === true).length,
    favoriteEntries: entries.filter((entry) => entry.favorited === true).length,
    expiredEntries: entries.filter((entry) => isInventoryEntryExpired(entry)).length
});

const buildCatalogSections = ({
    catalog,
    offerMap,
    inventoryEntries,
    wishlistEntries,
    user
}) => {
    const inventoryMaps = buildInventoryMaps(inventoryEntries);
    const wishlistIds = new Set(wishlistEntries.map((entry) => String(entry.itemId || '')));
    const activeCatalog = catalog.slice().sort(sortByOrder);
    const serializeMany = (items) => items.map((item) => serializeCatalogItem(item, {
        at: new Date(),
        offer: offerMap[item.itemId],
        owned: inventoryMaps.byItemId.has(item.itemId),
        quantity: inventoryMaps.quantities[item.itemId] || 0,
        equipped: inventoryMaps.equippedItemIds.has(item.itemId),
        active: inventoryMaps.activeItemIds.has(item.itemId),
        favorited: inventoryMaps.favoriteItemIds.has(item.itemId),
        wishlisted: wishlistIds.has(item.itemId)
    }));
    const recentlyViewedIds = ensureShopProfileShape(user).recentlyViewedItemIds || [];
    const recentlyViewedItems = recentlyViewedIds
        .map((itemId) => getCatalogItem(itemId, { allowInactive: true }))
        .filter(Boolean);
    const incompleteCollections = buildCollectionProgress(inventoryEntries)
        .filter((entry) => entry.totalItems > 0 && entry.complete !== true)
        .sort((left, right) => right.progressPercent - left.progressPercent);
    const recommended = incompleteCollections.length > 0
        ? getCollectionItems(incompleteCollections[0].collectionSetId)
            .filter((item) => !inventoryMaps.byItemId.has(item.itemId))
        : [];

    return {
        featured: serializeMany(activeCatalog.filter((item) => item.isFeatured === true).slice(0, 6)),
        newArrivals: serializeMany(activeCatalog.filter((item) => item.tags.includes('NEW')).slice(0, 8)),
        popular: serializeMany(activeCatalog.filter((item) => item.isPopular === true || item.tags.includes('POPULAR')).slice(0, 8)),
        limited: serializeMany(activeCatalog.filter((item) => item.limitedEdition === true).slice(0, 8)),
        dailyDeals: serializeMany(resolveDailyDeals({ catalog: activeCatalog }).map((offer) => getCatalogItem(offer.itemId)).filter(Boolean)),
        weekendSpecials: serializeMany(resolveWeekendSpotlights({ catalog: activeCatalog }).map((offer) => getCatalogItem(offer.itemId)).filter(Boolean)),
        bundles: serializeMany(activeCatalog.filter((item) => item.itemType === 'bundle')),
        mysteryCapsules: serializeMany(activeCatalog.filter((item) => item.itemType === 'capsule')),
        lowCostImpulse: serializeMany(activeCatalog.filter((item) => Number(item.priceCoins || 0) <= 350).slice(0, 8)),
        aspiration: serializeMany(activeCatalog.filter((item) => item.rarity === 'legendary' || item.rarity === 'mythic').slice(0, 8)),
        recentlyViewed: serializeMany(recentlyViewedItems),
        recommended: serializeMany(recommended.slice(0, 8)),
        wishlist: serializeMany(activeCatalog.filter((item) => wishlistIds.has(item.itemId))),
        collectionProgress: buildCollectionProgress(inventoryEntries)
    };
};

const buildShopHome = async ({ userId } = {}) => {
    const user = await User.findById(userId).select('coins gems xp level vipLevel shopProfile username avatar region bio coverPhoto status gameStats badges stats uid');
    if (!user) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }

    const inventoryEntries = await syncUserInventoryState(user);
    const wishlistEntries = await UserWishlistItem.find({ userId: user._id });
    const catalog = getActiveCatalog();
    const offerMap = buildOfferMap({ catalog });
    const inventoryMaps = buildInventoryMaps(inventoryEntries);
    const wishlistIds = new Set(wishlistEntries.map((entry) => String(entry.itemId || '')));
    return {
        balance: buildProgressPayload(user, { shopProfile: serializeShopProfile(user) }),
        shopProfile: serializeShopProfile(user),
        categories: buildCategorySummary(),
        catalog: catalog.map((item) => serializeCatalogItem(item, {
            offer: offerMap[item.itemId],
            owned: inventoryMaps.byItemId.has(item.itemId),
            quantity: inventoryMaps.quantities[item.itemId] || 0,
            equipped: inventoryMaps.equippedItemIds.has(item.itemId),
            active: inventoryMaps.activeItemIds.has(item.itemId),
            favorited: inventoryMaps.favoriteItemIds.has(item.itemId),
            wishlisted: wishlistIds.has(item.itemId)
        })),
        sections: buildCatalogSections({ catalog, offerMap, inventoryEntries, wishlistEntries, user }),
        inventorySummary: buildInventorySummary(inventoryEntries),
        firstPurchaseReward: serializeCatalogItem(
            getCatalogItem(FIRST_SHOP_PURCHASE_REWARD_ITEM_ID, { allowInactive: true }),
            { owned: inventoryEntries.some((entry) => entry.itemId === FIRST_SHOP_PURCHASE_REWARD_ITEM_ID) }
        )
    };
};

const buildInventory = async ({ userId } = {}) => {
    const user = await User.findById(userId).select('shopProfile');
    if (!user) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }
    const entries = await syncUserInventoryState(user);
    const sortedEntries = entries
        .slice()
        .sort((left, right) => new Date(right.updatedAt || right.acquiredAt || 0) - new Date(left.updatedAt || left.acquiredAt || 0));

    return {
        shopProfile: serializeShopProfile(user),
        summary: buildInventorySummary(sortedEntries),
        collections: buildCollectionProgress(sortedEntries),
        items: sortedEntries.map((entry) => serializeInventoryEntry(
            entry,
            getCatalogItem(entry.itemId, { allowInactive: true })
        ))
    };
};

const buildMutationResponse = async ({ user, item, transaction, grants = [], reward = null } = {}) => {
    const inventory = await buildInventory({ userId: user._id.toString() });
    return {
        success: true,
        transactionId: transaction?.transactionId || '',
        balance: buildProgressPayload(user, { shopProfile: serializeShopProfile(user) }),
        shopProfile: serializeShopProfile(user),
        item: item ? serializeCatalogItem(item, { owned: true }) : null,
        grants: grants.map((grant) => ({
            itemId: grant.item.itemId,
            itemName: grant.item.itemName,
            quantity: grant.quantity,
            skipped: grant.skipped === true
        })),
        reward: reward ? { itemId: reward.item.itemId, itemName: reward.item.itemName, quantity: reward.quantity } : null,
        inventory
    };
};

const purchaseCatalogItem = async ({ userId, itemId, idempotencyKey, io } = {}) => {
    const catalogItem = getCatalogItem(itemId);
    if (!catalogItem) {
        const error = new Error('Shop item not found');
        error.status = 404;
        throw error;
    }
    if (catalogItem.bundleOnly === true) {
        const error = new Error('This item is only available through special bundles.');
        error.status = 403;
        throw error;
    }

    if (idempotencyKey) {
        const existing = await Transaction.findOne({ userId, idempotencyKey, status: 'completed' }).sort({ createdAt: -1 });
        if (existing) {
            const user = await User.findById(userId);
            if (!user) {
                const error = new Error('User not found');
                error.status = 404;
                throw error;
            }
            return buildMutationResponse({ user, item: catalogItem, transaction: existing });
        }
    }

    const result = await runWithOptionalTransaction(async (session) => {
        const user = await withSession(User.findById(userId), session);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const entries = await syncUserInventoryState(user, { session });
        const ownedEntry = entries.find((entry) => entry.itemId === catalogItem.itemId);
        if (!catalogItem.isStackable && !catalogItem.isTemporary && ownedEntry && Number(ownedEntry.quantity || 0) > 0) {
            const error = new Error('You already own this item.');
            error.status = 409;
            throw error;
        }

        if (catalogItem.stockCount > 0) {
            const soldCount = await totalSoldForItem(catalogItem.itemId, session);
            if (soldCount >= Number(catalogItem.stockCount || 0)) {
                const error = new Error('This limited item is sold out.');
                error.status = 409;
                throw error;
            }
        }

        const offerMap = buildOfferMap();
        const offer = offerMap[catalogItem.itemId];
        const pricePaid = offer
            ? Math.max(0, Math.round(Number(catalogItem.priceCoins || 0) * ((100 - Number(offer.discountPercent || 0)) / 100)))
            : Number(catalogItem.priceCoins || 0);
        if (Number(user.coins || 0) < pricePaid) {
            const error = new Error('Insufficient coins');
            error.status = 400;
            throw error;
        }

        const balanceBefore = balanceBeforeSnapshot(user);
        user.coins = Number(user.coins || 0) - pricePaid;
        user.totalCoinsSpent = Number(user.totalCoinsSpent || 0) + pricePaid;
        ensureShopProfileShape(user).lastInventoryUpdatedAt = new Date();
        appendRecentlyViewed(user, catalogItem.itemId);

        const grants = [];
        if (catalogItem.itemType === 'bundle') {
            for (const bundleEntry of catalogItem.bundleContents || []) {
                const childItem = getCatalogItem(bundleEntry.itemId, { allowInactive: true });
                if (!childItem) continue;
                const grantResult = await grantInventoryItem({
                    user,
                    item: childItem,
                    quantity: bundleEntry.quantity,
                    sourceType: 'bundle_purchase',
                    sourceReferenceId: catalogItem.itemId,
                    session
                });
                grants.push({
                    item: childItem,
                    quantity: Math.max(Number(bundleEntry.quantity || 1), 1),
                    skipped: grantResult.skipped === true
                });
            }
        } else {
            const grantResult = await grantInventoryItem({
                user,
                item: catalogItem,
                quantity: 1,
                sourceType: 'shop_purchase',
                sourceReferenceId: catalogItem.itemId,
                session
            });
            grants.push({ item: catalogItem, quantity: 1, skipped: grantResult.skipped === true });
        }
        if (!grants.some((entry) => entry.skipped !== true)) {
            const error = new Error('You already own every unique item in this purchase.');
            error.status = 409;
            throw error;
        }

        let firstPurchaseReward = null;
        if (!user.shopProfile.firstShopPurchaseAt) {
            const rewardItem = getCatalogItem(FIRST_SHOP_PURCHASE_REWARD_ITEM_ID, { allowInactive: true });
            if (rewardItem) {
                const rewardGrant = await grantInventoryItem({
                    user,
                    item: rewardItem,
                    quantity: 1,
                    sourceType: 'first_shop_purchase_reward',
                    sourceReferenceId: catalogItem.itemId,
                    session
                });
                if (rewardGrant.skipped !== true) {
                    firstPurchaseReward = { item: rewardItem, quantity: 1 };
                }
            }
            user.shopProfile.firstShopPurchaseAt = new Date();
        }

        await user.save(session ? { session } : undefined);
        const transaction = await createShopTransaction({
            user,
            type: catalogItem.itemType === 'bundle'
                ? INVENTORY_MUTATION_TYPES.BUNDLE_PURCHASE
                : INVENTORY_MUTATION_TYPES.PURCHASE,
            item: catalogItem,
            pricePaid,
            balanceBefore,
            idempotencyKey,
            session,
            metadata: {
                offerLabel: offer?.label || '',
                discountPercent: Number(offer?.discountPercent || 0),
                grantedItemIds: grants.map((entry) => entry.item.itemId),
                firstPurchaseRewardItemId: firstPurchaseReward?.item?.itemId || ''
            }
        });
        return { user, transaction, grants, reward: firstPurchaseReward };
    });

    emitInventoryRealtime(io, result.user, { source: 'shop_purchase', itemId: catalogItem.itemId });
    return buildMutationResponse({
        user: result.user,
        item: catalogItem,
        transaction: result.transaction,
        grants: result.grants,
        reward: result.reward
    });
};

const toggleWishlistItem = async ({ userId, itemId } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item) {
        const error = new Error('Shop item not found');
        error.status = 404;
        throw error;
    }
    const existing = await UserWishlistItem.findOne({ userId, itemId });
    if (existing) {
        await existing.deleteOne();
        return { success: true, itemId, wishlisted: false };
    }
    await UserWishlistItem.create({ userId, itemId });
    return { success: true, itemId, wishlisted: true };
};

const setInventoryFavorite = async ({ userId, itemId, favorited } = {}) => {
    const entry = await UserInventoryItem.findOne({ userId, itemId });
    if (!entry) {
        const error = new Error('Inventory item not found');
        error.status = 404;
        throw error;
    }
    entry.favorited = favorited === true;
    await entry.save();
    return { success: true, itemId, favorited: entry.favorited === true };
};

const equipInventoryItem = async ({ userId, itemId, io } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item || item.isEquippable !== true || !item.equipSlot) {
        const error = new Error('This item cannot be equipped.');
        error.status = 400;
        throw error;
    }

    const result = await runWithOptionalTransaction(async (session) => {
        const user = await withSession(User.findById(userId), session);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        const entries = await syncUserInventoryState(user, { session });
        const targetEntry = entries.find((entry) => entry.itemId === itemId);
        if (!targetEntry || (Number(targetEntry.quantity || 0) <= 0 && targetEntry.isActive !== true)) {
            const error = new Error('You do not own this item.');
            error.status = 403;
            throw error;
        }
        if (isInventoryEntryExpired(targetEntry)) {
            const error = new Error('This item has expired.');
            error.status = 400;
            throw error;
        }
        for (const entry of entries) {
            if (entry.itemId === itemId) {
                entry.isEquipped = true;
            } else {
                const entryItem = getCatalogItem(entry.itemId, { allowInactive: true });
                if (entryItem?.equipSlot === item.equipSlot && entry.isEquipped === true) {
                    entry.isEquipped = false;
                }
            }
            await entry.save(session ? { session } : undefined);
        }
        user.shopProfile.equipped[item.equipSlot] = item.itemId;
        user.shopProfile.lastInventoryUpdatedAt = new Date();
        await user.save(session ? { session } : undefined);
        return { user };
    });

    emitInventoryRealtime(io, result.user, { source: 'equip', itemId });
    return { success: true, itemId, shopProfile: serializeShopProfile(result.user) };
};

const unequipInventoryItem = async ({ userId, itemId, io } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item || !item.equipSlot) {
        const error = new Error('This item cannot be unequipped.');
        error.status = 400;
        throw error;
    }

    const result = await runWithOptionalTransaction(async (session) => {
        const user = await withSession(User.findById(userId), session);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        const entry = await withSession(UserInventoryItem.findOne({ userId: user._id, itemId }), session);
        if (!entry) {
            const error = new Error('Inventory item not found');
            error.status = 404;
            throw error;
        }
        entry.isEquipped = false;
        await entry.save(session ? { session } : undefined);
        user.shopProfile.equipped[item.equipSlot] = '';
        user.shopProfile.lastInventoryUpdatedAt = new Date();
        await user.save(session ? { session } : undefined);
        return { user };
    });

    emitInventoryRealtime(io, result.user, { source: 'unequip', itemId });
    return { success: true, itemId, shopProfile: serializeShopProfile(result.user) };
};

const applyBoosterActivation = async ({ user, item, entry, session }) => {
    const boostSlot = item.featureFlags?.boostSlot || '';
    const durationSeconds = Math.max(Number(item.featureFlags?.durationSeconds || 0), 0);
    if (!boostSlot || durationSeconds <= 0) {
        const error = new Error('This boost is not configured correctly.');
        error.status = 400;
        throw error;
    }
    const slotConfig = BOOST_SLOTS[boostSlot];
    if (!slotConfig) {
        const error = new Error('Unknown boost slot');
        error.status = 400;
        throw error;
    }
    const expiresAt = user.shopProfile.activeBoosts[slotConfig.expiresAtField];
    if (expiresAt && new Date(expiresAt) > new Date()) {
        const error = new Error('A similar boost is already active.');
        error.status = 409;
        throw error;
    }
    if (Number(entry.quantity || 0) <= 0) {
        const error = new Error('No charges remaining for this boost.');
        error.status = 400;
        throw error;
    }

    entry.quantity = Math.max(Number(entry.quantity || 0) - 1, 0);
    entry.isActive = true;
    entry.lastUsedAt = new Date();
    entry.usageCount = Math.max(Number(entry.usageCount || 0), 0) + 1;
    await entry.save(session ? { session } : undefined);

    const startedAt = new Date();
    const nextExpiresAt = new Date(startedAt.getTime() + (durationSeconds * 1000));
    user.shopProfile.activeBoosts[slotConfig.itemIdField] = item.itemId;
    user.shopProfile.activeBoosts[slotConfig.expiresAtField] = nextExpiresAt;
    if (slotConfig.extraField) {
        user.shopProfile.activeBoosts[slotConfig.extraField] = Number(item.featureFlags?.multiplier || 1);
    }
    user.shopProfile.lastInventoryUpdatedAt = startedAt;
    await user.save(session ? { session } : undefined);
    await UserItemActivation.create([{
        userId: user._id,
        itemId: item.itemId,
        inventoryEntryId: entry._id,
        startedAt,
        expiresAt: nextExpiresAt,
        status: 'active',
        sourceType: 'inventory_use',
        sourceReferenceId: item.itemId
    }], session ? { session } : undefined);

    return nextExpiresAt;
};

const openCapsuleItem = async ({ userId, itemId, idempotencyKey, io } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item || item.itemType !== 'capsule') {
        const error = new Error('This item cannot be opened.');
        error.status = 400;
        throw error;
    }

    if (idempotencyKey) {
        const existing = await Transaction.findOne({ userId, idempotencyKey, status: 'completed' }).sort({ createdAt: -1 });
        if (existing) {
            const user = await User.findById(userId);
            if (!user) {
                const error = new Error('User not found');
                error.status = 404;
                throw error;
            }
            const rewardItemId = existing.reference?.rewardItemId || '';
            const rewardItem = rewardItemId ? getCatalogItem(rewardItemId, { allowInactive: true }) : null;
            return buildMutationResponse({
                user,
                item,
                transaction: existing,
                reward: rewardItem ? { item: rewardItem, quantity: Number(existing.metadata?.rewardQuantity || 1) } : null
            });
        }
    }

    const result = await runWithOptionalTransaction(async (session) => {
        const user = await withSession(User.findById(userId), session);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        const entries = await syncUserInventoryState(user, { session });
        const capsuleEntry = entries.find((entry) => entry.itemId === item.itemId);
        if (!capsuleEntry || Number(capsuleEntry.quantity || 0) <= 0) {
            const error = new Error('You do not own this capsule.');
            error.status = 403;
            throw error;
        }

        const dropTable = Array.isArray(item.featureFlags?.dropTable) ? item.featureFlags.dropTable : [];
        let rewardConfig = null;
        let rewardItem = null;
        for (let attempt = 0; attempt < 12; attempt += 1) {
            rewardConfig = pickWeightedReward(dropTable);
            rewardItem = rewardConfig ? getCatalogItem(rewardConfig.itemId, { allowInactive: true }) : null;
            if (rewardItem) break;
        }
        if (!rewardItem) {
            const error = new Error('No reward is configured for this capsule.');
            error.status = 500;
            throw error;
        }

        capsuleEntry.quantity = Math.max(Number(capsuleEntry.quantity || 0) - 1, 0);
        capsuleEntry.lastUsedAt = new Date();
        capsuleEntry.usageCount = Math.max(Number(capsuleEntry.usageCount || 0), 0) + 1;
        await capsuleEntry.save(session ? { session } : undefined);

        const rewardQuantity = Math.max(Number(rewardConfig?.quantity || 1), 1);
        const rewardGrant = await grantInventoryItem({
            user,
            item: rewardItem,
            quantity: rewardQuantity,
            sourceType: 'capsule_reward',
            sourceReferenceId: item.itemId,
            session
        });

        user.shopProfile.lastInventoryUpdatedAt = new Date();
        await user.save(session ? { session } : undefined);

        const transaction = new Transaction({
            userId: user._id,
            type: INVENTORY_MUTATION_TYPES.CAPSULE_OPEN,
            amount: { coins: 0 },
            balanceBefore: balanceBeforeSnapshot(user),
            balanceAfter: balanceBeforeSnapshot(user),
            reference: {
                itemId: item.itemId,
                rewardItemId: rewardItem.itemId,
                shopCategory: item.itemCategory,
                collectionSetId: rewardItem.collectionSetId || ''
            },
            currencyType: 'coins',
            quantityPurchased: 1,
            idempotencyKey: idempotencyKey || undefined,
            status: 'completed',
            description: `Opened ${item.itemName}`,
            completedAt: new Date(),
            metadata: {
                rewardQuantity,
                rewardSkipped: rewardGrant.skipped === true
            }
        });
        await transaction.save(session ? { session } : undefined);

        return {
            user,
            transaction,
            reward: {
                item: rewardItem,
                quantity: rewardQuantity
            }
        };
    });

    emitInventoryRealtime(io, result.user, { source: 'capsule_open', itemId });
    return buildMutationResponse({
        user: result.user,
        item,
        transaction: result.transaction,
        reward: result.reward
    });
};

const useInventoryItem = async ({ userId, itemId, idempotencyKey, io } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item) {
        const error = new Error('Inventory item not found');
        error.status = 404;
        throw error;
    }
    if (item.itemType === 'capsule') {
        return openCapsuleItem({ userId, itemId, idempotencyKey, io });
    }
    if (item.activationRequired !== true) {
        const error = new Error('This item cannot be activated.');
        error.status = 400;
        throw error;
    }

    const result = await runWithOptionalTransaction(async (session) => {
        const user = await withSession(User.findById(userId), session);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        const entries = await syncUserInventoryState(user, { session });
        const entry = entries.find((inventoryEntry) => inventoryEntry.itemId === item.itemId);
        if (!entry) {
            const error = new Error('You do not own this item.');
            error.status = 403;
            throw error;
        }

        const expiresAt = await applyBoosterActivation({ user, item, entry, session });
        return { user, expiresAt };
    });

    emitInventoryRealtime(io, result.user, { source: 'activate', itemId });
    return {
        success: true,
        itemId,
        expiresAt: result.expiresAt.toISOString(),
        shopProfile: serializeShopProfile(result.user)
    };
};

const recordItemView = async ({ userId, itemId } = {}) => {
    const item = getCatalogItem(itemId, { allowInactive: true });
    if (!item) {
        const error = new Error('Shop item not found');
        error.status = 404;
        throw error;
    }
    const user = await User.findById(userId);
    if (!user) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }
    appendRecentlyViewed(user, itemId);
    user.shopProfile.lastInventoryUpdatedAt = user.shopProfile.lastInventoryUpdatedAt || new Date();
    await user.save();
    return { success: true, recentlyViewedItemIds: [...user.shopProfile.recentlyViewedItemIds] };
};

module.exports = {
    buildInventory,
    buildShopHome,
    equipInventoryItem,
    openCapsuleItem,
    purchaseCatalogItem,
    recordItemView,
    serializeInventoryEntry,
    serializeShopProfile,
    setInventoryFavorite,
    syncUserInventoryState,
    toggleWishlistItem,
    unequipInventoryItem,
    useInventoryItem
};
