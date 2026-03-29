const Gift = require('../models/Gift');
const {
    ACTIVE_GIFT_CATALOG,
    ACTIVE_GIFT_IDS,
    buildGiftLookupQuery
} = require('../utils/giftCatalog');

const GIFT_SYNC_TTL_MS = 60 * 1000;

let lastGiftSyncAt = 0;
let syncPromise = null;

async function syncGiftCatalog({ force = false } = {}) {
    const now = Date.now();
    if (!force && syncPromise) {
        return syncPromise;
    }

    if (!force && lastGiftSyncAt && now - lastGiftSyncAt < GIFT_SYNC_TTL_MS) {
        return {
            activeCount: ACTIVE_GIFT_CATALOG.length,
            deactivatedCount: 0,
            skipped: true
        };
    }

    syncPromise = (async () => {
        const operations = ACTIVE_GIFT_CATALOG.map((gift) => ({
            updateOne: {
                filter: { giftId: gift.giftId },
                update: {
                    $set: gift
                },
                upsert: true
            }
        }));

        if (operations.length > 0) {
            await Gift.bulkWrite(operations, { ordered: false });
        }

        const staleResult = await Gift.updateMany(
            {
                $or: [
                    { giftId: { $exists: false } },
                    { giftId: { $nin: ACTIVE_GIFT_IDS } }
                ],
                active: true
            },
            {
                $set: {
                    active: false
                }
            }
        );

        lastGiftSyncAt = Date.now();

        return {
            activeCount: ACTIVE_GIFT_CATALOG.length,
            deactivatedCount: staleResult.modifiedCount || 0,
            skipped: false
        };
    })();

    try {
        return await syncPromise;
    } finally {
        syncPromise = null;
    }
}

async function findGiftByIdentifier(identifier, { activeOnly = false } = {}) {
    const query = buildGiftLookupQuery(identifier);
    if (!query) return null;

    const finalQuery = activeOnly
        ? { $and: [query, { active: true }] }
        : query;

    let gift = await Gift.findOne(finalQuery);
    if (gift) return gift;

    await syncGiftCatalog({ force: true });
    return Gift.findOne(finalQuery);
}

module.exports = {
    findGiftByIdentifier,
    syncGiftCatalog
};
