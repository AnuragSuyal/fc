const {
    DAILY_DEAL_ITEM_COUNT,
    FIRST_SHOP_PURCHASE_REWARD_ITEM_ID,
    SHOP_CATALOG,
    SHOP_CATALOG_BY_ID,
    SHOP_CATEGORIES,
    SHOP_COLLECTION_SETS
} = require('../config/shopCatalog');

const sortByOrder = (left, right) => {
    const leftOrder = Number(left?.sortOrder || 0);
    const rightOrder = Number(right?.sortOrder || 0);
    if (leftOrder !== rightOrder) {
        return leftOrder - rightOrder;
    }
    return String(left?.itemName || left?.itemId || '').localeCompare(
        String(right?.itemName || right?.itemId || '')
    );
};

const normalizeDate = (value) => {
    if (!value) return null;
    const parsed = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(parsed.getTime())) return null;
    return parsed;
};

const seededScore = (seed, value) => {
    const input = `${seed}:${value}`;
    let hash = 0;
    for (let index = 0; index < input.length; index += 1) {
        hash = ((hash << 5) - hash) + input.charCodeAt(index);
        hash |= 0;
    }
    return Math.abs(hash);
};

const startOfUtcDay = (at = new Date()) =>
    new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate()));

const endOfUtcDay = (at = new Date()) =>
    new Date(Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate() + 1));

const endOfUtcWeek = (at = new Date()) => {
    const day = at.getUTCDay();
    const daysUntilMonday = day === 0 ? 1 : (8 - day);
    return new Date(Date.UTC(
        at.getUTCFullYear(),
        at.getUTCMonth(),
        at.getUTCDate() + daysUntilMonday
    ));
};

const isWeekend = (at = new Date()) => {
    const day = at.getUTCDay();
    return day === 5 || day === 6 || day === 0;
};

const isItemAvailable = (item, at = new Date()) => {
    if (!item || item.isActive === false) return false;
    const now = normalizeDate(at) || new Date();
    const startAt = normalizeDate(item.releaseStartAt);
    const endAt = normalizeDate(item.releaseEndAt);
    if (startAt && now < startAt) return false;
    if (endAt && now > endAt) return false;
    return true;
};

const getCatalogItem = (itemId, { allowInactive = false, at = new Date() } = {}) => {
    const item = SHOP_CATALOG_BY_ID[String(itemId || '').trim()] || null;
    if (!item) return null;
    if (!allowInactive && !isItemAvailable(item, at)) return null;
    return item;
};

const getActiveCatalog = ({ at = new Date() } = {}) =>
    SHOP_CATALOG.filter((item) => isItemAvailable(item, at)).sort(sortByOrder);

const getActiveCatalogByCategory = ({ category, at = new Date() } = {}) =>
    getActiveCatalog({ at }).filter((item) => category === 'all' || item.itemCategory === category);

const pickStableItems = ({ items, count, seed, filter }) => {
    const filtered = Array.isArray(items)
        ? items.filter((item) => !filter || filter(item))
        : [];

    return filtered
        .slice()
        .sort((left, right) =>
            seededScore(seed, left.itemId) - seededScore(seed, right.itemId))
        .slice(0, count);
};

const resolveDailyDeals = ({ at = new Date(), catalog = null } = {}) => {
    const now = normalizeDate(at) || new Date();
    const activeCatalog = Array.isArray(catalog) ? catalog : getActiveCatalog({ at: now });
    const eligible = activeCatalog.filter((item) =>
        item.isDailyDealEligible !== false &&
        item.itemCategory !== 'bundles' &&
        item.itemType !== 'capsule');
    const seed = startOfUtcDay(now).toISOString().slice(0, 10);
    const picked = pickStableItems({
        items: eligible,
        count: DAILY_DEAL_ITEM_COUNT,
        seed: `daily:${seed}`
    });
    const discountSchedule = [20, 25, 15];

    return picked.map((item, index) => ({
        itemId: item.itemId,
        label: 'DAILY DEAL',
        discountPercent: discountSchedule[index] || 15,
        startsAt: startOfUtcDay(now),
        endsAt: endOfUtcDay(now)
    }));
};

const resolveWeekendSpotlights = ({ at = new Date(), catalog = null } = {}) => {
    const now = normalizeDate(at) || new Date();
    const activeCatalog = Array.isArray(catalog) ? catalog : getActiveCatalog({ at: now });
    const picked = pickStableItems({
        items: activeCatalog,
        count: 3,
        seed: `weekend:${startOfUtcDay(now).toISOString().slice(0, 10)}`,
        filter: (item) => item.limitedEdition === true || item.rarity === 'legendary' || item.rarity === 'mythic'
    });

    return picked.map((item) => ({
        itemId: item.itemId,
        label: isWeekend(now) ? 'WEEKEND SPECIAL' : 'WEEKEND PREVIEW',
        discountPercent: item.itemCategory === 'bundles' ? 18 : 12,
        startsAt: startOfUtcDay(now),
        endsAt: endOfUtcWeek(now),
        active: isWeekend(now)
    }));
};

const buildOfferMap = ({ at = new Date(), catalog = null } = {}) => {
    const offers = [
        ...resolveDailyDeals({ at, catalog }),
        ...resolveWeekendSpotlights({ at, catalog }).filter((offer) => offer.active === true)
    ];

    return offers.reduce((accumulator, offer) => {
        accumulator[offer.itemId] = offer;
        return accumulator;
    }, {});
};

const buildBundleValueCoins = (item) => {
    if (!Array.isArray(item?.bundleContents) || item.bundleContents.length === 0) {
        return 0;
    }

    return item.bundleContents.reduce((sum, entry) => {
        const child = SHOP_CATALOG_BY_ID[entry.itemId];
        if (!child) return sum;
        return sum + (Number(child.priceCoins || 0) * Math.max(Number(entry.quantity || 1), 1));
    }, 0);
};

const getCollectionItems = (collectionSetId, { at = new Date() } = {}) =>
    getActiveCatalog({ at }).filter((item) => item.collectionSetId === collectionSetId);

const buildDropTablePreview = (item) => {
    const dropTable = Array.isArray(item?.featureFlags?.dropTable)
        ? item.featureFlags.dropTable
        : [];
    const totalWeight = dropTable.reduce((sum, entry) => sum + Math.max(Number(entry.weight || 0), 0), 0) || 1;

    return dropTable.map((entry) => {
        const rewardItem = getCatalogItem(entry.itemId, { allowInactive: true });
        return {
            itemId: entry.itemId,
            itemName: rewardItem?.itemName || entry.itemId,
            rarity: rewardItem?.rarity || 'common',
            weight: Number(entry.weight || 0),
            chancePercent: Number((((Number(entry.weight || 0) / totalWeight) * 100)).toFixed(2)),
            quantity: Math.max(Number(entry.quantity || 1), 1)
        };
    });
};

const serializeCatalogItem = (item, context = {}) => {
    const now = normalizeDate(context.at) || new Date();
    const offer = context.offer || null;
    const owned = context.owned === true;
    const quantity = Math.max(Number(context.quantity || 0), owned ? 1 : 0);
    const remainingStock = item.stockCount > 0
        ? Math.max(Number(item.stockCount) - Math.max(Number(context.totalSold || 0), 0), 0)
        : null;
    const effectivePriceCoins = offer
        ? Math.max(0, Math.round(Number(item.priceCoins || 0) * ((100 - Number(offer.discountPercent || 0)) / 100)))
        : Number(item.priceCoins || 0);

    return {
        itemId: item.itemId,
        itemName: item.itemName,
        itemDescription: item.itemDescription,
        itemCategory: item.itemCategory,
        itemSubcategory: item.itemSubcategory,
        itemType: item.itemType,
        rarity: item.rarity,
        priceCoins: Number(item.priceCoins || 0),
        effectivePriceCoins,
        imageAsset: item.imageAsset || '',
        previewAsset: item.previewAsset || '',
        tags: Array.isArray(item.tags) ? item.tags : [],
        isConsumable: item.isConsumable === true,
        isEquippable: item.isEquippable === true,
        isTemporary: item.isTemporary === true,
        expiryDurationSeconds: Number(item.expiryDurationSeconds || 0),
        isStackable: item.isStackable === true,
        activationRequired: item.activationRequired === true,
        oneActivePerCategory: item.oneActivePerCategory === true,
        bundleOnly: item.bundleOnly === true,
        limitedEdition: item.limitedEdition === true,
        stockCount: Number(item.stockCount || 0),
        remainingStock,
        releaseStartAt: normalizeDate(item.releaseStartAt)?.toISOString() || null,
        releaseEndAt: normalizeDate(item.releaseEndAt)?.toISOString() || null,
        isFeatured: item.isFeatured === true,
        isPopular: item.isPopular === true,
        isDailyDeal: !!offer && offer.label === 'DAILY DEAL',
        offerLabel: offer?.label || '',
        discountPercent: Number(offer?.discountPercent || item.discountPercent || 0),
        offerEndsAt: offer?.endsAt ? normalizeDate(offer.endsAt)?.toISOString() : null,
        bundleContents: Array.isArray(item.bundleContents) ? item.bundleContents : [],
        bundleValueCoins: item.itemType === 'bundle' ? buildBundleValueCoins(item) : 0,
        collectionSetId: item.collectionSetId || '',
        featureFlags: item.featureFlags || {},
        previewStyle: item.previewStyle || {},
        equipSlot: item.equipSlot || '',
        purchaseLimit: Number(item.purchaseLimit || 0),
        isActive: item.isActive !== false,
        availableNow: isItemAvailable(item, now),
        owned,
        quantity,
        equipped: context.equipped === true,
        favorited: context.favorited === true,
        active: context.active === true,
        wishlisted: context.wishlisted === true,
        expired: context.expired === true,
        dropTablePreview: item.itemType === 'capsule' ? buildDropTablePreview(item) : []
    };
};

const buildCategorySummary = ({ at = new Date() } = {}) => {
    const catalog = getActiveCatalog({ at });
    return SHOP_CATEGORIES.map((category) => ({
        ...category,
        itemCount: category.id === 'all'
            ? catalog.length
            : catalog.filter((item) => item.itemCategory === category.id).length
    }));
};

module.exports = {
    FIRST_SHOP_PURCHASE_REWARD_ITEM_ID,
    SHOP_CATALOG,
    SHOP_CATALOG_BY_ID,
    SHOP_CATEGORIES,
    SHOP_COLLECTION_SETS,
    buildCategorySummary,
    buildDropTablePreview,
    buildOfferMap,
    getActiveCatalog,
    getActiveCatalogByCategory,
    getCatalogItem,
    getCollectionItems,
    isItemAvailable,
    resolveDailyDeals,
    resolveWeekendSpotlights,
    serializeCatalogItem,
    sortByOrder
};
