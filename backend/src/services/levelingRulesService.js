const {
    LEVELING_CONFIG,
    LEVEL_BADGE_TIERS
} = require('../config/leveling');

const clampNumber = (value, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) => {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) {
        return min;
    }
    return Math.min(Math.max(numeric, min), max);
};

const normalizeXp = (value) => Math.floor(clampNumber(value, { min: 0 }));

const normalizeLevel = (value) => Math.floor(
    clampNumber(value, { min: 1, max: LEVELING_CONFIG.maxLevel })
);

const xpForLevel = (level) => {
    const safeLevel = normalizeLevel(level);
    return Math.pow(safeLevel - 1, 2) * LEVELING_CONFIG.xpScale;
};

const getLevelFromXp = (xp) => {
    const safeXp = normalizeXp(xp);
    const derivedLevel = Math.floor(
        Math.sqrt(safeXp / LEVELING_CONFIG.xpScale)
    ) + 1;
    return normalizeLevel(derivedLevel);
};

const resolveBadgeTier = (level) => {
    const safeLevel = normalizeLevel(level);
    return LEVEL_BADGE_TIERS.find((tier) => safeLevel >= tier.minLevel)
        || LEVEL_BADGE_TIERS[LEVEL_BADGE_TIERS.length - 1];
};

const getNextBadgeTier = (level) => {
    const safeLevel = normalizeLevel(level);
    const orderedAscending = [...LEVEL_BADGE_TIERS]
        .sort((left, right) => left.minLevel - right.minLevel);
    return orderedAscending.find((tier) => tier.minLevel > safeLevel) || null;
};

const buildLevelSnapshot = ({
    xp = 0,
    level = null,
    lastLevelUpdatedAt = null
} = {}) => {
    const safeXp = normalizeXp(xp);
    const safeLevel = level == null
        ? getLevelFromXp(safeXp)
        : normalizeLevel(level);
    const levelFloorXp = xpForLevel(safeLevel);
    const nextLevel = Math.min(safeLevel + 1, LEVELING_CONFIG.maxLevel);
    const nextLevelXp = safeLevel >= LEVELING_CONFIG.maxLevel
        ? null
        : xpForLevel(nextLevel);
    const xpIntoLevel = Math.max(0, safeXp - levelFloorXp);
    const xpToNextLevel = nextLevelXp == null
        ? 0
        : Math.max(0, nextLevelXp - safeXp);
    const progressDenominator = nextLevelXp == null
        ? 0
        : Math.max(1, nextLevelXp - levelFloorXp);
    const progress = nextLevelXp == null
        ? 1
        : Number((xpIntoLevel / progressDenominator).toFixed(4));
    const milestoneTier = resolveBadgeTier(safeLevel);
    const nextMilestone = getNextBadgeTier(safeLevel);

    return {
        level: safeLevel,
        xp: safeXp,
        currentLevelXp: levelFloorXp,
        nextLevelXp,
        xpIntoLevel,
        xpToNextLevel,
        progress,
        progressPercent: Number((progress * 100).toFixed(2)),
        milestoneTier: milestoneTier.key,
        milestoneLabel: milestoneTier.label,
        milestoneStartLevel: milestoneTier.minLevel,
        nextMilestoneLevel: nextMilestone?.minLevel || null,
        lastLevelUpdatedAt: lastLevelUpdatedAt
            ? new Date(lastLevelUpdatedAt).toISOString()
            : null
    };
};

const ensureXpStatsShape = (xpStats = {}) => ({
    totalAwarded: Math.max(Number(xpStats.totalAwarded || 0), 0),
    totalAwards: Math.max(Number(xpStats.totalAwards || 0), 0),
    roomXp: Math.max(Number(xpStats.roomXp || 0), 0),
    socialXp: Math.max(Number(xpStats.socialXp || 0), 0),
    rewardXp: Math.max(Number(xpStats.rewardXp || 0), 0),
    profileXp: Math.max(Number(xpStats.profileXp || 0), 0),
    premiumXp: Math.max(Number(xpStats.premiumXp || 0), 0),
    lastAwardedAt: xpStats.lastAwardedAt || null,
    lastSourceType: xpStats.lastSourceType || '',
    lastAwardAmount: Math.max(Number(xpStats.lastAwardAmount || 0), 0)
});

const applyXpCategoryAward = (xpStats = {}, category, amount) => {
    const nextStats = ensureXpStatsShape(xpStats);
    const safeAmount = normalizeXp(amount);

    switch (category) {
        case 'room':
            nextStats.roomXp += safeAmount;
            break;
        case 'social':
            nextStats.socialXp += safeAmount;
            break;
        case 'reward':
            nextStats.rewardXp += safeAmount;
            break;
        case 'profile':
            nextStats.profileXp += safeAmount;
            break;
        case 'premium':
            nextStats.premiumXp += safeAmount;
            break;
        default:
            break;
    }

    return nextStats;
};

const syncUserLevelState = (user) => {
    if (!user) return buildLevelSnapshot({});

    const previousLevel = normalizeLevel(user.level || 1);
    const previousTier = resolveBadgeTier(previousLevel).key;

    user.xp = normalizeXp(user.xp);

    const nextSnapshot = buildLevelSnapshot({
        xp: user.xp,
        level: null,
        lastLevelUpdatedAt: user.lastLevelUpdatedAt
    });

    user.level = nextSnapshot.level;
    user.levelMilestoneTier = nextSnapshot.milestoneTier;
    user.levelMilestoneLevel = nextSnapshot.milestoneStartLevel;

    if (!user.lastLevelUpdatedAt || nextSnapshot.level > previousLevel) {
        user.lastLevelUpdatedAt = new Date();
    }

    user.xpStats = ensureXpStatsShape(user.xpStats);

    return {
        previousLevel,
        newLevel: nextSnapshot.level,
        previousTier,
        newTier: nextSnapshot.milestoneTier,
        leveledUp: nextSnapshot.level > previousLevel,
        tierChanged: nextSnapshot.milestoneTier !== previousTier,
        snapshot: buildLevelSnapshot({
            xp: user.xp,
            level: user.level,
            lastLevelUpdatedAt: user.lastLevelUpdatedAt
        })
    };
};

const buildLevelFields = (user) => {
    const snapshot = buildLevelSnapshot({
        xp: user?.xp,
        level: user?.level,
        lastLevelUpdatedAt: user?.lastLevelUpdatedAt
    });

    return {
        level: snapshot.level,
        xp: snapshot.xp,
        nextLevelXp: snapshot.nextLevelXp,
        xpProgress: snapshot.progress,
        levelMilestoneTier: snapshot.milestoneTier,
        lastLevelUpdatedAt: snapshot.lastLevelUpdatedAt,
        levelInfo: snapshot
    };
};

module.exports = {
    applyXpCategoryAward,
    buildLevelFields,
    buildLevelSnapshot,
    ensureXpStatsShape,
    getLevelFromXp,
    normalizeLevel,
    normalizeXp,
    resolveBadgeTier,
    syncUserLevelState,
    xpForLevel
};
