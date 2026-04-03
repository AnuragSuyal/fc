const VIP_TIER_ORDER = [
    'vip1',
    'vip2',
    'vip3',
    'vip4',
    'vip5',
    'vip6',
    'vip7',
    'vip8',
    'vip9',
    'vip10',
    'diamond',
    'legend',
    'supreme'
];

const VIP_PLAN_DEFINITIONS = {
    monthly: {
        planDuration: 'monthly',
        label: 'Monthly',
        durationDays: 30,
        savingsPercent: 0
    },
    quarterly: {
        planDuration: 'quarterly',
        label: 'Quarterly',
        durationDays: 90,
        savingsPercent: 10
    },
    yearly: {
        planDuration: 'yearly',
        label: 'Yearly',
        durationDays: 365,
        savingsPercent: 20
    }
};

const defineTier = ({
    tierId,
    level,
    displayName,
    shortLabel,
    badgeAsset,
    nameColorStyle,
    frameAsset,
    monthlyBasePrice,
    xpBoostPercent,
    monthlyCoinReward,
    giftingPerkLevel,
    roomEntryEffect,
    premiumEffects,
    featureFlags,
    newlyUnlockedBenefits,
    ui
}) => {
    const quarterlyPrice = Math.round(monthlyBasePrice * 2.7);
    const yearlyPrice = Math.round(monthlyBasePrice * 9.6);

    return {
        tierId,
        level,
        displayOrder: level,
        displayName,
        shortLabel,
        badgeAsset,
        nameColorStyle,
        frameAsset,
        xpBoostPercent,
        monthlyCoinReward,
        giftingPerkLevel,
        roomEntryEffect,
        premiumEffects,
        featureFlags,
        newlyUnlockedBenefits,
        ui,
        pricing: {
            monthly: {
                coins: monthlyBasePrice,
                durationDays: VIP_PLAN_DEFINITIONS.monthly.durationDays,
                savingsPercent: 0
            },
            quarterly: {
                coins: quarterlyPrice,
                durationDays: VIP_PLAN_DEFINITIONS.quarterly.durationDays,
                savingsPercent: 10
            },
            yearly: {
                coins: yearlyPrice,
                durationDays: VIP_PLAN_DEFINITIONS.yearly.durationDays,
                savingsPercent: 20
            }
        }
    };
};

const VIP_MEMBERSHIP_TIERS = [
    defineTier({
        tierId: 'vip1',
        level: 1,
        displayName: 'VIP 1',
        shortLabel: 'VIP 1',
        badgeAsset: 'badge_vip1',
        nameColorStyle: {
            token: 'green',
            label: 'Green',
            colors: ['#B9FF60', '#4FD53B']
        },
        frameAsset: 'vip_frame_basic_green',
        monthlyBasePrice: 499,
        xpBoostPercent: 5,
        monthlyCoinReward: 400,
        giftingPerkLevel: 0,
        roomEntryEffect: 'premium_status_glow',
        premiumEffects: ['basic_identity_glow', 'vip_chat_bubble'],
        featureFlags: {
            vipChatBubble: true,
            basicPremiumIdentity: true,
            purchaseWelcomePack: true,
            extraDailyRewardCoins: 20
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip1_badge',
                category: 'identity',
                title: 'Unique VIP 1 badge',
                description: 'Show your first premium identity badge across the app.'
            },
            {
                id: 'vip1_name_color',
                category: 'identity',
                title: 'Green premium name color',
                description: 'Your display name uses a fresh premium green accent.'
            },
            {
                id: 'vip1_frame',
                category: 'profile',
                title: 'Basic premium profile frame',
                description: 'Unlock the first premium frame linked to membership.'
            },
            {
                id: 'vip1_xp',
                category: 'progression',
                title: '5% XP boost',
                description: 'Earn 5% more XP from eligible progression sources.'
            },
            {
                id: 'vip1_reward',
                category: 'rewards',
                title: 'Monthly coin reward',
                description: 'Claim a monthly membership reward from the VIP page.'
            },
            {
                id: 'vip1_identity',
                category: 'identity',
                title: 'VIP chat bubble and welcome pack',
                description: 'Start with a premium chat bubble and a basic welcome pack.'
            }
        ],
        ui: {
            accent: '#7EF24B',
            gradient: ['#123B23', '#1E7A40', '#9BE15D'],
            glow: '#A3FF5A'
        }
    }),
    defineTier({
        tierId: 'vip2',
        level: 2,
        displayName: 'VIP 2',
        shortLabel: 'VIP 2',
        badgeAsset: 'badge_vip2',
        nameColorStyle: {
            token: 'blue',
            label: 'Blue',
            colors: ['#77C4FF', '#2C7DFF']
        },
        frameAsset: 'vip_frame_improved_blue',
        monthlyBasePrice: 899,
        xpBoostPercent: 8,
        monthlyCoinReward: 650,
        giftingPerkLevel: 0,
        roomEntryEffect: 'better_room_join_identity',
        premiumEffects: ['emoji_pack_vip2', 'enhanced_join_presence'],
        featureFlags: {
            vipChatBubble: true,
            basicPremiumIdentity: true,
            purchaseWelcomePack: true,
            emojiPackCount: 1,
            enhancedRoomJoinIdentity: true,
            extraDailyRewardCoins: 30
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip2_badge',
                category: 'identity',
                title: 'Unique VIP 2 badge',
                description: 'Upgrade to a brighter VIP badge with a stronger room presence.'
            },
            {
                id: 'vip2_name_color',
                category: 'identity',
                title: 'Blue premium name color',
                description: 'Switch your display name to a cool premium blue.'
            },
            {
                id: 'vip2_frame',
                category: 'profile',
                title: 'Improved premium frame',
                description: 'Use a sharper frame style that feels more elevated.'
            },
            {
                id: 'vip2_xp',
                category: 'progression',
                title: '8% XP boost',
                description: 'Push your progression further with an 8% bonus XP rate.'
            },
            {
                id: 'vip2_monthly_reward',
                category: 'rewards',
                title: 'Larger monthly reward',
                description: 'Claim a better monthly coin bundle than VIP 1.'
            },
            {
                id: 'vip2_reaction_pack',
                category: 'cosmetics',
                title: 'Exclusive reaction pack',
                description: 'Unlock one membership-only emoji and reaction pack.'
            }
        ],
        ui: {
            accent: '#4C9CFF',
            gradient: ['#0A1E4F', '#1740A6', '#4DAFFF'],
            glow: '#79CCFF'
        }
    }),
    defineTier({
        tierId: 'vip3',
        level: 3,
        displayName: 'VIP 3',
        shortLabel: 'VIP 3',
        badgeAsset: 'badge_vip3',
        nameColorStyle: {
            token: 'purple',
            label: 'Purple',
            colors: ['#DE9CFF', '#8E3FF8']
        },
        frameAsset: 'vip_frame_richer_purple',
        monthlyBasePrice: 1399,
        xpBoostPercent: 10,
        monthlyCoinReward: 900,
        giftingPerkLevel: 0,
        roomEntryEffect: 'better_room_join_identity',
        premiumEffects: ['gift_display_enhancement', 'profile_visibility_style'],
        featureFlags: {
            emojiPackCount: 1,
            profileVisibilityStyle: true,
            giftDisplayEnhancement: true,
            extraDailyRewardCoins: 40
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip3_badge',
                category: 'identity',
                title: 'Unique VIP 3 badge',
                description: 'Move up to a richer purple badge with more visual weight.'
            },
            {
                id: 'vip3_name_color',
                category: 'identity',
                title: 'Purple premium name color',
                description: 'Your profile and room identity shift to a prestige purple tone.'
            },
            {
                id: 'vip3_frame',
                category: 'profile',
                title: 'Richer premium frame',
                description: 'A more decorative frame adds depth to your profile.'
            },
            {
                id: 'vip3_xp',
                category: 'progression',
                title: '10% XP boost',
                description: 'Boost every eligible XP gain by 10%.'
            },
            {
                id: 'vip3_monthly_reward',
                category: 'rewards',
                title: 'Better monthly reward',
                description: 'Claim a stronger monthly coin reward than previous tiers.'
            },
            {
                id: 'vip3_visibility',
                category: 'identity',
                title: 'Gifting display enhancement',
                description: 'Stand out with stronger gift display and profile visibility styling.'
            }
        ],
        ui: {
            accent: '#B46BFF',
            gradient: ['#2C0E46', '#6520A5', '#D36DFF'],
            glow: '#DB8DFF'
        }
    }),
    defineTier({
        tierId: 'vip4',
        level: 4,
        displayName: 'VIP 4',
        shortLabel: 'VIP 4',
        badgeAsset: 'badge_vip4',
        nameColorStyle: {
            token: 'orange',
            label: 'Orange',
            colors: ['#FFCE72', '#FF8C21']
        },
        frameAsset: 'vip_frame_luxury_orange',
        monthlyBasePrice: 1899,
        xpBoostPercent: 12,
        monthlyCoinReward: 1250,
        giftingPerkLevel: 0,
        roomEntryEffect: 'vip_room_entry_orange',
        premiumEffects: ['room_profile_border_effect', 'entry_effect_vip4'],
        featureFlags: {
            roomEntryEffect: true,
            roomProfileBorderEffect: true,
            extraDailyRewardCoins: 50
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip4_badge',
                category: 'identity',
                title: 'Unique VIP 4 badge',
                description: 'Your badge becomes brighter and more luxurious.'
            },
            {
                id: 'vip4_name_color',
                category: 'identity',
                title: 'Orange premium name color',
                description: 'A warm orange name color announces your higher-tier presence.'
            },
            {
                id: 'vip4_frame',
                category: 'profile',
                title: 'Luxurious frame',
                description: 'Unlock a more ornate premium frame.'
            },
            {
                id: 'vip4_xp',
                category: 'progression',
                title: '12% XP boost',
                description: 'Get a 12% XP bonus on supported progression events.'
            },
            {
                id: 'vip4_entry',
                category: 'room',
                title: 'Room entry effect',
                description: 'Make your arrival feel premium with a dedicated room entry effect.'
            },
            {
                id: 'vip4_border',
                category: 'room',
                title: 'Room profile border effect',
                description: 'Carry a stronger visual border inside room identity surfaces.'
            }
        ],
        ui: {
            accent: '#FF9A2B',
            gradient: ['#42200C', '#A84E13', '#FFB347'],
            glow: '#FFB54C'
        }
    }),
    defineTier({
        tierId: 'vip5',
        level: 5,
        displayName: 'VIP 5',
        shortLabel: 'VIP 5',
        badgeAsset: 'badge_vip5',
        nameColorStyle: {
            token: 'red',
            label: 'Red',
            colors: ['#FFB1B1', '#E63838']
        },
        frameAsset: 'vip_frame_royal_red',
        monthlyBasePrice: 2499,
        xpBoostPercent: 15,
        monthlyCoinReward: 1650,
        giftingPerkLevel: 1,
        roomEntryEffect: 'vip_room_micro_animation_red',
        premiumEffects: ['gifting_perk_level_1', 'micro_join_animation'],
        featureFlags: {
            giftingPerkLevel: 1,
            microJoinAnimation: true,
            extraDailyRewardCoins: 65
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip5_badge',
                category: 'identity',
                title: 'Unique VIP 5 badge',
                description: 'Your badge steps into a royal red identity tier.'
            },
            {
                id: 'vip5_name_color',
                category: 'identity',
                title: 'Red premium name color',
                description: 'A confident premium red makes your name unmistakable.'
            },
            {
                id: 'vip5_frame',
                category: 'profile',
                title: 'Royal frame',
                description: 'Unlock a royal-grade profile frame.'
            },
            {
                id: 'vip5_xp',
                category: 'progression',
                title: '15% XP boost',
                description: 'Accelerate level progress with a 15% XP bonus.'
            },
            {
                id: 'vip5_gifting',
                category: 'gifting',
                title: 'Gifting perk level 1',
                description: 'Start unlocking stronger gifting-related premium behavior.'
            },
            {
                id: 'vip5_join',
                category: 'room',
                title: 'Micro room join animation',
                description: 'Enter rooms with a more dramatic premium micro-animation.'
            }
        ],
        ui: {
            accent: '#FF5555',
            gradient: ['#451014', '#8E171C', '#FF7469'],
            glow: '#FF7C72'
        }
    }),
    defineTier({
        tierId: 'vip6',
        level: 6,
        displayName: 'VIP 6',
        shortLabel: 'VIP 6',
        badgeAsset: 'badge_vip6',
        nameColorStyle: {
            token: 'emerald',
            label: 'Emerald',
            colors: ['#D6FF95', '#1FCF7A']
        },
        frameAsset: 'vip_frame_animated_emerald',
        monthlyBasePrice: 3299,
        xpBoostPercent: 18,
        monthlyCoinReward: 2100,
        giftingPerkLevel: 2,
        roomEntryEffect: 'vip_room_entry_emerald',
        premiumEffects: ['gifting_perk_level_2', 'exclusive_collectible_access'],
        featureFlags: {
            giftingPerkLevel: 2,
            exclusiveCollectibleStoreAccess: 1,
            animatedFrame: true,
            extraDailyRewardCoins: 80
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip6_badge',
                category: 'identity',
                title: 'Unique VIP 6 badge',
                description: 'A crown-forward emerald badge elevates your status.'
            },
            {
                id: 'vip6_name_color',
                category: 'identity',
                title: 'Emerald premium name color',
                description: 'Give your identity a clean emerald premium finish.'
            },
            {
                id: 'vip6_frame',
                category: 'profile',
                title: 'Exclusive premium frame',
                description: 'Use a stronger premium frame with animation-ready styling.'
            },
            {
                id: 'vip6_xp',
                category: 'progression',
                title: '18% XP boost',
                description: 'Earn 18% more XP from supported sources.'
            },
            {
                id: 'vip6_gifting',
                category: 'gifting',
                title: 'Gifting perk level 2',
                description: 'Upgrade gifting benefits beyond VIP 5.'
            },
            {
                id: 'vip6_collectible',
                category: 'access',
                title: 'Exclusive collectible item access',
                description: 'Unlock one collectible store lane that lower tiers cannot reach.'
            }
        ],
        ui: {
            accent: '#34D399',
            gradient: ['#123822', '#0F7A5C', '#B8F84A'],
            glow: '#96F34E'
        }
    }),
    defineTier({
        tierId: 'vip7',
        level: 7,
        displayName: 'VIP 7',
        shortLabel: 'VIP 7',
        badgeAsset: 'badge_vip7',
        nameColorStyle: {
            token: 'sapphire',
            label: 'Sapphire',
            colors: ['#B7E0FF', '#2E6CFF']
        },
        frameAsset: 'vip_frame_elite_sapphire',
        monthlyBasePrice: 4199,
        xpBoostPercent: 20,
        monthlyCoinReward: 2650,
        giftingPerkLevel: 3,
        roomEntryEffect: 'vip_room_entry_sapphire',
        premiumEffects: ['premium_user_card_styling', 'stronger_entry_effect'],
        featureFlags: {
            giftingPerkLevel: 3,
            premiumUserCardStyling: true,
            strongerRoomEntryEffect: true,
            extraDailyRewardCoins: 95
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip7_badge',
                category: 'identity',
                title: 'Unique VIP 7 badge',
                description: 'Your badge shifts to an elite sapphire and silver tone.'
            },
            {
                id: 'vip7_name_color',
                category: 'identity',
                title: 'Sapphire premium name color',
                description: 'Your display name gains a crisp sapphire premium finish.'
            },
            {
                id: 'vip7_frame',
                category: 'profile',
                title: 'Elite frame',
                description: 'Unlock an elite frame reserved for higher VIP members.'
            },
            {
                id: 'vip7_xp',
                category: 'progression',
                title: '20% XP boost',
                description: 'Hit a 20% XP multiplier across supported progression systems.'
            },
            {
                id: 'vip7_user_card',
                category: 'identity',
                title: 'Premium user card styling',
                description: 'Carry a more polished identity card inside rooms and sheets.'
            },
            {
                id: 'vip7_gifting',
                category: 'gifting',
                title: 'Gifting perk level 3',
                description: 'Continue upgrading premium gifting-related value.'
            }
        ],
        ui: {
            accent: '#5EA7FF',
            gradient: ['#111D4A', '#2146A9', '#9BD8FF'],
            glow: '#9CCFFF'
        }
    }),
    defineTier({
        tierId: 'vip8',
        level: 8,
        displayName: 'VIP 8',
        shortLabel: 'VIP 8',
        badgeAsset: 'badge_vip8',
        nameColorStyle: {
            token: 'violet_gold',
            label: 'Violet-Gold',
            colors: ['#F1C8FF', '#9F47FF', '#F0C553']
        },
        frameAsset: 'vip_frame_elite_violet_gold',
        monthlyBasePrice: 5199,
        xpBoostPercent: 22,
        monthlyCoinReward: 3250,
        giftingPerkLevel: 4,
        roomEntryEffect: 'vip_room_highlight_violet_gold',
        premiumEffects: ['exclusive_reaction_pack', 'room_highlight_effect'],
        featureFlags: {
            giftingPerkLevel: 4,
            exclusiveReactionPack: true,
            roomHighlightEffect: true,
            extraDailyRewardCoins: 110
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip8_badge',
                category: 'identity',
                title: 'Unique VIP 8 badge',
                description: 'A violet-gold badge signals elite premium status instantly.'
            },
            {
                id: 'vip8_name_color',
                category: 'identity',
                title: 'Violet-gold name color',
                description: 'Blend violet prestige with premium gold highlights.'
            },
            {
                id: 'vip8_frame',
                category: 'profile',
                title: 'Elite frame upgrade',
                description: 'A stronger elite frame makes your profile feel rarer.'
            },
            {
                id: 'vip8_xp',
                category: 'progression',
                title: '22% XP boost',
                description: 'Turn your progression into a 22% XP-boosted pace.'
            },
            {
                id: 'vip8_reactions',
                category: 'cosmetics',
                title: 'Exclusive premium reaction pack',
                description: 'Unlock a more premium reaction and emoji set.'
            },
            {
                id: 'vip8_highlight',
                category: 'room',
                title: 'Room highlight effect',
                description: 'Gain an elevated room highlight effect and gifting perk level 4.'
            }
        ],
        ui: {
            accent: '#B874FF',
            gradient: ['#281347', '#6130A5', '#E8C86A'],
            glow: '#E9C971'
        }
    }),
    defineTier({
        tierId: 'vip9',
        level: 9,
        displayName: 'VIP 9',
        shortLabel: 'VIP 9',
        badgeAsset: 'badge_vip9',
        nameColorStyle: {
            token: 'crimson',
            label: 'Crimson',
            colors: ['#FFC0C0', '#A70F25']
        },
        frameAsset: 'vip_frame_elite_crimson',
        monthlyBasePrice: 6399,
        xpBoostPercent: 25,
        monthlyCoinReward: 4000,
        giftingPerkLevel: 4,
        roomEntryEffect: 'vip_room_prestige_crimson',
        premiumEffects: ['exclusive_store_access', 'profile_prestige_styling'],
        featureFlags: {
            giftingPerkLevel: 4,
            premiumStoreAccess: true,
            strongerProfilePrestigeStyling: true,
            extraDailyRewardCoins: 130
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip9_badge',
                category: 'identity',
                title: 'Unique VIP 9 badge',
                description: 'Crimson-black prestige pushes your badge into a high-tier look.'
            },
            {
                id: 'vip9_name_color',
                category: 'identity',
                title: 'Crimson premium name color',
                description: 'Use a darker premium crimson identity tone across the app.'
            },
            {
                id: 'vip9_frame',
                category: 'profile',
                title: 'Very elite frame',
                description: 'Unlock a heavier prestige frame reserved for very high tiers.'
            },
            {
                id: 'vip9_xp',
                category: 'progression',
                title: '25% XP boost',
                description: 'Earn a strong 25% XP bonus from eligible activities.'
            },
            {
                id: 'vip9_store',
                category: 'access',
                title: 'Exclusive premium store access',
                description: 'Get access to a premium store lane unavailable to lower tiers.'
            },
            {
                id: 'vip9_prestige',
                category: 'identity',
                title: 'Stronger profile prestige styling',
                description: 'Carry a more serious prestige presentation on profile surfaces.'
            }
        ],
        ui: {
            accent: '#C62136',
            gradient: ['#1F1115', '#5E0B16', '#D95A47'],
            glow: '#E36D58'
        }
    }),
    defineTier({
        tierId: 'vip10',
        level: 10,
        displayName: 'VIP 10',
        shortLabel: 'VIP 10',
        badgeAsset: 'badge_vip10',
        nameColorStyle: {
            token: 'gold',
            label: 'Gold',
            colors: ['#FFE28F', '#F3B228']
        },
        frameAsset: 'vip_frame_ultra_gold',
        monthlyBasePrice: 7899,
        xpBoostPercent: 30,
        monthlyCoinReward: 5000,
        giftingPerkLevel: 5,
        roomEntryEffect: 'vip_room_elite_gold',
        premiumEffects: ['elite_room_entry_effect', 'premium_identity_everywhere'],
        featureFlags: {
            giftingPerkLevel: 5,
            eliteRoomEntryEffect: true,
            premiumIdentityEverywhere: true,
            extraDailyRewardCoins: 150
        },
        newlyUnlockedBenefits: [
            {
                id: 'vip10_badge',
                category: 'identity',
                title: 'Unique VIP 10 badge',
                description: 'Step into the top VIP bracket with a gold-and-red badge.'
            },
            {
                id: 'vip10_name_color',
                category: 'identity',
                title: 'Gold premium name color',
                description: 'A gold premium name color marks you as top-tier VIP.'
            },
            {
                id: 'vip10_frame',
                category: 'profile',
                title: 'Ultra-premium frame',
                description: 'Unlock a richer gold ultra-premium frame.'
            },
            {
                id: 'vip10_xp',
                category: 'progression',
                title: '30% XP boost',
                description: 'Reach a major 30% XP bonus across supported activities.'
            },
            {
                id: 'vip10_identity',
                category: 'identity',
                title: 'Premium identity everywhere',
                description: 'Make your room list, profile, and user card presence feel elite.'
            },
            {
                id: 'vip10_gifting',
                category: 'gifting',
                title: 'Gifting perk level 5',
                description: 'Unlock the highest VIP gifting perk tier.'
            }
        ],
        ui: {
            accent: '#F0BF3C',
            gradient: ['#31210C', '#7E3111', '#F8D66A'],
            glow: '#FFD96F'
        }
    }),
    defineTier({
        tierId: 'diamond',
        level: 11,
        displayName: 'Diamond',
        shortLabel: 'Diamond',
        badgeAsset: 'badge_diamond',
        nameColorStyle: {
            token: 'ice_blue',
            label: 'Ice Blue',
            colors: ['#DDF3FF', '#79C7FF']
        },
        frameAsset: 'vip_frame_luxury_crystal',
        monthlyBasePrice: 9999,
        xpBoostPercent: 35,
        monthlyCoinReward: 6500,
        giftingPerkLevel: 6,
        roomEntryEffect: 'diamond_room_prestige',
        premiumEffects: ['diamond_reaction_pack', 'exclusive_event_access'],
        featureFlags: {
            giftingPerkLevel: 6,
            giftingDiscountPercent: 5,
            exclusiveDiamondReactionPack: true,
            exclusiveEventAccess: true,
            strongerRoomPrestigeVisuals: true,
            extraDailyRewardCoins: 180
        },
        newlyUnlockedBenefits: [
            {
                id: 'diamond_badge',
                category: 'identity',
                title: 'Diamond badge',
                description: 'Use the first elite prestige badge beyond VIP 10.'
            },
            {
                id: 'diamond_name_color',
                category: 'identity',
                title: 'Ice blue diamond name color',
                description: 'Your name takes on a crystal-blue premium glow.'
            },
            {
                id: 'diamond_frame',
                category: 'profile',
                title: 'Luxury crystal frame',
                description: 'Unlock a crystal profile frame worthy of Diamond tier.'
            },
            {
                id: 'diamond_xp',
                category: 'progression',
                title: '35% XP boost',
                description: 'Get a 35% XP multiplier from supported actions.'
            },
            {
                id: 'diamond_events',
                category: 'access',
                title: 'Exclusive event access',
                description: 'Join Diamond-only event lanes and unlock Diamond reactions.'
            },
            {
                id: 'diamond_identity',
                category: 'identity',
                title: 'Diamond identity across the app',
                description: 'Carry Diamond prestige throughout profile, room, and card surfaces.'
            }
        ],
        ui: {
            accent: '#7CCBFF',
            gradient: ['#0F223F', '#29579A', '#C3F0FF'],
            glow: '#CBF4FF'
        }
    }),
    defineTier({
        tierId: 'legend',
        level: 12,
        displayName: 'Legend',
        shortLabel: 'Legend',
        badgeAsset: 'badge_legend',
        nameColorStyle: {
            token: 'gold_red',
            label: 'Gold-Red',
            colors: ['#FFD976', '#D9372A', '#FF9B44']
        },
        frameAsset: 'vip_frame_mythic_legend',
        monthlyBasePrice: 12999,
        xpBoostPercent: 40,
        monthlyCoinReward: 8200,
        giftingPerkLevel: 7,
        roomEntryEffect: 'legend_room_spotlight',
        premiumEffects: ['legend_only_effects', 'profile_prestige_superior'],
        featureFlags: {
            giftingPerkLevel: 7,
            legendOnlyEffects: true,
            premiumRoomSpotlightStyling: true,
            exclusiveCollectiblePerks: true,
            supportPriority: 'priority',
            extraDailyRewardCoins: 220
        },
        newlyUnlockedBenefits: [
            {
                id: 'legend_badge',
                category: 'identity',
                title: 'Legend badge',
                description: 'Wear a mythic dragon-forged Legend badge.'
            },
            {
                id: 'legend_name_color',
                category: 'identity',
                title: 'Gold-red mythical name color',
                description: 'Your identity shifts to a mythic gold-red tone.'
            },
            {
                id: 'legend_frame',
                category: 'profile',
                title: 'Mythic frame',
                description: 'Unlock a top-tier mythic frame with heavier prestige.'
            },
            {
                id: 'legend_xp',
                category: 'progression',
                title: '40% XP boost',
                description: 'Push supported XP gains 40% higher than base.'
            },
            {
                id: 'legend_spotlight',
                category: 'room',
                title: 'Premium room spotlight styling',
                description: 'Earn superior spotlight visuals on room entry and profile presence.'
            },
            {
                id: 'legend_collectibles',
                category: 'access',
                title: 'Legend-exclusive collectible perks',
                description: 'Reach collectible and cosmetic perks reserved for Legend members.'
            }
        ],
        ui: {
            accent: '#FF9F42',
            gradient: ['#2B140B', '#7B1E12', '#F5A74C'],
            glow: '#FFB15C'
        }
    }),
    defineTier({
        tierId: 'supreme',
        level: 13,
        displayName: 'Supreme',
        shortLabel: 'Supreme',
        badgeAsset: 'badge_supreme',
        nameColorStyle: {
            token: 'rainbow',
            label: 'Rainbow',
            colors: ['#FF5EAA', '#FFB84C', '#55E48A', '#53B6FF', '#B775FF']
        },
        frameAsset: 'vip_frame_supreme_prism',
        monthlyBasePrice: 16999,
        xpBoostPercent: 50,
        monthlyCoinReward: 10500,
        giftingPerkLevel: 8,
        roomEntryEffect: 'supreme_prism_arrival',
        premiumEffects: ['supreme_animation_effects', 'ultimate_prestige_style'],
        featureFlags: {
            giftingPerkLevel: 8,
            strongestPremiumIdentity: true,
            supremeAnimationEffects: true,
            exclusivePremiumDrops: true,
            ultimatePrestigeStyling: true,
            supportPriority: 'concierge',
            extraDailyRewardCoins: 280
        },
        newlyUnlockedBenefits: [
            {
                id: 'supreme_badge',
                category: 'identity',
                title: 'Supreme badge',
                description: 'Carry the highest prestige badge available in the app.'
            },
            {
                id: 'supreme_name_color',
                category: 'identity',
                title: 'Rainbow name color',
                description: 'Your identity gains the app’s highest prestige rainbow styling.'
            },
            {
                id: 'supreme_frame',
                category: 'profile',
                title: 'Supreme ultra-premium frame',
                description: 'Use the strongest premium frame and identity shell available.'
            },
            {
                id: 'supreme_xp',
                category: 'progression',
                title: '50% XP boost',
                description: 'Unlock the maximum 50% XP bonus from supported sources.'
            },
            {
                id: 'supreme_effects',
                category: 'room',
                title: 'Exclusive Supreme animation and effects',
                description: 'Gain the strongest safe premium animations and arrival visuals.'
            },
            {
                id: 'supreme_drops',
                category: 'access',
                title: 'Exclusive premium drops and cosmetics',
                description: 'Unlock Supreme-only premium drops, cosmetics, and top-tier gifting perks.'
            }
        ],
        ui: {
            accent: '#FF7FD3',
            gradient: ['#241039', '#7330B8', '#FFB14C', '#59D6A7', '#5AB0FF'],
            glow: '#F2C7FF'
        }
    })
];

const VIP_TIER_BY_ID = VIP_MEMBERSHIP_TIERS.reduce((accumulator, tier) => {
    accumulator[tier.tierId] = tier;
    return accumulator;
}, {});

const VIP_TIER_BY_LEVEL = VIP_MEMBERSHIP_TIERS.reduce((accumulator, tier) => {
    accumulator[tier.level] = tier;
    return accumulator;
}, {});

const VIP_COMPARISON_ROWS = [
    { key: 'badgeAsset', label: 'Badge', type: 'text' },
    { key: 'nameColorStyle.label', label: 'Name Color', type: 'text' },
    { key: 'frameAsset', label: 'Profile Frame', type: 'text' },
    { key: 'xpBoostPercent', label: 'XP Boost', type: 'percent' },
    { key: 'monthlyCoinReward', label: 'Monthly Coins', type: 'coins' },
    { key: 'giftingPerkLevel', label: 'Gifting Perk', type: 'level' },
    { key: 'roomEntryEffect', label: 'Room Entry', type: 'text' },
    { key: 'featureFlags.extraDailyRewardCoins', label: 'Extra Daily Reward', type: 'coins' }
];

module.exports = {
    VIP_TIER_ORDER,
    VIP_PLAN_DEFINITIONS,
    VIP_MEMBERSHIP_TIERS,
    VIP_TIER_BY_ID,
    VIP_TIER_BY_LEVEL,
    VIP_COMPARISON_ROWS
};
