const PremiumEntitlement = require('../models/PremiumEntitlement');

const ENTITLEMENT_KEYS = Object.freeze({
    CHAT_COIN_TRANSFER_UNLOCK: 'chat_coin_transfer_unlock'
});

const getPremiumEntitlement = async ({
    userId,
    entitlementKey,
    session = null
} = {}) => {
    const query = PremiumEntitlement.findOne({
        userId,
        entitlementKey
    });
    return session ? query.session(session) : query;
};

const isPremiumEntitlementActive = (entitlement, { now = new Date() } = {}) => {
    if (!entitlement) return false;
    if (entitlement.status !== 'active') return false;
    if (entitlement.expiresAt && new Date(entitlement.expiresAt) <= now) {
        return false;
    }
    return true;
};

const activatePremiumEntitlement = async ({
    userId,
    entitlementKey,
    purchaseSource = 'system',
    purchaseAmountInr = 0,
    currency = 'INR',
    metadata = {},
    session = null
} = {}) => {
    const now = new Date();
    return PremiumEntitlement.findOneAndUpdate(
        {
            userId,
            entitlementKey
        },
        {
            $set: {
                purchaseSource,
                purchaseAmountInr,
                currency,
                status: 'active',
                purchasedAt: now,
                revokedAt: null,
                metadata
            }
        },
        {
            returnDocument: 'after',
            upsert: true,
            session
        }
    );
};

const revokePremiumEntitlement = async ({
    userId,
    entitlementKey,
    status = 'revoked',
    metadata = {},
    session = null
} = {}) => {
    const now = new Date();
    return PremiumEntitlement.findOneAndUpdate(
        {
            userId,
            entitlementKey
        },
        {
            $set: {
                status,
                revokedAt: now,
                metadata: {
                    ...(metadata || {}),
                    revokedAt: now.toISOString()
                }
            }
        },
        {
            returnDocument: 'after',
            session
        }
    );
};

const serializePremiumEntitlement = (entitlement) => ({
    id: entitlement?._id?.toString() || '',
    userId: entitlement?.userId?.toString?.() || '',
    entitlementKey: entitlement?.entitlementKey || '',
    purchaseSource: entitlement?.purchaseSource || '',
    purchaseAmountInr: Number(entitlement?.purchaseAmountInr || 0),
    currency: entitlement?.currency || 'INR',
    status: entitlement?.status || 'revoked',
    purchasedAt: entitlement?.purchasedAt ? new Date(entitlement.purchasedAt).toISOString() : null,
    revokedAt: entitlement?.revokedAt ? new Date(entitlement.revokedAt).toISOString() : null,
    expiresAt: entitlement?.expiresAt ? new Date(entitlement.expiresAt).toISOString() : null,
    metadata: entitlement?.metadata || {}
});

module.exports = {
    ENTITLEMENT_KEYS,
    activatePremiumEntitlement,
    getPremiumEntitlement,
    isPremiumEntitlementActive,
    revokePremiumEntitlement,
    serializePremiumEntitlement
};
