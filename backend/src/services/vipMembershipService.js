const {
    VIP_COMPARISON_ROWS,
    VIP_MEMBERSHIP_TIERS,
    VIP_PLAN_DEFINITIONS,
    VIP_TIER_BY_ID,
    VIP_TIER_BY_LEVEL,
    VIP_TIER_ORDER
} = require('../config/vipMembershipConfig');

const DAY_MS = 24 * 60 * 60 * 1000;
const REWARD_CYCLE_MS = 30 * DAY_MS;

const FREE_TIER = {
    tierId: 'free',
    level: 0,
    displayOrder: 0,
    displayName: 'Free',
    shortLabel: 'Free',
    badgeAsset: '',
    nameColorStyle: {
        token: 'default',
        label: 'Default',
        colors: ['#CBD5E1', '#64748B']
    },
    frameAsset: '',
    xpBoostPercent: 0,
    monthlyCoinReward: 0,
    giftingPerkLevel: 0,
    roomEntryEffect: '',
    premiumEffects: [],
    featureFlags: {},
    newlyUnlockedBenefits: [],
    pricing: {},
    ui: {
        accent: '#94A3B8',
        gradient: ['#111827', '#334155'],
        glow: '#94A3B8'
    }
};

const safeDate = (value) => {
    if (!value) return null;
    const date = value instanceof Date ? value : new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
};

const getNestedValue = (object, path) => path
    .split('.')
    .reduce((current, key) => (current == null ? undefined : current[key]), object);

const normalizeVipTierId = (value) => {
    if (value == null) return '';

    if (typeof value === 'number' || /^\d+$/.test(String(value).trim())) {
        const tier = VIP_TIER_BY_LEVEL[Number(value)];
        return tier?.tierId || '';
    }

    const normalized = String(value).trim().toLowerCase();
    if (VIP_TIER_BY_ID[normalized]) return normalized;

    if (/^vip[_\s-]?(\d{1,2})$/.test(normalized)) {
        const match = normalized.match(/^vip[_\s-]?(\d{1,2})$/);
        const level = Number(match?.[1] || 0);
        return VIP_TIER_BY_LEVEL[level]?.tierId || '';
    }

    return '';
};

const getVipTierConfig = (tierIdOrLevel) => {
    const normalizedTierId = normalizeVipTierId(tierIdOrLevel);
    return VIP_TIER_BY_ID[normalizedTierId] || null;
};

const getVipPlanConfig = (planDuration) => {
    const normalized = String(planDuration || 'monthly').trim().toLowerCase();
    return VIP_PLAN_DEFINITIONS[normalized] || VIP_PLAN_DEFINITIONS.monthly;
};

const compareVipTierIds = (left, right) => {
    const leftIndex = VIP_TIER_ORDER.indexOf(normalizeVipTierId(left));
    const rightIndex = VIP_TIER_ORDER.indexOf(normalizeVipTierId(right));
    return leftIndex - rightIndex;
};

const isHigherVipTier = (candidate, current) => compareVipTierIds(candidate, current) > 0;

const serializeBenefit = (benefit) => ({
    id: benefit.id,
    category: benefit.category,
    title: benefit.title,
    description: benefit.description
});

const buildTierPlans = (tier) => Object.values(VIP_PLAN_DEFINITIONS).map((plan) => {
    const pricing = tier.pricing?.[plan.planDuration] || {};
    return {
        planDuration: plan.planDuration,
        label: plan.label,
        durationDays: pricing.durationDays || plan.durationDays,
        priceCoins: Number(pricing.coins || 0),
        savingsPercent: Number(pricing.savingsPercent || plan.savingsPercent || 0),
        recommendedTag: plan.planDuration === 'yearly'
            ? 'Best Value'
            : plan.planDuration === 'quarterly'
                ? 'Most Popular'
                : 'Flexible'
    };
});

const buildCumulativeBenefits = (tierId) => {
    const normalized = normalizeVipTierId(tierId);
    if (!normalized) return [];

    const tierIndex = VIP_TIER_ORDER.indexOf(normalized);
    if (tierIndex < 0) return [];

    const benefits = [];
    for (let index = 0; index <= tierIndex; index += 1) {
        const tier = VIP_TIER_BY_ID[VIP_TIER_ORDER[index]];
        if (!tier) continue;

        for (const benefit of tier.newlyUnlockedBenefits || []) {
            if (!benefits.some((item) => item.id === benefit.id)) {
                benefits.push(serializeBenefit(benefit));
            }
        }
    }

    return benefits;
};

const serializeVipTier = (tier, { currentTierId = '', selectedTierId = '' } = {}) => {
    const current = normalizeVipTierId(currentTierId);
    const selected = normalizeVipTierId(selectedTierId);
    const isCurrent = !!current && tier.tierId === current;
    const isSelected = !!selected && tier.tierId === selected;

    return {
        tierId: tier.tierId,
        level: tier.level,
        displayOrder: tier.displayOrder,
        displayName: tier.displayName,
        shortLabel: tier.shortLabel,
        badgeAsset: tier.badgeAsset,
        nameColorStyle: tier.nameColorStyle,
        frameAsset: tier.frameAsset,
        xpBoostPercent: tier.xpBoostPercent,
        monthlyCoinReward: tier.monthlyCoinReward,
        giftingPerkLevel: tier.giftingPerkLevel,
        roomEntryEffect: tier.roomEntryEffect,
        premiumEffects: [...(tier.premiumEffects || [])],
        featureFlags: { ...(tier.featureFlags || {}) },
        newlyUnlockedBenefits: (tier.newlyUnlockedBenefits || []).map(serializeBenefit),
        cumulativeBenefits: buildCumulativeBenefits(tier.tierId),
        includedTierIds: VIP_TIER_ORDER.slice(0, VIP_TIER_ORDER.indexOf(tier.tierId) + 1),
        planOptions: buildTierPlans(tier),
        ui: tier.ui,
        isCurrent,
        isSelected,
        upgradeState: !current
            ? 'unlock'
            : isCurrent
                ? 'current'
                : isHigherVipTier(tier.tierId, current)
                    ? 'upgrade'
                    : 'locked_lower'
    };
};

const buildComparisonMatrix = () => ({
    rows: VIP_COMPARISON_ROWS.map((row) => ({
        key: row.key,
        label: row.label,
        type: row.type,
        values: VIP_MEMBERSHIP_TIERS.map((tier) => ({
            tierId: tier.tierId,
            value: getNestedValue(tier, row.key)
        }))
    }))
});

const resolveMonthlyRewardState = ({
    startAt,
    lastClaimedAt,
    active,
    now = new Date()
}) => {
    const safeStart = safeDate(startAt);
    const safeLastClaimedAt = safeDate(lastClaimedAt);
    if (!active || !safeStart) {
        return {
            eligible: false,
            currentCycle: -1,
            lastClaimedCycle: -1,
            nextEligibleAt: null
        };
    }

    const currentCycle = Math.max(0, Math.floor((now.getTime() - safeStart.getTime()) / REWARD_CYCLE_MS));
    const lastClaimedCycle = safeLastClaimedAt
        ? Math.max(0, Math.floor((safeLastClaimedAt.getTime() - safeStart.getTime()) / REWARD_CYCLE_MS))
        : -1;
    const eligible = lastClaimedCycle < currentCycle;

    return {
        eligible,
        currentCycle,
        lastClaimedCycle,
        nextEligibleAt: eligible
            ? now
            : new Date(safeStart.getTime() + ((lastClaimedCycle + 1) * REWARD_CYCLE_MS))
    };
};

const syncVipMembershipState = (user, { now = new Date() } = {}) => {
    if (!user) {
        return {
            active: false,
            tier: null,
            status: 'inactive'
        };
    }

    const normalizedTierId = normalizeVipTierId(user.vipTier || user.vipLevel);
    const tier = getVipTierConfig(normalizedTierId);
    const expireAt = safeDate(user.vipExpireAt || user.vipExpiry);
    const startAt = safeDate(user.vipStartAt || user.vipPurchasedAt);
    const active = !!tier && !!expireAt && expireAt > now;
    const status = active
        ? 'active'
        : tier
            ? 'expired'
            : 'inactive';

    user.vipTier = normalizedTierId || '';
    user.vipStatus = status;
    user.vipExpireAt = expireAt;
    user.vipExpiry = expireAt;
    user.vipStartAt = startAt;
    user.vipPurchasedAt = startAt;
    user.vipLevel = active ? Number(tier.level || 0) : 0;
    user.vipPlanDuration = user.vipPlanDuration || 'monthly';
    user.vipPurchaseSource = user.vipPurchaseSource || (active ? 'coins' : '');
    user.vipAutoRenew = active ? user.vipAutoRenew === true : false;
    user.vipLastUpdatedAt = now;

    return {
        active,
        tier,
        status,
        expireAt,
        startAt
    };
};

const buildVipMembershipSnapshot = (user, { now = new Date(), selectedTierId = '' } = {}) => {
    const synced = syncVipMembershipState(user, { now });
    const activeTier = synced.active ? synced.tier : null;
    const currentTier = synced.tier || FREE_TIER;
    const rewardState = resolveMonthlyRewardState({
        startAt: user?.vipStartAt,
        lastClaimedAt: user?.monthlyRewardLastClaimedAt,
        active: synced.active,
        now
    });

    return {
        activeTierId: activeTier?.tierId || '',
        currentTierId: currentTier.tierId,
        currentTierLevel: currentTier.level,
        status: synced.status,
        isActive: synced.active,
        vipLevel: synced.active ? Number(activeTier?.level || 0) : 0,
        vipStartAt: user?.vipStartAt ? new Date(user.vipStartAt).toISOString() : null,
        vipExpireAt: user?.vipExpireAt ? new Date(user.vipExpireAt).toISOString() : null,
        autoRenew: user?.vipAutoRenew === true,
        planDuration: String(user?.vipPlanDuration || 'monthly'),
        purchaseSource: String(user?.vipPurchaseSource || ''),
        monthlyRewardLastClaimedAt: user?.monthlyRewardLastClaimedAt
            ? new Date(user.monthlyRewardLastClaimedAt).toISOString()
            : null,
        daysRemaining: synced.active && synced.expireAt
            ? Math.max(0, Math.ceil((synced.expireAt.getTime() - now.getTime()) / DAY_MS))
            : 0,
        secondsRemaining: synced.active && synced.expireAt
            ? Math.max(0, Math.floor((synced.expireAt.getTime() - now.getTime()) / 1000))
            : 0,
        currentTier: serializeVipTier(currentTier, {
            currentTierId: activeTier?.tierId,
            selectedTierId
        }),
        activeTier: activeTier
            ? serializeVipTier(activeTier, {
                currentTierId: activeTier.tierId,
                selectedTierId
            })
            : null,
        canClaimMonthlyReward: rewardState.eligible && synced.active,
        monthlyRewardAmount: Number(activeTier?.monthlyCoinReward || 0),
        nextRewardAt: rewardState.nextEligibleAt
            ? rewardState.nextEligibleAt.toISOString()
            : null
    };
};

const calculateVipUpgradeCredit = ({
    currentTierId,
    currentPlanDuration,
    currentExpireAt,
    now = new Date()
}) => {
    const tier = getVipTierConfig(currentTierId);
    const plan = getVipPlanConfig(currentPlanDuration);
    const expireAt = safeDate(currentExpireAt);
    if (!tier || !expireAt || expireAt <= now) {
        return 0;
    }

    const pricing = tier.pricing?.[plan.planDuration];
    if (!pricing?.coins) {
        return 0;
    }

    const totalMs = Number(pricing.durationDays || plan.durationDays || 30) * DAY_MS;
    const remainingMs = Math.max(0, expireAt.getTime() - now.getTime());
    if (remainingMs <= 0 || totalMs <= 0) {
        return 0;
    }

    return Math.max(0, Math.round(Number(pricing.coins) * (remainingMs / totalMs)));
};

const buildVipCatalog = ({ currentTierId = '', selectedTierId = '' } = {}) => ({
    tiers: VIP_MEMBERSHIP_TIERS.map((tier) => serializeVipTier(tier, { currentTierId, selectedTierId })),
    comparison: buildComparisonMatrix(),
    planDefinitions: Object.values(VIP_PLAN_DEFINITIONS)
});

module.exports = {
    FREE_TIER,
    buildComparisonMatrix,
    buildCumulativeBenefits,
    buildVipCatalog,
    buildVipMembershipSnapshot,
    calculateVipUpgradeCredit,
    compareVipTierIds,
    getVipPlanConfig,
    getVipTierConfig,
    isHigherVipTier,
    normalizeVipTierId,
    resolveMonthlyRewardState,
    serializeVipTier,
    syncVipMembershipState
};
