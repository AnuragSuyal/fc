const DEFAULT_COIN_TRANSFER_CONFIG = Object.freeze({
    featureEnabled: true,
    unlockPriceInr: 599,
    unlockCurrency: 'INR',
    unlockEntitlementKey: 'chat_coin_transfer_unlock',
    unlockProductCode: 'chat_coin_transfer_unlock_599_inr',
    minTransferAmount: 100,
    maxTransferPerTxn: 100000,
    dailySendLimitAmount: 50000,
    dailySendLimitCount: 20,
    monthlySendLimitAmount: 300000,
    monthlySendLimitCount: 200,
    cooldownSecondsBetweenTransfers: 30,
    maxUniqueReceiversPerDay: 10,
    maxReceivedFromSameSenderPerDay: 50000,
    accountAgeMinDaysForTransfer: 7,
    minFriendshipAgeHours: 24,
    minChatMessagesExchanged: 0,
    requireVerifiedAccount: false,
    receiverPercentage: 70,
    platformPercentage: 30,
    suspiciousVelocityThresholds: {
        windowSeconds: 600,
        maxTransfers: 5,
        maxGrossAmount: 20000,
        circularWindowHours: 24,
        circularTransferCount: 4,
        circularGrossAmount: 25000
    },
    platformAccountKey: 'chat_coin_transfer_platform_margin',
    allowMockUnlockPurchases: process.env.NODE_ENV !== 'production'
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
        process.env.COIN_TRANSFER_FEATURE_ENABLED,
        DEFAULT_COIN_TRANSFER_CONFIG.featureEnabled
    ),
    unlockPriceInr: parseInteger(
        process.env.COIN_TRANSFER_UNLOCK_PRICE_INR,
        DEFAULT_COIN_TRANSFER_CONFIG.unlockPriceInr,
        { min: 1 }
    ),
    minTransferAmount: parseInteger(
        process.env.COIN_TRANSFER_MIN_AMOUNT,
        DEFAULT_COIN_TRANSFER_CONFIG.minTransferAmount,
        { min: 1 }
    ),
    maxTransferPerTxn: parseInteger(
        process.env.COIN_TRANSFER_MAX_PER_TXN,
        DEFAULT_COIN_TRANSFER_CONFIG.maxTransferPerTxn,
        { min: 1 }
    ),
    dailySendLimitAmount: parseInteger(
        process.env.COIN_TRANSFER_DAILY_AMOUNT_LIMIT,
        DEFAULT_COIN_TRANSFER_CONFIG.dailySendLimitAmount,
        { min: 1 }
    ),
    dailySendLimitCount: parseInteger(
        process.env.COIN_TRANSFER_DAILY_COUNT_LIMIT,
        DEFAULT_COIN_TRANSFER_CONFIG.dailySendLimitCount,
        { min: 1 }
    ),
    monthlySendLimitAmount: parseInteger(
        process.env.COIN_TRANSFER_MONTHLY_AMOUNT_LIMIT,
        DEFAULT_COIN_TRANSFER_CONFIG.monthlySendLimitAmount,
        { min: 1 }
    ),
    monthlySendLimitCount: parseInteger(
        process.env.COIN_TRANSFER_MONTHLY_COUNT_LIMIT,
        DEFAULT_COIN_TRANSFER_CONFIG.monthlySendLimitCount,
        { min: 1 }
    ),
    cooldownSecondsBetweenTransfers: parseInteger(
        process.env.COIN_TRANSFER_COOLDOWN_SECONDS,
        DEFAULT_COIN_TRANSFER_CONFIG.cooldownSecondsBetweenTransfers,
        { min: 0 }
    ),
    maxUniqueReceiversPerDay: parseInteger(
        process.env.COIN_TRANSFER_MAX_UNIQUE_RECEIVERS_PER_DAY,
        DEFAULT_COIN_TRANSFER_CONFIG.maxUniqueReceiversPerDay,
        { min: 1 }
    ),
    maxReceivedFromSameSenderPerDay: parseInteger(
        process.env.COIN_TRANSFER_MAX_RECEIVED_FROM_SAME_SENDER_PER_DAY,
        DEFAULT_COIN_TRANSFER_CONFIG.maxReceivedFromSameSenderPerDay,
        { min: 1 }
    ),
    accountAgeMinDaysForTransfer: parseInteger(
        process.env.COIN_TRANSFER_ACCOUNT_AGE_MIN_DAYS,
        DEFAULT_COIN_TRANSFER_CONFIG.accountAgeMinDaysForTransfer,
        { min: 0 }
    ),
    minFriendshipAgeHours: parseInteger(
        process.env.COIN_TRANSFER_MIN_FRIENDSHIP_AGE_HOURS,
        DEFAULT_COIN_TRANSFER_CONFIG.minFriendshipAgeHours,
        { min: 0 }
    ),
    minChatMessagesExchanged: parseInteger(
        process.env.COIN_TRANSFER_MIN_CHAT_MESSAGES_EXCHANGED,
        DEFAULT_COIN_TRANSFER_CONFIG.minChatMessagesExchanged,
        { min: 0 }
    ),
    requireVerifiedAccount: parseBoolean(
        process.env.COIN_TRANSFER_REQUIRE_VERIFIED_ACCOUNT,
        DEFAULT_COIN_TRANSFER_CONFIG.requireVerifiedAccount
    ),
    receiverPercentage: parseInteger(
        process.env.COIN_TRANSFER_RECEIVER_PERCENTAGE,
        DEFAULT_COIN_TRANSFER_CONFIG.receiverPercentage,
        { min: 0, max: 100 }
    ),
    platformPercentage: parseInteger(
        process.env.COIN_TRANSFER_PLATFORM_PERCENTAGE,
        DEFAULT_COIN_TRANSFER_CONFIG.platformPercentage,
        { min: 0, max: 100 }
    ),
    suspiciousVelocityThresholds: {
        windowSeconds: parseInteger(
            process.env.COIN_TRANSFER_SUSPICIOUS_WINDOW_SECONDS,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.windowSeconds,
            { min: 1 }
        ),
        maxTransfers: parseInteger(
            process.env.COIN_TRANSFER_SUSPICIOUS_MAX_TRANSFERS,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.maxTransfers,
            { min: 1 }
        ),
        maxGrossAmount: parseInteger(
            process.env.COIN_TRANSFER_SUSPICIOUS_MAX_GROSS_AMOUNT,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.maxGrossAmount,
            { min: 1 }
        ),
        circularWindowHours: parseInteger(
            process.env.COIN_TRANSFER_CIRCULAR_WINDOW_HOURS,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.circularWindowHours,
            { min: 1 }
        ),
        circularTransferCount: parseInteger(
            process.env.COIN_TRANSFER_CIRCULAR_TRANSFER_COUNT,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.circularTransferCount,
            { min: 1 }
        ),
        circularGrossAmount: parseInteger(
            process.env.COIN_TRANSFER_CIRCULAR_GROSS_AMOUNT,
            DEFAULT_COIN_TRANSFER_CONFIG.suspiciousVelocityThresholds.circularGrossAmount,
            { min: 1 }
        )
    },
    allowMockUnlockPurchases: parseBoolean(
        process.env.COIN_TRANSFER_ALLOW_MOCK_UNLOCK_PURCHASES,
        DEFAULT_COIN_TRANSFER_CONFIG.allowMockUnlockPurchases
    )
});

const validateCoinTransferConfig = (config) => {
    const validated = mergeObjects(DEFAULT_COIN_TRANSFER_CONFIG, config || {});

    if (
        Number(validated.receiverPercentage || 0) +
        Number(validated.platformPercentage || 0) !==
        100
    ) {
        throw new Error('Coin transfer percentages must total 100');
    }

    if (validated.minTransferAmount < 1) {
        throw new Error('Coin transfer minTransferAmount must be at least 1');
    }

    if (validated.maxTransferPerTxn < validated.minTransferAmount) {
        throw new Error('Coin transfer maxTransferPerTxn must be >= minTransferAmount');
    }

    return validated;
};

const getCoinTransferConfig = () => validateCoinTransferConfig(
    mergeObjects(
        mergeObjects(DEFAULT_COIN_TRANSFER_CONFIG, buildEnvConfig()),
        runtimeOverrides
    )
);

const buildPublicCoinTransferConfig = () => {
    const config = getCoinTransferConfig();
    return {
        featureEnabled: config.featureEnabled,
        unlockPriceInr: config.unlockPriceInr,
        unlockCurrency: config.unlockCurrency,
        minTransferAmount: config.minTransferAmount,
        maxTransferPerTxn: config.maxTransferPerTxn,
        dailySendLimitAmount: config.dailySendLimitAmount,
        dailySendLimitCount: config.dailySendLimitCount,
        monthlySendLimitAmount: config.monthlySendLimitAmount,
        monthlySendLimitCount: config.monthlySendLimitCount,
        cooldownSecondsBetweenTransfers: config.cooldownSecondsBetweenTransfers,
        maxUniqueReceiversPerDay: config.maxUniqueReceiversPerDay,
        maxReceivedFromSameSenderPerDay: config.maxReceivedFromSameSenderPerDay,
        accountAgeMinDaysForTransfer: config.accountAgeMinDaysForTransfer,
        minFriendshipAgeHours: config.minFriendshipAgeHours,
        minChatMessagesExchanged: config.minChatMessagesExchanged,
        requireVerifiedAccount: config.requireVerifiedAccount,
        feePercentages: {
            receiverPercentage: config.receiverPercentage,
            platformPercentage: config.platformPercentage
        }
    };
};

const setCoinTransferConfigForTests = (overrides = {}) => {
    runtimeOverrides = mergeObjects({}, overrides);
};

const clearCoinTransferConfigForTests = () => {
    runtimeOverrides = {};
};

module.exports = {
    DEFAULT_COIN_TRANSFER_CONFIG,
    buildPublicCoinTransferConfig,
    clearCoinTransferConfigForTests,
    getCoinTransferConfig,
    setCoinTransferConfigForTests,
    validateCoinTransferConfig
};
