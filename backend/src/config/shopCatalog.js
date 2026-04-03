const currentYear = new Date().getUTCFullYear();

const buildDateUtc = (year, month, day, hour = 0, minute = 0, second = 0) =>
    new Date(Date.UTC(year, month - 1, day, hour, minute, second));

const hours = (value) => value * 60 * 60;

const SHOP_CATEGORIES = Object.freeze([
    { id: 'all', name: 'All', description: 'Everything playful, premium, and account-bound.' },
    { id: 'profile_cosmetics', name: 'Profile', description: 'Frames, glows, borders, and prestige touches.' },
    { id: 'room_entry_effects', name: 'Entry', description: 'Join a room with style.' },
    { id: 'room_interaction_effects', name: 'Voice', description: 'Mic aura, speaking glow, and room vibe cosmetics.' },
    { id: 'chat_cosmetics', name: 'Chat', description: 'Bubble skins, stickers, and reaction packs.' },
    { id: 'identity_cosmetics', name: 'Identity', description: 'Nameplates, user card skins, and popup themes.' },
    { id: 'boosters', name: 'Boosters', description: 'XP, visibility, and spotlight boosts.' },
    { id: 'utilities', name: 'Utilities', description: 'Tickets and passes for future room moments.' },
    { id: 'collectibles', name: 'Collectibles', description: 'Capsules, artifacts, and decorative keepsakes.' },
    { id: 'seasonal', name: 'Seasonal', description: 'Limited-time festival cosmetics and themed rewards.' },
    { id: 'bundles', name: 'Bundles', description: 'Curated packs with better value and stronger identity.' }
]);

const SHOP_RARITIES = Object.freeze(['common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic']);

const SHOP_COLLECTION_SETS = Object.freeze([
    { collectionSetId: 'galaxy_set', name: 'Galaxy Set', description: 'Cosmic purple-blue identity pieces.' },
    { collectionSetId: 'royal_set', name: 'Royal Set', description: 'Regal gold-red prestige cosmetics.' },
    { collectionSetId: 'love_set', name: 'Love Set', description: 'Soft pink and heart-forward playful identity.' },
    { collectionSetId: 'diamond_set', name: 'Diamond Set', description: 'Crystal-clear elite cosmetics.' },
    { collectionSetId: 'party_set', name: 'Party Set', description: 'Confetti, pop, and lively room energy.' },
    { collectionSetId: 'supreme_set', name: 'Supreme Set', description: 'Highest-tier orbit, aura, and arrival cosmetics.' }
]);

const createItem = (overrides) => ({
    itemDescription: '',
    imageAsset: '',
    previewAsset: '',
    tags: [],
    isConsumable: false,
    isEquippable: false,
    isTemporary: false,
    expiryDurationSeconds: 0,
    isStackable: false,
    activationRequired: false,
    oneActivePerCategory: false,
    bundleOnly: false,
    limitedEdition: false,
    stockCount: 0,
    releaseStartAt: buildDateUtc(currentYear - 1, 1, 1),
    releaseEndAt: buildDateUtc(currentYear + 2, 12, 31, 23, 59, 59),
    isFeatured: false,
    isPopular: false,
    isDailyDealEligible: true,
    discountPercent: 0,
    bundleContents: [],
    collectionSetId: '',
    featureFlags: {},
    previewStyle: {},
    equipSlot: '',
    purchaseLimit: 0,
    isActive: true,
    ...overrides
});

const equippableItem = (overrides) => createItem({
    itemType: 'permanent_cosmetic',
    isEquippable: true,
    oneActivePerCategory: true,
    ...overrides
});

const temporaryEquippableItem = (overrides) => createItem({
    itemType: 'temporary_cosmetic',
    isEquippable: true,
    isTemporary: true,
    oneActivePerCategory: true,
    ...overrides
});

const boosterItem = (overrides) => createItem({
    itemCategory: 'boosters',
    itemType: 'booster',
    isConsumable: true,
    isStackable: true,
    activationRequired: true,
    ...overrides
});

const utilityItem = (overrides) => createItem({
    itemCategory: 'utilities',
    itemType: 'utility_token',
    isStackable: true,
    ...overrides
});

const collectibleItem = (overrides) => createItem({
    itemCategory: 'collectibles',
    itemType: 'collectible',
    isDailyDealEligible: false,
    ...overrides
});

const capsuleItem = (overrides) => createItem({
    itemCategory: 'collectibles',
    itemType: 'capsule',
    isConsumable: true,
    isStackable: true,
    activationRequired: true,
    isDailyDealEligible: false,
    ...overrides
});

const bundleItem = (overrides) => createItem({
    itemCategory: 'bundles',
    itemType: 'bundle',
    isDailyDealEligible: false,
    ...overrides
});

const permanentUnlockItem = (overrides) => createItem({
    itemType: 'permanent_unlock',
    ...overrides
});

const SHOP_CATALOG = Object.freeze([
    equippableItem({
        itemId: 'frame_neon',
        itemName: 'Neon Frame',
        itemDescription: 'Electric cyan and violet portrait ring for a bright profile entrance.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'rare',
        priceCoins: 650,
        tags: ['NEW'],
        isFeatured: true,
        isPopular: true,
        collectionSetId: 'galaxy_set',
        sortOrder: 100,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'bolt', colors: ['#10E7FF', '#7C4DFF'] }
    }),
    equippableItem({
        itemId: 'frame_royal',
        itemName: 'Royal Frame',
        itemDescription: 'Deep crimson and gold frame built for room royalty.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'epic',
        priceCoins: 920,
        tags: ['HOT'],
        isFeatured: true,
        collectionSetId: 'royal_set',
        sortOrder: 110,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'crown', colors: ['#F59E0B', '#B91C1C'] }
    }),
    equippableItem({
        itemId: 'frame_diamond',
        itemName: 'Diamond Frame',
        itemDescription: 'Clean crystal-blue halo for polished high-tier identity.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'legendary',
        priceCoins: 1380,
        tags: ['POPULAR'],
        isFeatured: true,
        collectionSetId: 'diamond_set',
        sortOrder: 120,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'diamond', colors: ['#E0F2FE', '#38BDF8'] }
    }),
    equippableItem({
        itemId: 'frame_galaxy',
        itemName: 'Galaxy Frame',
        itemDescription: 'Nebula-style profile frame with soft starfield energy.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'epic',
        priceCoins: 1260,
        tags: ['HOT'],
        collectionSetId: 'galaxy_set',
        sortOrder: 130,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'auto_awesome', colors: ['#4F46E5', '#A855F7'] }
    }),
    equippableItem({
        itemId: 'frame_soft_pink',
        itemName: 'Soft Pink Frame',
        itemDescription: 'Sweet blush frame for friendly, lighthearted profiles.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'uncommon',
        priceCoins: 520,
        tags: ['CUTE'],
        collectionSetId: 'love_set',
        sortOrder: 140,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'favorite', colors: ['#F9A8D4', '#FB7185'] }
    }),
    equippableItem({
        itemId: 'frame_flame',
        itemName: 'Flame Frame',
        itemDescription: 'A hot red-orange ring for players who like visible energy.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'epic',
        priceCoins: 870,
        tags: ['HOT'],
        sortOrder: 150,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'local_fire_department', colors: ['#FB923C', '#DC2626'] }
    }),
    equippableItem({
        itemId: 'frame_shadow',
        itemName: 'Shadow Frame',
        itemDescription: 'Dark graphite frame with subtle depth for sleek profiles.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'rare',
        priceCoins: 760,
        tags: ['SLEEK'],
        sortOrder: 160,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'nightlight_round', colors: ['#111827', '#4B5563'] }
    }),
    equippableItem({
        itemId: 'frame_rainbow',
        itemName: 'Rainbow Frame',
        itemDescription: 'Prismatic profile frame with a festival-ready vibe.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'legendary',
        priceCoins: 1490,
        tags: ['BRIGHT'],
        sortOrder: 170,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'palette', colors: ['#EC4899', '#F59E0B', '#10B981'] }
    }),
    equippableItem({
        itemId: 'frame_frost',
        itemName: 'Frost Frame',
        itemDescription: 'Chilled silver-blue ring for clean winter identity.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'rare',
        priceCoins: 830,
        tags: ['COOL'],
        sortOrder: 180,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'ac_unit', colors: ['#E0F2FE', '#60A5FA'] }
    }),
    equippableItem({
        itemId: 'frame_supreme_orbit',
        itemName: 'Supreme Orbit Frame',
        itemDescription: 'Mythic rotating orbit-style identity built for top collectors.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_frame',
        rarity: 'mythic',
        priceCoins: 2400,
        tags: ['LIMITED', 'ASPIRATION'],
        limitedEdition: true,
        stockCount: 2500,
        isFeatured: true,
        collectionSetId: 'supreme_set',
        sortOrder: 190,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'flare', colors: ['#8B5CF6', '#F59E0B', '#06B6D4'] }
    }),
    temporaryEquippableItem({
        itemId: 'glow_starlight_24h',
        itemName: 'Starlight Glow 24H',
        itemDescription: 'A temporary profile shimmer with soft floating sparkle.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'profile_glow',
        rarity: 'uncommon',
        priceCoins: 190,
        tags: ['IMPULSE'],
        expiryDurationSeconds: hours(24),
        sortOrder: 200,
        equipSlot: 'profileGlowItemId',
        previewStyle: { icon: 'stars', colors: ['#FDE68A', '#A78BFA'] }
    }),
    temporaryEquippableItem({
        itemId: 'avatar_border_spark_orbit_3d',
        itemName: 'Spark Orbit Border 3D',
        itemDescription: 'Three-day orbiting border that makes avatars feel more alive.',
        itemCategory: 'profile_cosmetics',
        itemSubcategory: 'avatar_border',
        rarity: 'rare',
        priceCoins: 460,
        tags: ['LIMITED'],
        expiryDurationSeconds: hours(72),
        sortOrder: 210,
        equipSlot: 'avatarBorderItemId',
        previewStyle: { icon: 'radio_button_checked', colors: ['#34D399', '#3B82F6'] }
    }),
    equippableItem({
        itemId: 'entry_pop',
        itemName: 'Pop Entry',
        itemDescription: 'A crisp little burst when you arrive.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'common',
        priceCoins: 250,
        tags: ['IMPULSE'],
        isPopular: true,
        collectionSetId: 'party_set',
        sortOrder: 300,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'celebration', colors: ['#22C55E', '#14B8A6'] }
    }),
    equippableItem({
        itemId: 'entry_confetti',
        itemName: 'Confetti Entry',
        itemDescription: 'A playful confetti splash for lively social rooms.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'uncommon',
        priceCoins: 430,
        tags: ['POPULAR'],
        collectionSetId: 'party_set',
        sortOrder: 310,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'celebration', colors: ['#F59E0B', '#EC4899'] }
    }),
    equippableItem({
        itemId: 'entry_spotlight',
        itemName: 'Spotlight Entry',
        itemDescription: 'A clean premium spotlight to announce your join.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'rare',
        priceCoins: 650,
        tags: ['HOT'],
        sortOrder: 320,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'light_mode', colors: ['#FDE68A', '#F59E0B'] }
    }),
    equippableItem({
        itemId: 'entry_thunder',
        itemName: 'Thunder Entry',
        itemDescription: 'Sharp electric flash for dramatic arrivals.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'rare',
        priceCoins: 720,
        tags: ['HOT'],
        sortOrder: 330,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'bolt', colors: ['#60A5FA', '#6366F1'] }
    }),
    equippableItem({
        itemId: 'entry_heart',
        itemName: 'Heart Entry',
        itemDescription: 'Soft floating hearts for warm playful rooms.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'common',
        priceCoins: 360,
        tags: ['CUTE'],
        collectionSetId: 'love_set',
        sortOrder: 340,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'favorite', colors: ['#FB7185', '#F472B6'] }
    }),
    equippableItem({
        itemId: 'entry_flame',
        itemName: 'Flame Entry',
        itemDescription: 'A hotter, more dramatic arrival with ember energy.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'epic',
        priceCoins: 810,
        tags: ['HOT'],
        sortOrder: 350,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'local_fire_department', colors: ['#FB923C', '#DC2626'] }
    }),
    equippableItem({
        itemId: 'entry_royal_carpet',
        itemName: 'Royal Carpet Entry',
        itemDescription: 'A rich gold-red reveal with host energy.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'epic',
        priceCoins: 1040,
        tags: ['ELITE'],
        collectionSetId: 'royal_set',
        sortOrder: 360,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'workspace_premium', colors: ['#B91C1C', '#F59E0B'] }
    }),
    equippableItem({
        itemId: 'entry_diamond_burst',
        itemName: 'Diamond Burst Entry',
        itemDescription: 'Crystal shards and cool prestige in one burst.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'legendary',
        priceCoins: 1450,
        tags: ['ELITE'],
        collectionSetId: 'diamond_set',
        sortOrder: 370,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'diamond', colors: ['#E0F2FE', '#38BDF8'] }
    }),
    equippableItem({
        itemId: 'entry_galaxy_portal',
        itemName: 'Galaxy Portal Entry',
        itemDescription: 'A portal glow built for cosmic identity flexing.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'legendary',
        priceCoins: 1620,
        tags: ['ASPIRATION'],
        collectionSetId: 'galaxy_set',
        sortOrder: 380,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'travel_explore', colors: ['#4F46E5', '#A855F7'] }
    }),
    equippableItem({
        itemId: 'entry_legend_arrival',
        itemName: 'Legend Arrival',
        itemDescription: 'A full mythic entrance for top-tier collectors.',
        itemCategory: 'room_entry_effects',
        itemSubcategory: 'entry_effect',
        rarity: 'mythic',
        priceCoins: 2850,
        tags: ['LIMITED', 'ULTIMATE'],
        limitedEdition: true,
        stockCount: 1800,
        isFeatured: true,
        collectionSetId: 'supreme_set',
        sortOrder: 390,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'military_tech', colors: ['#F59E0B', '#B91C1C', '#7C3AED'] }
    }),
    equippableItem({
        itemId: 'mic_aura_blue',
        itemName: 'Blue Mic Aura',
        itemDescription: 'Clean cool-tone mic aura for voice-first rooms.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'mic_aura',
        rarity: 'uncommon',
        priceCoins: 480,
        tags: ['POPULAR'],
        sortOrder: 500,
        equipSlot: 'micAuraItemId',
        previewStyle: { icon: 'mic', colors: ['#60A5FA', '#2563EB'] }
    }),
    equippableItem({
        itemId: 'mic_aura_fire',
        itemName: 'Fire Mic Aura',
        itemDescription: 'Warm ember mic ring for loud personalities.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'mic_aura',
        rarity: 'rare',
        priceCoins: 760,
        tags: ['HOT'],
        sortOrder: 510,
        equipSlot: 'micAuraItemId',
        previewStyle: { icon: 'mic', colors: ['#FB923C', '#DC2626'] }
    }),
    equippableItem({
        itemId: 'mic_ring_diamond',
        itemName: 'Diamond Mic Ring',
        itemDescription: 'Sharp crystal ring with premium room presence.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'mic_aura',
        rarity: 'legendary',
        priceCoins: 1240,
        tags: ['ELITE'],
        collectionSetId: 'diamond_set',
        sortOrder: 520,
        equipSlot: 'micAuraItemId',
        previewStyle: { icon: 'graphic_eq', colors: ['#E0F2FE', '#38BDF8'] }
    }),
    equippableItem({
        itemId: 'mic_love_pulse',
        itemName: 'Love Pulse Mic Skin',
        itemDescription: 'Soft pulse ring for sweet, playful room energy.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'mic_aura',
        rarity: 'rare',
        priceCoins: 620,
        tags: ['CUTE'],
        collectionSetId: 'love_set',
        sortOrder: 530,
        equipSlot: 'micAuraItemId',
        previewStyle: { icon: 'favorite', colors: ['#FB7185', '#F472B6'] }
    }),
    equippableItem({
        itemId: 'mic_golden_echo',
        itemName: 'Golden Echo Aura',
        itemDescription: 'Rich gold speaking aura with polished shine.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'speaking_glow',
        rarity: 'epic',
        priceCoins: 980,
        tags: ['ELITE'],
        sortOrder: 540,
        equipSlot: 'speakingGlowItemId',
        previewStyle: { icon: 'surround_sound', colors: ['#FDE68A', '#D97706'] }
    }),
    equippableItem({
        itemId: 'mic_cosmic_halo',
        itemName: 'Cosmic Voice Halo',
        itemDescription: 'Deep-space speaking glow for the galaxy crowd.',
        itemCategory: 'room_interaction_effects',
        itemSubcategory: 'speaking_glow',
        rarity: 'legendary',
        priceCoins: 1520,
        tags: ['ASPIRATION'],
        collectionSetId: 'galaxy_set',
        sortOrder: 550,
        equipSlot: 'speakingGlowItemId',
        previewStyle: { icon: 'blur_circular', colors: ['#6366F1', '#A855F7'] }
    }),
    equippableItem({
        itemId: 'bubble_candy',
        itemName: 'Candy Bubble',
        itemDescription: 'Sweet chat bubble for a fun, bright DM tone.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'common',
        priceCoins: 220,
        tags: ['IMPULSE'],
        sortOrder: 700,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#FDBA74', '#F472B6'] }
    }),
    equippableItem({
        itemId: 'bubble_neon',
        itemName: 'Neon Bubble',
        itemDescription: 'Bold bubble skin with lively blue-purple punch.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'uncommon',
        priceCoins: 340,
        tags: ['NEW'],
        sortOrder: 710,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#22D3EE', '#8B5CF6'] }
    }),
    equippableItem({
        itemId: 'bubble_royal',
        itemName: 'Royal Bubble',
        itemDescription: 'Luxury gold-red bubble with clear prestige.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'epic',
        priceCoins: 690,
        tags: ['ELITE'],
        collectionSetId: 'royal_set',
        sortOrder: 720,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#F59E0B', '#B91C1C'] }
    }),
    equippableItem({
        itemId: 'bubble_galaxy',
        itemName: 'Galaxy Bubble',
        itemDescription: 'Nebula chat skin for standout conversations.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'epic',
        priceCoins: 740,
        tags: ['POPULAR'],
        collectionSetId: 'galaxy_set',
        sortOrder: 730,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#4338CA', '#A855F7'] }
    }),
    equippableItem({
        itemId: 'bubble_minimal_black',
        itemName: 'Minimal Black Bubble',
        itemDescription: 'Dark polished chat shell for quieter premium style.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'common',
        priceCoins: 280,
        tags: ['SLEEK'],
        sortOrder: 740,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#111827', '#374151'] }
    }),
    equippableItem({
        itemId: 'bubble_love',
        itemName: 'Love Bubble',
        itemDescription: 'Heart-forward bubble that feels warm and playful.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'chat_bubble',
        rarity: 'common',
        priceCoins: 320,
        tags: ['CUTE'],
        collectionSetId: 'love_set',
        sortOrder: 750,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'chat_bubble', colors: ['#FB7185', '#F472B6'] }
    }),
    permanentUnlockItem({
        itemId: 'reaction_pack_emoji_1',
        itemName: 'Emoji Reaction Pack 1',
        itemDescription: 'Unlocks a cheerful extra reaction sticker set.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'reaction_pack',
        rarity: 'common',
        priceCoins: 260,
        tags: ['FUN'],
        sortOrder: 760,
        previewStyle: { icon: 'emoji_emotions', colors: ['#F59E0B', '#F97316'] }
    }),
    permanentUnlockItem({
        itemId: 'reaction_pack_emoji_2',
        itemName: 'Emoji Reaction Pack 2',
        itemDescription: 'Unlocks a brighter premium reaction pack with bolder moods.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'reaction_pack',
        rarity: 'rare',
        priceCoins: 420,
        tags: ['NEW'],
        sortOrder: 770,
        previewStyle: { icon: 'insert_emoticon', colors: ['#10B981', '#06B6D4'] }
    }),
    permanentUnlockItem({
        itemId: 'sticker_pack_fun',
        itemName: 'Sticker Pack Fun',
        itemDescription: 'Playful sticker reactions for casual social chats.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'sticker_pack',
        rarity: 'uncommon',
        priceCoins: 350,
        tags: ['FUN'],
        sortOrder: 780,
        previewStyle: { icon: 'sticky_note_2', colors: ['#F59E0B', '#84CC16'] }
    }),
    permanentUnlockItem({
        itemId: 'sticker_pack_romance',
        itemName: 'Sticker Pack Romance',
        itemDescription: 'Warm romance-themed stickers for softer moments.',
        itemCategory: 'chat_cosmetics',
        itemSubcategory: 'sticker_pack',
        rarity: 'uncommon',
        priceCoins: 360,
        tags: ['CUTE'],
        sortOrder: 790,
        previewStyle: { icon: 'favorite', colors: ['#FB7185', '#EC4899'] }
    }),
    equippableItem({
        itemId: 'nameplate_midnight_gold',
        itemName: 'Midnight Gold Nameplate',
        itemDescription: 'Dark premium nameplate with warm gold trim.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'rare',
        priceCoins: 420,
        tags: ['IDENTITY'],
        sortOrder: 900,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'badge', colors: ['#111827', '#F59E0B'], nameColor: '#FCD34D' }
    }),
    equippableItem({
        itemId: 'nameplate_cloud_pop',
        itemName: 'Cloud Pop Nameplate',
        itemDescription: 'Light pastel ribbon for a playful display name.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'uncommon',
        priceCoins: 360,
        tags: ['CUTE'],
        sortOrder: 910,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'sell', colors: ['#93C5FD', '#F9A8D4'], nameColor: '#F9A8D4' }
    }),
    equippableItem({
        itemId: 'nameplate_neon_pop',
        itemName: 'Neon Pop Nameplate',
        itemDescription: 'Electric cyan-violet ribbon for louder display-name style.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'epic',
        priceCoins: 620,
        tags: ['NEW'],
        collectionSetId: 'galaxy_set',
        sortOrder: 912,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'bolt', colors: ['#22D3EE', '#8B5CF6'], nameColor: '#C4B5FD' }
    }),
    equippableItem({
        itemId: 'nameplate_diamond_shine',
        itemName: 'Diamond Shine Nameplate',
        itemDescription: 'Crystal-cut identity ribbon for cool elite display energy.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'legendary',
        priceCoins: 960,
        tags: ['ELITE'],
        collectionSetId: 'diamond_set',
        sortOrder: 914,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'diamond', colors: ['#E0F2FE', '#38BDF8'], nameColor: '#BAE6FD' }
    }),
    equippableItem({
        itemId: 'nameplate_legend_ribbon',
        itemName: 'Legend Ribbon',
        itemDescription: 'Flame-gold prestige ribbon for standout room identity.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'legendary',
        priceCoins: 1180,
        tags: ['PRESTIGE'],
        collectionSetId: 'royal_set',
        sortOrder: 916,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'workspace_premium', colors: ['#F59E0B', '#B91C1C'], nameColor: '#FBBF24' }
    }),
    equippableItem({
        itemId: 'nameplate_supreme_prism',
        itemName: 'Supreme Prism Nameplate',
        itemDescription: 'Mythic rainbow-lit ribbon for top-tier account identity flex.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'nameplate',
        rarity: 'mythic',
        priceCoins: 1760,
        tags: ['ASPIRATION'],
        collectionSetId: 'supreme_set',
        sortOrder: 918,
        equipSlot: 'nameplateItemId',
        previewStyle: { icon: 'palette', colors: ['#EC4899', '#F59E0B', '#10B981', '#38BDF8'], nameColor: '#F8FAFC' }
    }),
    equippableItem({
        itemId: 'level_frame_prism',
        itemName: 'Prism Level Skin',
        itemDescription: 'Premium skin for your level badge frame in profile preview areas.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'level_frame_skin',
        rarity: 'rare',
        priceCoins: 540,
        tags: ['IDENTITY'],
        sortOrder: 920,
        equipSlot: 'levelFrameSkinItemId',
        previewStyle: { icon: 'military_tech', colors: ['#8B5CF6', '#06B6D4'] }
    }),
    equippableItem({
        itemId: 'room_card_neon_panel',
        itemName: 'Neon Room Card',
        itemDescription: 'Neon identity shell for room popups and cards.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'room_card_skin',
        rarity: 'epic',
        priceCoins: 760,
        tags: ['NEW'],
        sortOrder: 930,
        equipSlot: 'roomCardSkinItemId',
        previewStyle: { icon: 'style', colors: ['#22D3EE', '#8B5CF6'] }
    }),
    equippableItem({
        itemId: 'popup_card_royal_theme',
        itemName: 'Royal Popup Theme',
        itemDescription: 'Gold-accented identity theme for profile detail sheets.',
        itemCategory: 'identity_cosmetics',
        itemSubcategory: 'popup_card_theme',
        rarity: 'epic',
        priceCoins: 790,
        tags: ['ELITE'],
        sortOrder: 940,
        equipSlot: 'popupCardThemeItemId',
        previewStyle: { icon: 'view_carousel', colors: ['#B91C1C', '#F59E0B'] }
    }),
    boosterItem({
        itemId: 'booster_xp_2x_1h',
        itemName: '2x XP Booster 1 Hour',
        itemDescription: 'Doubles XP gains for one hour from the moment you activate it.',
        itemSubcategory: 'xp_boost',
        rarity: 'common',
        priceCoins: 120,
        tags: ['IMPULSE'],
        sortOrder: 1100,
        featureFlags: {
            boostSlot: 'xp_boost',
            multiplier: 2,
            durationSeconds: hours(1)
        },
        previewStyle: { icon: 'trending_up', colors: ['#34D399', '#22C55E'] }
    }),
    boosterItem({
        itemId: 'booster_xp_2x_24h',
        itemName: '2x XP Booster 24 Hours',
        itemDescription: 'A full-day XP booster for longer grind sessions.',
        itemSubcategory: 'xp_boost',
        rarity: 'epic',
        priceCoins: 1580,
        tags: ['BEST VALUE'],
        sortOrder: 1110,
        featureFlags: {
            boostSlot: 'xp_boost',
            multiplier: 2,
            durationSeconds: hours(24)
        },
        previewStyle: { icon: 'rocket_launch', colors: ['#34D399', '#10B981'] }
    }),
    boosterItem({
        itemId: 'booster_profile_highlight_1d',
        itemName: 'Profile Highlight 1 Day',
        itemDescription: 'Boost your profile visibility and glow for one day.',
        itemSubcategory: 'profile_highlight',
        rarity: 'uncommon',
        priceCoins: 280,
        tags: ['POPULAR'],
        sortOrder: 1120,
        featureFlags: {
            boostSlot: 'profile_highlight',
            durationSeconds: hours(24)
        },
        previewStyle: { icon: 'visibility', colors: ['#F59E0B', '#FB7185'] }
    }),
    boosterItem({
        itemId: 'booster_discover_ticket',
        itemName: 'Discover Boost Ticket',
        itemDescription: 'Temporary discover boost reserved for future explore placement logic.',
        itemSubcategory: 'discover_boost',
        rarity: 'rare',
        priceCoins: 340,
        tags: ['UTILITY'],
        sortOrder: 1130,
        featureFlags: {
            boostSlot: 'discover_boost',
            durationSeconds: hours(8)
        },
        previewStyle: { icon: 'explore', colors: ['#38BDF8', '#2563EB'] }
    }),
    utilityItem({
        itemId: 'utility_lucky_spin_token',
        itemName: 'Lucky Spin Token',
        itemDescription: 'Account-bound token for future luck-based events and spin features.',
        itemSubcategory: 'spin_token',
        rarity: 'uncommon',
        priceCoins: 180,
        tags: ['UTILITY'],
        sortOrder: 1140,
        previewStyle: { icon: 'casino', colors: ['#F59E0B', '#EC4899'] }
    }),
    utilityItem({
        itemId: 'utility_event_access_pass',
        itemName: 'Event Access Pass',
        itemDescription: 'Reserved pass for event-locked social experiences and seasonal drops.',
        itemSubcategory: 'event_pass',
        rarity: 'rare',
        priceCoins: 260,
        tags: ['UTILITY'],
        sortOrder: 1150,
        previewStyle: { icon: 'confirmation_number', colors: ['#8B5CF6', '#F59E0B'] }
    }),
    utilityItem({
        itemId: 'utility_spotlight_ticket',
        itemName: 'Spotlight Ticket',
        itemDescription: 'Single-use ticket reserved for future room spotlight and discovery moments.',
        itemSubcategory: 'spotlight_ticket',
        rarity: 'rare',
        priceCoins: 320,
        tags: ['UTILITY', 'NEW'],
        sortOrder: 1160,
        previewStyle: { icon: 'light_mode', colors: ['#FDE68A', '#F59E0B'] }
    }),
    capsuleItem({
        itemId: 'capsule_mystery',
        itemName: 'Mystery Capsule',
        itemDescription: 'Open for a random cosmetic, collectible, or booster.',
        itemSubcategory: 'capsule',
        rarity: 'rare',
        priceCoins: 260,
        tags: ['MYSTERY'],
        isFeatured: true,
        sortOrder: 1300,
        featureFlags: {
            dropTable: [
                { itemId: 'frame_soft_pink', weight: 12 },
                { itemId: 'entry_pop', weight: 12 },
                { itemId: 'bubble_candy', weight: 12 },
                { itemId: 'booster_xp_2x_1h', weight: 15, quantity: 2 },
                { itemId: 'collectible_golden_duck', weight: 10 },
                { itemId: 'collectible_lucky_coin_totem', weight: 8 },
                { itemId: 'frame_neon', weight: 8 },
                { itemId: 'entry_spotlight', weight: 7 },
                { itemId: 'mic_aura_fire', weight: 7 },
                { itemId: 'collectible_rare_crystal_orb', weight: 5 },
                { itemId: 'frame_supreme_orbit', weight: 2 }
            ]
        },
        previewStyle: { icon: 'inventory_2', colors: ['#8B5CF6', '#EC4899'] }
    }),
    collectibleItem({
        itemId: 'collectible_golden_duck',
        itemName: 'Golden Duck',
        itemDescription: 'A shiny decorative collectible that lives in your inventory showcase.',
        itemSubcategory: 'decor_collectible',
        rarity: 'uncommon',
        priceCoins: 520,
        tags: ['COLLECTIBLE'],
        sortOrder: 1310,
        previewStyle: { icon: 'pets', colors: ['#FBBF24', '#F59E0B'] }
    }),
    capsuleItem({
        itemId: 'festival_box',
        itemName: 'Festival Box',
        itemDescription: 'Seasonal reward box with a tighter premium drop table.',
        itemSubcategory: 'festival_box',
        rarity: 'epic',
        priceCoins: 680,
        tags: ['LIMITED', 'SEASONAL'],
        limitedEdition: true,
        sortOrder: 1320,
        featureFlags: {
            dropTable: [
                { itemId: 'frame_frost', weight: 14 },
                { itemId: 'bubble_love', weight: 14 },
                { itemId: 'nameplate_cloud_pop', weight: 12 },
                { itemId: 'entry_confetti', weight: 12 },
                { itemId: 'theme_winter_lounge', weight: 10 },
                { itemId: 'entry_holi_splash', weight: 10 },
                { itemId: 'frame_diwali_rangoli', weight: 8 },
                { itemId: 'popup_card_royal_theme', weight: 8 },
                { itemId: 'frame_supreme_orbit', weight: 2 }
            ]
        },
        previewStyle: { icon: 'redeem', colors: ['#F59E0B', '#8B5CF6'] }
    }),
    collectibleItem({
        itemId: 'collectible_lucky_coin_totem',
        itemName: 'Lucky Coin Totem',
        itemDescription: 'An account-bound good-luck display collectible.',
        itemSubcategory: 'decor_collectible',
        rarity: 'rare',
        priceCoins: 690,
        tags: ['COLLECTIBLE'],
        sortOrder: 1330,
        previewStyle: { icon: 'workspace_premium', colors: ['#FDE68A', '#F59E0B'] }
    }),
    collectibleItem({
        itemId: 'collectible_premium_toy_rocket',
        itemName: 'Premium Toy Rocket',
        itemDescription: 'Decorative rocket collectible for playful high-energy profiles.',
        itemSubcategory: 'decor_collectible',
        rarity: 'rare',
        priceCoins: 760,
        tags: ['COLLECTIBLE'],
        sortOrder: 1340,
        previewStyle: { icon: 'rocket_launch', colors: ['#38BDF8', '#8B5CF6'] }
    }),
    collectibleItem({
        itemId: 'collectible_rare_crystal_orb',
        itemName: 'Rare Crystal Orb',
        itemDescription: 'Premium crystal collectible with deep, cool-tone prestige.',
        itemSubcategory: 'decor_collectible',
        rarity: 'legendary',
        priceCoins: 1420,
        tags: ['COLLECTIBLE', 'ELITE'],
        collectionSetId: 'diamond_set',
        sortOrder: 1350,
        previewStyle: { icon: 'auto_awesome', colors: ['#E0F2FE', '#38BDF8'] }
    }),
    equippableItem({
        itemId: 'frame_diwali_rangoli',
        itemName: 'Diwali Rangoli Frame',
        itemDescription: 'Festival-inspired lights and gold for celebratory profiles.',
        itemCategory: 'seasonal',
        itemSubcategory: 'profile_frame',
        rarity: 'epic',
        priceCoins: 980,
        tags: ['LIMITED', 'SEASONAL'],
        limitedEdition: true,
        sortOrder: 1500,
        equipSlot: 'profileFrameItemId',
        previewStyle: { icon: 'lightbulb', colors: ['#F59E0B', '#FB7185'] }
    }),
    equippableItem({
        itemId: 'entry_holi_splash',
        itemName: 'Holi Splash Entry',
        itemDescription: 'Color splash arrival effect inspired by festival powder bursts.',
        itemCategory: 'seasonal',
        itemSubcategory: 'entry_effect',
        rarity: 'epic',
        priceCoins: 1050,
        tags: ['LIMITED', 'SEASONAL'],
        limitedEdition: true,
        sortOrder: 1510,
        equipSlot: 'entryEffectItemId',
        previewStyle: { icon: 'water_drop', colors: ['#F97316', '#A855F7', '#22C55E'] }
    }),
    equippableItem({
        itemId: 'bubble_valentine_whisper',
        itemName: 'Valentine Whisper Bubble',
        itemDescription: 'Soft romantic chat bubble with subtle shimmer.',
        itemCategory: 'seasonal',
        itemSubcategory: 'chat_bubble',
        rarity: 'rare',
        priceCoins: 430,
        tags: ['LIMITED', 'SEASONAL'],
        limitedEdition: true,
        sortOrder: 1520,
        equipSlot: 'chatBubbleItemId',
        previewStyle: { icon: 'favorite', colors: ['#FB7185', '#F472B6'] }
    }),
    equippableItem({
        itemId: 'theme_winter_lounge',
        itemName: 'Winter Lounge Card',
        itemDescription: 'Cool seasonal card theme for user popups and identity surfaces.',
        itemCategory: 'seasonal',
        itemSubcategory: 'popup_card_theme',
        rarity: 'rare',
        priceCoins: 640,
        tags: ['LIMITED', 'SEASONAL'],
        limitedEdition: true,
        sortOrder: 1530,
        equipSlot: 'popupCardThemeItemId',
        previewStyle: { icon: 'ac_unit', colors: ['#E0F2FE', '#60A5FA'] }
    }),
    bundleItem({
        itemId: 'bundle_cute_starter_pack',
        itemName: 'Cute Starter Pack',
        itemDescription: 'A low-friction starter bundle with a sweet frame, entry, and bubble.',
        rarity: 'uncommon',
        priceCoins: 980,
        tags: ['BEST VALUE'],
        isFeatured: true,
        sortOrder: 1700,
        bundleContents: [
            { itemId: 'frame_soft_pink', quantity: 1 },
            { itemId: 'entry_heart', quantity: 1 },
            { itemId: 'bubble_love', quantity: 1 },
            { itemId: 'reaction_pack_emoji_1', quantity: 1 }
        ],
        previewStyle: { icon: 'redeem', colors: ['#F9A8D4', '#FB7185'] }
    }),
    bundleItem({
        itemId: 'bundle_party_pack',
        itemName: 'Party Pack',
        itemDescription: 'Bring confetti, room energy, and brighter reactions into one pack.',
        rarity: 'rare',
        priceCoins: 1420,
        tags: ['POPULAR'],
        sortOrder: 1710,
        bundleContents: [
            { itemId: 'entry_confetti', quantity: 1 },
            { itemId: 'entry_pop', quantity: 1 },
            { itemId: 'mic_aura_blue', quantity: 1 },
            { itemId: 'sticker_pack_fun', quantity: 1 }
        ],
        previewStyle: { icon: 'party_mode', colors: ['#F59E0B', '#EC4899'] }
    }),
    bundleItem({
        itemId: 'bundle_profile_glow_pack',
        itemName: 'Profile Glow Pack',
        itemDescription: 'A profile-first bundle with glow and premium shell upgrades.',
        rarity: 'rare',
        priceCoins: 1540,
        tags: ['BEST VALUE'],
        sortOrder: 1720,
        bundleContents: [
            { itemId: 'frame_neon', quantity: 1 },
            { itemId: 'glow_starlight_24h', quantity: 1 },
            { itemId: 'avatar_border_spark_orbit_3d', quantity: 1 },
            { itemId: 'nameplate_midnight_gold', quantity: 1 }
        ],
        previewStyle: { icon: 'flare', colors: ['#22D3EE', '#8B5CF6'] }
    }),
    bundleItem({
        itemId: 'bundle_elite_entry_pack',
        itemName: 'Elite Entry Pack',
        itemDescription: 'Premium arrival bundle for users who want every join to land.',
        rarity: 'epic',
        priceCoins: 2280,
        tags: ['ELITE CHOICE'],
        sortOrder: 1730,
        bundleContents: [
            { itemId: 'entry_spotlight', quantity: 1 },
            { itemId: 'entry_flame', quantity: 1 },
            { itemId: 'entry_royal_carpet', quantity: 1 }
        ],
        previewStyle: { icon: 'workspace_premium', colors: ['#B91C1C', '#F59E0B'] }
    }),
    bundleItem({
        itemId: 'bundle_creator_boost_pack',
        itemName: 'Creator Boost Pack',
        itemDescription: 'Useful utility bundle for users pushing profile and progression.',
        rarity: 'epic',
        priceCoins: 1880,
        tags: ['UTILITY'],
        sortOrder: 1740,
        bundleContents: [
            { itemId: 'booster_xp_2x_1h', quantity: 4 },
            { itemId: 'booster_profile_highlight_1d', quantity: 2 },
            { itemId: 'booster_discover_ticket', quantity: 2 },
            { itemId: 'utility_event_access_pass', quantity: 1 }
        ],
        previewStyle: { icon: 'trending_up', colors: ['#22C55E', '#06B6D4'] }
    }),
    bundleItem({
        itemId: 'bundle_seasonal_pack',
        itemName: 'Seasonal Pack',
        itemDescription: 'Festival cosmetics and a premium box in one rotating bundle.',
        rarity: 'legendary',
        priceCoins: 2140,
        tags: ['LIMITED', 'BEST VALUE'],
        limitedEdition: true,
        isFeatured: true,
        sortOrder: 1750,
        bundleContents: [
            { itemId: 'frame_diwali_rangoli', quantity: 1 },
            { itemId: 'entry_holi_splash', quantity: 1 },
            { itemId: 'bubble_valentine_whisper', quantity: 1 },
            { itemId: 'festival_box', quantity: 1 }
        ],
        previewStyle: { icon: 'redeem', colors: ['#F59E0B', '#8B5CF6', '#22C55E'] }
    }),
]);

const SHOP_CATALOG_BY_ID = Object.freeze(
    SHOP_CATALOG.reduce((accumulator, item) => {
        accumulator[item.itemId] = item;
        return accumulator;
    }, {})
);

const FIRST_SHOP_PURCHASE_REWARD_ITEM_ID = 'collectible_lucky_coin_totem';
const DAILY_DEAL_ITEM_COUNT = 3;

module.exports = {
    DAILY_DEAL_ITEM_COUNT,
    FIRST_SHOP_PURCHASE_REWARD_ITEM_ID,
    SHOP_CATALOG,
    SHOP_CATALOG_BY_ID,
    SHOP_CATEGORIES,
    SHOP_COLLECTION_SETS,
    SHOP_RARITIES
};
