const DEFAULT_DRAGON_PACKET_PRODUCTS = Object.freeze([
    {
        sku: 'dragon_packet_small_199_inr',
        packageType: 'small',
        name: 'Dragon Packet Small',
        priceInr: 199,
        currency: 'INR',
        packetCoinAmount: 800,
        artworkAssetKey: 'golden_dragon_packet_small',
        badgeLabel: 'Starter Fire'
    },
    {
        sku: 'dragon_packet_medium_499_inr',
        packageType: 'medium',
        name: 'Dragon Packet Medium',
        priceInr: 499,
        currency: 'INR',
        packetCoinAmount: 2200,
        artworkAssetKey: 'golden_dragon_packet_medium',
        badgeLabel: 'Hot Pick'
    },
    {
        sku: 'dragon_packet_large_999_inr',
        packageType: 'large',
        name: 'Dragon Packet Large',
        priceInr: 999,
        currency: 'INR',
        packetCoinAmount: 6000,
        artworkAssetKey: 'golden_dragon_packet_large',
        badgeLabel: 'Dragon Storm'
    }
]);

const DEFAULT_DRAGON_PACKET_CONFIG = Object.freeze({
    featureEnabled: true,
    allowMockPurchases: process.env.NODE_ENV !== 'production',
    allowedRoomTypes: ['voice'],
    eventDurationMs: 10000,
    participantJoinCutoffRemainingMs: 5000,
    minimumRoomPresenceSeconds: 2,
    minimumAccountAgeDaysToClaim: 0,
    requireVerifiedAccountToClaim: false,
    activatorCanClaim: false,
    basePoolPercentage: 30,
    maxSharePercentagePerUser: 20,
    minValidTapsToParticipate: 1,
    maxCountedTapsPerSecond: 8,
    maxTotalCountedTaps: 50,
    maxCountedTapsPerRollingWindow: 14,
    rollingWindowSeconds: 2,
    leaderboardBroadcastIntervalMs: 1000,
    reconcileIntervalMs: 5000,
    suspiciousRegularityToleranceMs: 8,
    suspiciousRegularityMinimumIntervals: 6,
    inventoryRefundMode: 'restore_inventory',
    visualType: 'golden_dragon_default',
    products: DEFAULT_DRAGON_PACKET_PRODUCTS,
    diminishingReturns: Object.freeze([
        { upToTap: 10, scorePerTap: 1.0 },
        { upToTap: 20, scorePerTap: 0.7 },
        { upToTap: 35, scorePerTap: 0.4 },
        { upToTap: 50, scorePerTap: 0.2 }
    ])
});

let runtimeOverrides = {};

const parseBoolean = (value, fallback) => {
    if (value === undefined || value === null || value === '') {
        return fallback;
    }
    if (typeof value === 'boolean') {
        return value;
    }

    const normalized = String(value).trim().toLowerCase();
    if (['1', 'true', 'yes', 'on'].includes(normalized)) {
        return true;
    }
    if (['0', 'false', 'no', 'off'].includes(normalized)) {
        return false;
    }
    return fallback;
};

const parseInteger = (value, fallback, { min = null, max = null } = {}) => {
    const parsed = Number.parseInt(value, 10);
    if (!Number.isFinite(parsed)) {
        return fallback;
    }
    if (min != null && parsed < min) {
        return fallback;
    }
    if (max != null && parsed > max) {
        return fallback;
    }
    return parsed;
};

const mergeObjects = (base, override) => {
    const output = { ...base };

    Object.entries(override || {}).forEach(([key, value]) => {
        if (
            value &&
            typeof value === 'object' &&
            !Array.isArray(value) &&
            base?.[key] &&
            typeof base[key] === 'object' &&
            !Array.isArray(base[key])
        ) {
            output[key] = mergeObjects(base[key], value);
            return;
        }

        output[key] = value;
    });

    return output;
};

const buildEnvConfig = () => ({
    featureEnabled: parseBoolean(
        process.env.DRAGON_PACKET_FEATURE_ENABLED,
        DEFAULT_DRAGON_PACKET_CONFIG.featureEnabled
    ),
    allowMockPurchases: parseBoolean(
        process.env.DRAGON_PACKET_ALLOW_MOCK_PURCHASES,
        DEFAULT_DRAGON_PACKET_CONFIG.allowMockPurchases
    ),
    eventDurationMs: parseInteger(
        process.env.DRAGON_PACKET_EVENT_DURATION_MS,
        DEFAULT_DRAGON_PACKET_CONFIG.eventDurationMs,
        { min: 1000 }
    ),
    participantJoinCutoffRemainingMs: parseInteger(
        process.env.DRAGON_PACKET_JOIN_CUTOFF_REMAINING_MS,
        DEFAULT_DRAGON_PACKET_CONFIG.participantJoinCutoffRemainingMs,
        { min: 0 }
    ),
    minimumRoomPresenceSeconds: parseInteger(
        process.env.DRAGON_PACKET_MIN_ROOM_PRESENCE_SECONDS,
        DEFAULT_DRAGON_PACKET_CONFIG.minimumRoomPresenceSeconds,
        { min: 0 }
    ),
    minimumAccountAgeDaysToClaim: parseInteger(
        process.env.DRAGON_PACKET_MIN_ACCOUNT_AGE_DAYS_TO_CLAIM,
        DEFAULT_DRAGON_PACKET_CONFIG.minimumAccountAgeDaysToClaim,
        { min: 0 }
    ),
    requireVerifiedAccountToClaim: parseBoolean(
        process.env.DRAGON_PACKET_REQUIRE_VERIFIED_ACCOUNT_TO_CLAIM,
        DEFAULT_DRAGON_PACKET_CONFIG.requireVerifiedAccountToClaim
    ),
    activatorCanClaim: parseBoolean(
        process.env.DRAGON_PACKET_ACTIVATOR_CAN_CLAIM,
        DEFAULT_DRAGON_PACKET_CONFIG.activatorCanClaim
    ),
    basePoolPercentage: parseInteger(
        process.env.DRAGON_PACKET_BASE_POOL_PERCENTAGE,
        DEFAULT_DRAGON_PACKET_CONFIG.basePoolPercentage,
        { min: 0, max: 100 }
    ),
    maxSharePercentagePerUser: parseInteger(
        process.env.DRAGON_PACKET_MAX_SHARE_PERCENTAGE_PER_USER,
        DEFAULT_DRAGON_PACKET_CONFIG.maxSharePercentagePerUser,
        { min: 1, max: 100 }
    ),
    minValidTapsToParticipate: parseInteger(
        process.env.DRAGON_PACKET_MIN_VALID_TAPS_TO_PARTICIPATE,
        DEFAULT_DRAGON_PACKET_CONFIG.minValidTapsToParticipate,
        { min: 1 }
    ),
    maxCountedTapsPerSecond: parseInteger(
        process.env.DRAGON_PACKET_MAX_COUNTED_TAPS_PER_SECOND,
        DEFAULT_DRAGON_PACKET_CONFIG.maxCountedTapsPerSecond,
        { min: 1 }
    ),
    maxTotalCountedTaps: parseInteger(
        process.env.DRAGON_PACKET_MAX_TOTAL_COUNTED_TAPS,
        DEFAULT_DRAGON_PACKET_CONFIG.maxTotalCountedTaps,
        { min: 1 }
    ),
    maxCountedTapsPerRollingWindow: parseInteger(
        process.env.DRAGON_PACKET_MAX_COUNTED_TAPS_PER_ROLLING_WINDOW,
        DEFAULT_DRAGON_PACKET_CONFIG.maxCountedTapsPerRollingWindow,
        { min: 1 }
    ),
    rollingWindowSeconds: parseInteger(
        process.env.DRAGON_PACKET_ROLLING_WINDOW_SECONDS,
        DEFAULT_DRAGON_PACKET_CONFIG.rollingWindowSeconds,
        { min: 1 }
    ),
    leaderboardBroadcastIntervalMs: parseInteger(
        process.env.DRAGON_PACKET_LEADERBOARD_BROADCAST_INTERVAL_MS,
        DEFAULT_DRAGON_PACKET_CONFIG.leaderboardBroadcastIntervalMs,
        { min: 250 }
    ),
    reconcileIntervalMs: parseInteger(
        process.env.DRAGON_PACKET_RECONCILE_INTERVAL_MS,
        DEFAULT_DRAGON_PACKET_CONFIG.reconcileIntervalMs,
        { min: 1000 }
    )
});

const validateDragonPacketConfig = (config) => {
    const validated = mergeObjects(DEFAULT_DRAGON_PACKET_CONFIG, config || {});
    if (!Array.isArray(validated.products) || validated.products.length === 0) {
        throw new Error('Dragon packet products are required');
    }
    if (validated.basePoolPercentage < 0 || validated.basePoolPercentage > 100) {
        throw new Error('Dragon packet basePoolPercentage must be between 0 and 100');
    }
    if (validated.maxSharePercentagePerUser < 1 || validated.maxSharePercentagePerUser > 100) {
        throw new Error('Dragon packet maxSharePercentagePerUser must be between 1 and 100');
    }
    if (validated.eventDurationMs < 1000) {
        throw new Error('Dragon packet eventDurationMs must be at least 1000');
    }
    return validated;
};

const getDragonPacketConfig = () => validateDragonPacketConfig(
    mergeObjects(
        mergeObjects(DEFAULT_DRAGON_PACKET_CONFIG, buildEnvConfig()),
        runtimeOverrides
    )
);

const getDragonPacketProducts = () =>
    getDragonPacketConfig().products.map((product) => ({ ...product }));

const getDragonPacketProductBySku = (sku) => {
    const normalizedSku = String(sku || '').trim();
    if (!normalizedSku) {
        return null;
    }

    return getDragonPacketProducts().find(
        (product) => product.sku === normalizedSku
    ) || null;
};

const buildPublicDragonPacketConfig = () => {
    const config = getDragonPacketConfig();
    return {
        featureEnabled: config.featureEnabled,
        allowedRoomTypes: [...config.allowedRoomTypes],
        eventDurationMs: config.eventDurationMs,
        participantJoinCutoffRemainingMs: config.participantJoinCutoffRemainingMs,
        minimumRoomPresenceSeconds: config.minimumRoomPresenceSeconds,
        minimumAccountAgeDaysToClaim: config.minimumAccountAgeDaysToClaim,
        requireVerifiedAccountToClaim: config.requireVerifiedAccountToClaim,
        activatorCanClaim: config.activatorCanClaim,
        basePoolPercentage: config.basePoolPercentage,
        maxSharePercentagePerUser: config.maxSharePercentagePerUser,
        minValidTapsToParticipate: config.minValidTapsToParticipate,
        maxCountedTapsPerSecond: config.maxCountedTapsPerSecond,
        maxTotalCountedTaps: config.maxTotalCountedTaps,
        maxCountedTapsPerRollingWindow: config.maxCountedTapsPerRollingWindow,
        rollingWindowSeconds: config.rollingWindowSeconds,
        leaderboardBroadcastIntervalMs: config.leaderboardBroadcastIntervalMs,
        inventoryRefundMode: config.inventoryRefundMode,
        products: getDragonPacketProducts()
    };
};

const setDragonPacketConfigForTests = (overrides = {}) => {
    runtimeOverrides = mergeObjects({}, overrides);
};

const clearDragonPacketConfigForTests = () => {
    runtimeOverrides = {};
};

module.exports = {
    DEFAULT_DRAGON_PACKET_CONFIG,
    DEFAULT_DRAGON_PACKET_PRODUCTS,
    buildPublicDragonPacketConfig,
    clearDragonPacketConfigForTests,
    getDragonPacketConfig,
    getDragonPacketProductBySku,
    getDragonPacketProducts,
    setDragonPacketConfigForTests
};
