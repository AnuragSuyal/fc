const { SPEND_XP_CONFIG } = require('../config/leveling');
const {
    awardUserXp,
    buildProgressPayload
} = require('./levelProgressionService');

const normalizeAmount = (value) => {
    const amount = Number(value);
    if (!Number.isFinite(amount) || amount <= 0) {
        return 0;
    }

    return Math.floor(amount);
};

const calculateSpendXp = ({ coins = 0, gems = 0, baseXp = 0 } = {}) => {
    const safeCoins = normalizeAmount(coins);
    const safeGems = normalizeAmount(gems);
    const safeBaseXp = normalizeAmount(baseXp);

    if (safeCoins === 0 && safeGems === 0 && safeBaseXp === 0) {
        return 0;
    }

    const scaledXp = Math.floor(safeCoins / SPEND_XP_CONFIG.coinsPerXp)
        + (safeGems * SPEND_XP_CONFIG.gemsPerXp);

    return Math.min(
        Math.max(safeBaseXp, scaledXp, SPEND_XP_CONFIG.minimumAward),
        SPEND_XP_CONFIG.maximumAward
    );
};

const awardSpendXp = async ({
    user,
    userId,
    coins = 0,
    gems = 0,
    baseXp = 0,
    sourceType = 'gift_received',
    sourceReferenceId = '',
    sourceReferenceType = '',
    dedupeKey = '',
    metadata = {},
    redis
} = {}) => {
    const xpGained = calculateSpendXp({ coins, gems, baseXp });

    if (xpGained <= 0) {
        return {
            user: user || null,
            xpGained: 0,
            leveledUp: false
        };
    }

    return awardUserXp({
        user,
        userId,
        amount: xpGained,
        sourceType,
        sourceReferenceId,
        sourceReferenceType,
        dedupeKey,
        metadata: {
            ...metadata,
            coins: normalizeAmount(coins),
            gems: normalizeAmount(gems),
            baseXp: normalizeAmount(baseXp)
        },
        redis
    });
};

module.exports = {
    calculateSpendXp,
    awardSpendXp,
    buildProgressPayload
};
