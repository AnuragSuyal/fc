// VIP Levels configuration - 12 tiers with benefits
const vipLevels = [
    {
        level: 0,
        name: 'Free',
        benefits: [],
        minSpend: 0,
        color: '#808080',
        icon: 'ðŸ†“'
    },
    {
        level: 1,
        name: 'VIP 1',
        description: 'Bronze Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name', description: 'Your name appears in gold' },
            { id: 'chat_backup', name: 'Chat Backup', description: 'Messages sync across devices' }
        ],
        minSpend: 0, // First purchase of any amount
        price: 499, // $4.99 per month
        annualPrice: 4999, // $49.99 per year
        color: '#CD7F32',
        icon: 'ðŸ¥‰',
        coinBonus: 100 // Daily coin bonus
    },
    {
        level: 2,
        name: 'VIP 2',
        description: 'Bronze+ Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect', description: 'Special animation when joining rooms' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble', description: 'VIP exclusive chat bubble' }
        ],
        minSpend: 500, // $5 spent
        price: 499, // $4.99 per month
        annualPrice: 4999,
        color: '#CD7F32',
        icon: 'ðŸ¥‰',
        coinBonus: 150
    },
    {
        level: 3,
        name: 'VIP 3',
        description: 'Silver Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts', description: 'Access to VIP-only gifts' }
        ],
        minSpend: 1500, // $15 spent
        price: 499,
        annualPrice: 4999,
        color: '#C0C0C0',
        icon: 'ðŸ¥ˆ',
        coinBonus: 200
    },
    {
        level: 4,
        name: 'VIP 4',
        description: 'Silver+ Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends', description: 'Higher friend limit (200)' }
        ],
        minSpend: 3000, // $30 spent
        price: 499,
        annualPrice: 4999,
        color: '#C0C0C0',
        icon: 'ðŸ¥ˆ',
        coinBonus: 250
    },
    {
        level: 5,
        name: 'VIP 5',
        description: 'Gold Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce', description: 'Make announcements to all users' },
            { id: 'broadcast', name: 'Broadcast Messages', description: 'Send messages to all friends' }
        ],
        minSpend: 6000, // $60 spent
        price: 999, // $9.99 per month
        annualPrice: 9999, // $99.99 per year
        color: '#FFD700',
        icon: 'ðŸ¥‡',
        coinBonus: 350
    },
    {
        level: 6,
        name: 'VIP 6',
        description: 'Gold+ Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame', description: 'Moving frame around avatar' }
        ],
        minSpend: 10000, // $100 spent
        price: 999,
        annualPrice: 9999,
        color: '#FFD700',
        icon: 'ðŸ¥‡',
        coinBonus: 450
    },
    {
        level: 7,
        name: 'VIP 7',
        description: 'Platinum Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title', description: 'Custom title under username' }
        ],
        minSpend: 15000, // $150 spent
        price: 999,
        annualPrice: 9999,
        color: '#E5E4E2',
        icon: 'ðŸ’Ž',
        coinBonus: 550
    },
    {
        level: 8,
        name: 'VIP 8',
        description: 'Platinum+ Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title' },
            { id: 'floating_chat', name: 'Floating Chat', description: 'Chat messages float in room' }
        ],
        minSpend: 25000, // $250 spent
        price: 999,
        annualPrice: 9999,
        color: '#E5E4E2',
        icon: 'ðŸ’Ž',
        coinBonus: 650
    },
    {
        level: 9,
        name: 'VIP 9',
        description: 'Diamond Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title' },
            { id: 'floating_chat', name: 'Floating Chat' },
            { id: 'custom_gifts', name: 'Create Custom Gifts', description: 'Design your own gifts' }
        ],
        minSpend: 40000, // $400 spent
        price: 1999, // $19.99 per month
        annualPrice: 19999, // $199.99 per year
        color: '#B9F2FF',
        icon: 'ðŸ’ ',
        coinBonus: 800
    },
    {
        level: 10,
        name: 'VIP 10',
        description: 'Diamond+ Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title' },
            { id: 'floating_chat', name: 'Floating Chat' },
            { id: 'custom_gifts', name: 'Create Custom Gifts' },
            { id: 'custom_frame', name: 'Custom Profile Frame', description: 'Upload your own frame' }
        ],
        minSpend: 60000, // $600 spent
        price: 1999,
        annualPrice: 19999,
        color: '#B9F2FF',
        icon: 'ðŸ’ ',
        coinBonus: 1000
    },
    {
        level: 11,
        name: 'VIP 11',
        description: 'Elite Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title' },
            { id: 'floating_chat', name: 'Floating Chat' },
            { id: 'custom_gifts', name: 'Create Custom Gifts' },
            { id: 'custom_frame', name: 'Custom Profile Frame' },
            { id: 'anti_kick', name: 'Anti-Kick', description: 'Cannot be kicked from rooms' },
            { id: 'anti_leave', name: 'Anti-Leave', description: 'Mic stays on when leaving' }
        ],
        minSpend: 85000, // $850 spent
        price: 1999,
        annualPrice: 19999,
        color: '#FFD700',
        icon: 'ðŸ‘‘',
        coinBonus: 1250
    },
    {
        level: 12,
        name: 'VIP 12',
        description: 'Legendary Member',
        benefits: [
            { id: 'colored_name', name: 'Colored Name' },
            { id: 'chat_backup', name: 'Chat Backup' },
            { id: 'entrance_effect', name: 'Entrance Effect' },
            { id: 'chat_bubble', name: 'Custom Chat Bubble' },
            { id: 'exclusive_gifts', name: 'Exclusive Gifts' },
            { id: 'enhanced_friends', name: 'Enhanced Friends' },
            { id: 'global_announce', name: 'Global Announce' },
            { id: 'broadcast', name: 'Broadcast Messages' },
            { id: 'animated_frame', name: 'Animated Profile Frame' },
            { id: 'special_title', name: 'Special Title' },
            { id: 'floating_chat', name: 'Floating Chat' },
            { id: 'custom_gifts', name: 'Create Custom Gifts' },
            { id: 'custom_frame', name: 'Custom Profile Frame' },
            { id: 'anti_kick', name: 'Anti-Kick' },
            { id: 'anti_leave', name: 'Anti-Leave' },
            { id: 'personal_support', name: 'Personal Support', description: 'Dedicated support agent' },
            { id: 'all_previous', name: 'All Previous Benefits' }
        ],
        minSpend: 120000, // $1200 spent
        price: 1999,
        annualPrice: 19999,
        color: '#FF1493',
        icon: 'ðŸŒŸ',
        coinBonus: 1500
    }
];

module.exports = vipLevels;






