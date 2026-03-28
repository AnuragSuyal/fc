const User = require('../models/User');

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

    const scaledXp = Math.floor(safeCoins / 20) + (safeGems * 2);

    return Math.max(safeBaseXp, scaledXp, 1);
};

const awardSpendXp = async ({ user, userId, coins = 0, gems = 0, baseXp = 0 } = {}) => {
    const targetUser = user || (userId ? await User.findById(userId) : null);

    if (!targetUser) {
        return null;
    }

    const xpGained = calculateSpendXp({ coins, gems, baseXp });

    if (xpGained <= 0) {
        return {
            user: targetUser,
            xpGained: 0,
            leveledUp: false
        };
    }

    const leveledUp = await targetUser.addXP(xpGained);
    await targetUser.save();

    return {
        user: targetUser,
        xpGained,
        leveledUp
    };
};

const buildProgressPayload = (user, extra = {}) => ({
    coins: Number(user?.coins || 0),
    gems: Number(user?.gems || 0),
    xp: Number(user?.xp || 0),
    level: Number(user?.level || 1),
    vipLevel: Number(user?.vipLevel || 0),
    ...extra
});

module.exports = {
    calculateSpendXp,
    awardSpendXp,
    buildProgressPayload
};
