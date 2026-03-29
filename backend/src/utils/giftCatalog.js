const GIFT_CATALOG_VERSION = '2026-03-29-premium-refresh';

const GIFT_CATEGORY_ORDER = ['simple', 'premium', 'luxury', 'limited'];

const CATEGORY_META = {
    simple: {
        tier: 1,
        rarity: 'simple',
        animationType: 'float',
        animationDuration: 3,
        animationColor: '#FFCF63',
        particleCount: 18,
        description: 'A polished everyday gift for live rooms.'
    },
    premium: {
        tier: 2,
        rarity: 'premium',
        animationType: 'explode',
        animationDuration: 4,
        animationColor: '#7ED7FF',
        particleCount: 34,
        description: 'A richer gift with elevated room presence.'
    },
    luxury: {
        tier: 3,
        rarity: 'luxury',
        animationType: 'screen',
        animationDuration: 5,
        animationColor: '#FF8FD9',
        particleCount: 56,
        description: 'A luxury collectible designed to stand out.'
    },
    limited: {
        tier: 4,
        rarity: 'limited',
        animationType: 'screen',
        animationDuration: 6,
        animationColor: '#FFD56A',
        particleCount: 80,
        description: 'A limited release gift reserved for special moments.'
    }
};

const GIFT_DEFINITIONS = {
    simple: [
        ['simple_microphone', 'Microphone', 40],
        ['simple_rose', 'Rose', 30],
        ['simple_heart_duo', 'Heart Duo', 50],
        ['simple_applause', 'Applause', 60],
        ['simple_tea_cup', 'Tea Cup', 20],
        ['simple_gift_box', 'Gift Box', 80],
        ['simple_campfire', 'Campfire', 100],
        ['simple_birthday_cake', 'Birthday Cake', 120],
        ['simple_cheers', 'Cheers', 60],
        ['simple_diamond', 'Diamond', 150],
        ['simple_magic_hand', 'Magic Hand', 80],
        ['simple_angel_wings', 'Angel Wings', 100],
        ['simple_lucky_cat', 'Lucky Cat', 120],
        ['simple_rocket', 'Rocket', 150],
        ['simple_unicorn', 'Unicorn', 150]
    ],
    premium: [
        ['premium_sweet_bowl', 'Sweet Bowl', 180],
        ['premium_moon_pearl', 'Moon Pearl', 220],
        ['premium_royal_crown', 'Royal Crown', 260],
        ['premium_pizza_slice', 'Pizza Slice', 220],
        ['premium_teddy_love', 'Teddy Love', 300],
        ['premium_love_phone', 'Love Phone', 350],
        ['premium_crystal_ball', 'Crystal Ball', 400],
        ['premium_butterfly', 'Butterfly', 260],
        ['premium_sports_car', 'Sports Car', 500],
        ['premium_treasure_chest', 'Treasure Chest', 600],
        ['premium_wing_trophy', 'Wing Trophy', 500],
        ['premium_cash_stack', 'Cash Stack', 600],
        ['premium_star_spark', 'Star Spark', 350],
        ['premium_love_letters', 'Love Letters', 300],
        ['premium_heart_cake', 'Heart Cake', 400]
    ],
    luxury: [
        ['luxury_heart_balloons', 'Heart Balloons', 700],
        ['luxury_golden_scroll', 'Golden Scroll', 850],
        ['luxury_dream_moon', 'Dream Moon', 1000],
        ['luxury_twin_hearts', 'Twin Hearts', 1200],
        ['luxury_rainbow', 'Rainbow', 1000],
        ['luxury_magic_potion', 'Magic Potion', 1200],
        ['luxury_cherry_pair', 'Cherry Pair', 850],
        ['luxury_duck_duo', 'Duck Duo', 850],
        ['luxury_flower_gift', 'Flower Gift', 1500],
        ['luxury_flame_torches', 'Flame Torches', 1800],
        ['luxury_pink_elixir', 'Pink Elixir', 1500],
        ['luxury_royal_bomb', 'Royal Bomb', 2200],
        ['luxury_fortune_booth', 'Fortune Booth', 1800],
        ['luxury_celebration_chest', 'Celebration Chest', 2200],
        ['luxury_cupid_cart', 'Cupid Cart', 2200]
    ],
    limited: [
        ['limited_sweet_bag', 'Sweet Bag', 2500],
        ['limited_party_bag', 'Party Bag', 3000],
        ['limited_celebration_cake', 'Celebration Cake', 4000],
        ['limited_festival_gift', 'Festival Gift', 5000],
        ['limited_baby_unicorn', 'Baby Unicorn', 7000],
        ['limited_rainbow_arc', 'Rainbow Arc', 5000],
        ['limited_candy_bowl', 'Candy Bowl', 3000],
        ['limited_silver_medal', 'Silver Medal', 2500],
        ['limited_confetti_ball', 'Confetti Ball', 4000]
    ]
};

const buildGiftDefinition = ({
    category,
    giftId,
    name,
    price,
    sortOrder
}) => {
    const meta = CATEGORY_META[category];
    const assetPath = `assets/gifts/${giftId}.png`;
    const xpReward = Math.max(6, Math.round(price / 12));

    return {
        giftId,
        catalogVersion: GIFT_CATALOG_VERSION,
        name,
        description: meta.description,
        icon: assetPath,
        assetPath,
        price: {
            coins: price,
            gems: 0
        },
        category,
        tier: meta.tier,
        rarity: meta.rarity,
        sortOrder,
        animation: {
            type: meta.animationType,
            duration: meta.animationDuration,
            color: meta.animationColor,
            particleCount: meta.particleCount,
            scale: 1
        },
        effects: {
            sender: {
                xp: xpReward
            },
            recipient: {
                effect: `${giftId}_shine`,
                duration: meta.animationDuration,
                xp: xpReward
            }
        },
        availability: {
            limited: category === 'limited',
            totalAvailable: 0,
            sold: 0
        },
        requirements: {
            minLevel: 0,
            requiredVip: 0
        },
        active: true
    };
};

let sortOrder = 0;
const ACTIVE_GIFT_CATALOG = GIFT_CATEGORY_ORDER.flatMap((category) =>
    GIFT_DEFINITIONS[category].map(([giftId, name, price]) => {
        sortOrder += 1;
        return buildGiftDefinition({
            category,
            giftId,
            name,
            price,
            sortOrder
        });
    })
);

const ACTIVE_GIFT_IDS = ACTIVE_GIFT_CATALOG.map((gift) => gift.giftId);

const normalizeGiftCategory = (category) => {
    if (category === 'legendary') return 'limited';
    return category;
};

const buildGiftLookupQuery = (identifier) => {
    const trimmed = typeof identifier === 'string' ? identifier.trim() : '';
    if (!trimmed) return null;

    const orConditions = [{ giftId: trimmed }];
    if (/^[0-9a-fA-F]{24}$/.test(trimmed)) {
        orConditions.push({ _id: trimmed });
    }

    return { $or: orConditions };
};

const serializeGift = (giftDoc) => {
    if (!giftDoc) return null;

    const raw = typeof giftDoc.toObject === 'function'
        ? giftDoc.toObject({ virtuals: true })
        : { ...giftDoc };

    const normalizedCategory = normalizeGiftCategory(raw.category);
    const assetPath = raw.assetPath || raw.icon || '';
    const isLimited = raw.isLimited === true || raw.availability?.limited === true;
    const isActive = raw.isActive === true || raw.active !== false;

    return {
        ...raw,
        _id: raw._id?.toString?.() || raw._id,
        id: raw.giftId || raw._id?.toString?.() || raw._id || '',
        giftId: raw.giftId || raw._id?.toString?.() || raw._id || '',
        icon: assetPath,
        assetPath,
        category: normalizedCategory,
        rarity: raw.rarity || normalizedCategory,
        sortOrder: Number(raw.sortOrder || 0),
        isLimited,
        isActive,
        availability: {
            ...(raw.availability || {}),
            limited: isLimited
        },
        active: isActive
    };
};

const buildCategorizedGiftResponse = (gifts) => {
    const serialized = gifts.map(serializeGift);
    return GIFT_CATEGORY_ORDER.reduce((accumulator, category) => {
        accumulator[category] = serialized.filter((gift) => gift.category === category);
        return accumulator;
    }, {});
};

module.exports = {
    ACTIVE_GIFT_CATALOG,
    ACTIVE_GIFT_IDS,
    GIFT_CATALOG_VERSION,
    GIFT_CATEGORY_ORDER,
    buildCategorizedGiftResponse,
    buildGiftLookupQuery,
    normalizeGiftCategory,
    serializeGift
};
