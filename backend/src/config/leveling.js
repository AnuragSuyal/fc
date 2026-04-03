const LEVEL_BADGE_TIERS = Object.freeze([
    {
        key: 'dark_red',
        minLevel: 100,
        label: 'Dark Red'
    },
    {
        key: 'yellow',
        minLevel: 80,
        label: 'Yellow'
    },
    {
        key: 'blue',
        minLevel: 40,
        label: 'Blue'
    },
    {
        key: 'parrot_green',
        minLevel: 20,
        label: 'Parrot Green'
    },
    {
        key: 'default',
        minLevel: 1,
        label: 'Default'
    }
]);

const LEVELING_CONFIG = Object.freeze({
    xpScale: Math.max(Number(process.env.LEVEL_XP_SCALE || 60), 10),
    maxLevel: Math.max(Number(process.env.LEVEL_MAX || 200), 100),
    badgeTiers: LEVEL_BADGE_TIERS
});

const SPEND_XP_CONFIG = Object.freeze({
    coinsPerXp: Math.max(Number(process.env.SPEND_XP_COINS_PER_POINT || 40), 10),
    gemsPerXp: Math.max(Number(process.env.SPEND_XP_GEMS_PER_POINT || 4), 1),
    minimumAward: 1,
    maximumAward: Math.max(Number(process.env.SPEND_XP_MAX_PER_AWARD || 250), 25)
});

const XP_SOURCE_DEFINITIONS = Object.freeze({
    daily_login: Object.freeze({
        key: 'daily_login',
        label: 'Daily Login',
        category: 'reward',
        enabled: true,
        defaultAmount: 18,
        maxAwardsPerWindow: 1,
        windowMs: 24 * 60 * 60 * 1000
    }),
    room_join: Object.freeze({
        key: 'room_join',
        label: 'Join Room',
        category: 'room',
        enabled: true,
        defaultAmount: 12,
        maxAwardsPerWindow: 8,
        windowMs: 24 * 60 * 60 * 1000
    }),
    room_heartbeat: Object.freeze({
        key: 'room_heartbeat',
        label: 'Room Heartbeat',
        category: 'room',
        enabled: true,
        defaultAmount: 2,
        cooldownMs: 28 * 1000,
        maxAwardsPerWindow: 180,
        windowMs: 24 * 60 * 60 * 1000
    }),
    gift_received: Object.freeze({
        key: 'gift_received',
        label: 'Gift Received',
        category: 'social',
        enabled: true,
        maxAwardsPerWindow: 80,
        windowMs: 24 * 60 * 60 * 1000
    }),
    quest_reward: Object.freeze({
        key: 'quest_reward',
        label: 'Quest Reward',
        category: 'reward',
        enabled: true
    }),
    friend_connection: Object.freeze({
        key: 'friend_connection',
        label: 'Friend Connection',
        category: 'social',
        enabled: true,
        defaultAmount: 16
    }),
    vip_purchase: Object.freeze({
        key: 'vip_purchase',
        label: 'VIP Purchase',
        category: 'premium',
        enabled: true,
        maxAwardsPerWindow: 10,
        windowMs: 24 * 60 * 60 * 1000
    }),
    profile_completed: Object.freeze({
        key: 'profile_completed',
        label: 'Profile Completed',
        category: 'profile',
        enabled: false,
        defaultAmount: 30
    }),
    room_hosting: Object.freeze({
        key: 'room_hosting',
        label: 'Room Hosting',
        category: 'room',
        enabled: false,
        defaultAmount: 20
    }),
    daily_task: Object.freeze({
        key: 'daily_task',
        label: 'Daily Task',
        category: 'reward',
        enabled: false,
        defaultAmount: 12
    }),
    event_participation: Object.freeze({
        key: 'event_participation',
        label: 'Event Participation',
        category: 'reward',
        enabled: false,
        defaultAmount: 18
    }),
    follower_gain: Object.freeze({
        key: 'follower_gain',
        label: 'Follower Gain',
        category: 'social',
        enabled: false,
        defaultAmount: 8
    })
});

module.exports = {
    LEVELING_CONFIG,
    LEVEL_BADGE_TIERS,
    SPEND_XP_CONFIG,
    XP_SOURCE_DEFINITIONS
};
