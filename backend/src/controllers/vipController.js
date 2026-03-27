const User        = require('../models/User');
const Transaction = require('../models/Transaction');

// Full VIP tier definition
const VIP_TIERS = [
    {
        level: 1, name: 'VIP I', price: 499, annualPrice: 4990,
        coinBonus: 5, dailyCoins: 100, color: '#A0AEC0',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+100 bonus coins per day' },
            { id: 'chat_colors',  name: 'Chat Colors',      description: 'Unlock colored chat text' },
            { id: 'vip_badge',    name: 'VIP Badge',        description: 'Display VIP badge on profile' }
        ]
    },
    {
        level: 2, name: 'VIP II', price: 499, annualPrice: 4990,
        coinBonus: 8, dailyCoins: 150, color: '#68D391',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+150 bonus coins per day' },
            { id: 'chat_colors',  name: 'Chat Colors',      description: 'More chat color options' },
            { id: 'vip_frame',    name: 'VIP Avatar Frame', description: 'Exclusive avatar border' }
        ]
    },
    {
        level: 3, name: 'VIP III', price: 499, annualPrice: 4990,
        coinBonus: 10, dailyCoins: 200, color: '#63B3ED',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+200 bonus coins per day' },
            { id: 'mic_priority', name: 'Mic Priority',     description: 'Priority speaker seat access' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '10% extra coins on gifts received' }
        ]
    },
    {
        level: 4, name: 'VIP IV', price: 499, annualPrice: 4990,
        coinBonus: 12, dailyCoins: 250, color: '#B794F4',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+250 bonus coins per day' },
            { id: 'room_theme',   name: 'Room Themes',      description: 'Unlock exclusive room backgrounds' },
            { id: 'profile_visit_alert', name: 'Visitor Alerts', description: 'See who visited your profile' }
        ]
    },
    {
        level: 5, name: 'VIP V', price: 999, annualPrice: 9990,
        coinBonus: 15, dailyCoins: 350, color: '#F6AD55',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+350 bonus coins per day' },
            { id: 'super_gift',   name: 'Super Gifts',      description: 'Unlock luxury gift catalog' },
            { id: 'custom_enter', name: 'Custom Entrance',  description: 'Animated room entrance effect' }
        ]
    },
    {
        level: 6, name: 'VIP VI', price: 999, annualPrice: 9990,
        coinBonus: 18, dailyCoins: 450, color: '#FC8181',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+450 bonus coins per day' },
            { id: 'co_host',      name: 'Co-Host Rights',   description: 'Auto co-host in partner rooms' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '15% extra coins on gifts received' }
        ]
    },
    {
        level: 7, name: 'VIP VII', price: 999, annualPrice: 9990,
        coinBonus: 22, dailyCoins: 600, color: '#F687B3',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+600 bonus coins per day' },
            { id: 'legend_gifts', name: 'Legendary Gifts',  description: 'Access all legendary gifts' },
            { id: 'vip_room',     name: 'VIP Room Access',  description: 'Enter VIP-only rooms' }
        ]
    },
    {
        level: 8, name: 'VIP VIII', price: 999, annualPrice: 9990,
        coinBonus: 28, dailyCoins: 800, color: '#76E4F7',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+800 bonus coins per day' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '20% extra coins on gifts received' },
            { id: 'name_color',   name: 'Custom Name Color','description': 'Gold username color in all rooms' }
        ]
    },
    {
        level: 9, name: 'VIP IX', price: 1999, annualPrice: 19990,
        coinBonus: 35, dailyCoins: 1200, color: '#FAF089',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+1200 bonus coins per day' },
            { id: 'instant_seat', name: 'Instant Seat',     description: 'Reserve speaker seat instantly' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '25% extra coins on gifts received' }
        ]
    },
    {
        level: 10, name: 'VIP X', price: 1999, annualPrice: 19990,
        coinBonus: 45, dailyCoins: 1800, color: '#FBD38D',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+1800 bonus coins per day' },
            { id: 'rank_boost',   name: 'Rank Boost',       description: '2× ranking score multiplier' },
            { id: 'exclusive_bg', name: 'Exclusive BG',     description: 'Ultra-rare room backgrounds' }
        ]
    },
    {
        level: 11, name: 'Diamond', price: 1999, annualPrice: 19990,
        coinBonus: 60, dailyCoins: 2500, color: '#90CDF4',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+2500 bonus coins per day' },
            { id: 'diamond_badge','name': 'Diamond Badge',  description: 'Diamond crown on all rooms' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '30% extra coins on gifts received' }
        ]
    },
    {
        level: 12, name: 'Legend', price: 1999, annualPrice: 19990,
        coinBonus: 80, dailyCoins: 4000, color: '#FEB2B2',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+4000 bonus coins per day' },
            { id: 'global_shout', name: 'Global Shout',     description: '1× global announcement per month' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '40% extra coins on gifts received' }
        ]
    },
    {
        level: 13, name: 'Supreme', price: 1999, annualPrice: 19990,
        coinBonus: 100, dailyCoins: 6000, color: '#E9D8FD',
        benefits: [
            { id: 'daily_coins',  name: 'Daily Coins',      description: '+6000 bonus coins per day' },
            { id: 'supreme_badge','name': 'Supreme Badge',  description: 'Supreme halo + name animation' },
            { id: 'gift_bonus',   name: 'Gift Bonus',       description: '50% extra coins on gifts received' },
            { id: 'all_access',   name: 'All Access',       description: 'Unlimited access to all features' }
        ]
    }
];

exports.getVipLevels = (req, res) => res.json(VIP_TIERS);

exports.getVipStatus = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId).select('vipLevel vipExpiry coins gems username');
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        const currentLevel = VIP_TIERS.find(t => t.level === (user.vipLevel || 0)) || null;
        const nextLevel    = VIP_TIERS.find(t => t.level === (user.vipLevel || 0) + 1) || null;

        res.json({
            vipLevel:     user.vipLevel || 0,
            currentLevel: currentLevel  || {
                level: 0,
                name: 'Free',
                description: 'Upgrade to unlock premium member perks.',
                benefits: [],
                coinBonus: 0,
                dailyCoins: 0,
                color: '#64748B',
                icon: 'VIP'
            },
            nextLevel,
            expiry:       user.vipExpiry,
            isActive:     user.vipLevel > 0 && (!user.vipExpiry || user.vipExpiry > new Date()),
            progress:     nextLevel ? Math.min(((user.vipLevel || 0) / nextLevel.level) * 100, 100) : 100,
            totalSpent:   0
        });
    } catch (error) { next(error); }
};

exports.purchaseVip = async (req, res, next) => {
    try {
        const { level, period = 'monthly' } = req.body;
        const tier = VIP_TIERS.find(t => t.level === parseInt(level));
        if (!tier) { const e = new Error('Invalid VIP level'); e.status = 400; throw e; }

        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        const durationMs = period === 'annual' ? 365 * 24 * 3600 * 1000 : 30 * 24 * 3600 * 1000;
        const newExpiry  = new Date(Date.now() + durationMs);

        user.vipLevel   = parseInt(level);
        user.vipExpiry  = newExpiry;
        await user.save();

        // Record transaction
        const transaction = new Transaction({
            userId: user._id,
            type:   'vip_purchase',
            amount: { coins: 0, gems: 0 },
            balanceBefore: { coins: user.coins, gems: user.gems },
            balanceAfter:  { coins: user.coins, gems: user.gems },
            description:   `VIP ${tier.name} (${period}) activated`,
            status: 'completed', completedAt: new Date()
        });
        await transaction.save();

        // Notify via socket
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${user._id}`).emit('vip_activated', {
                vipLevel: user.vipLevel, tierName: tier.name, expiry: newExpiry
            });
        }

        res.json({
            success:  true,
            message:  `${tier.name} activated!`,
            vipLevel: user.vipLevel,
            tier,
            expiry:   newExpiry
        });
    } catch (error) { next(error); }
};

exports.cancelVip = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        // In production you'd cancel Stripe subscription here
        res.json({ success: true, message: 'VIP auto-renewal cancelled. Benefits remain until expiry.', expiry: user.vipExpiry });
    } catch (error) { next(error); }
};

// @desc    Claim VIP daily coin bonus
exports.claimVipDailyBonus = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user || !user.vipLevel) { const e = new Error('VIP required'); e.status = 403; throw e; }
        if (user.vipExpiry && user.vipExpiry < new Date()) { const e = new Error('VIP expired'); e.status = 403; throw e; }

        const tier = VIP_TIERS.find(t => t.level === user.vipLevel);
        if (!tier) { const e = new Error('Tier not found'); e.status = 500; throw e; }

        const today = new Date(); today.setHours(0,0,0,0);
        if (user.lastVipDailyBonus) {
            const last = new Date(user.lastVipDailyBonus); last.setHours(0,0,0,0);
            if (last.getTime() === today.getTime()) {
                return res.json({ success: true, alreadyClaimed: true, dailyCoins: tier.dailyCoins });
            }
        }

        const balanceBefore = { coins: user.coins, gems: user.gems };
        user.coins += tier.dailyCoins;
        user.lastVipDailyBonus = new Date();
        await user.save();

        const txn = new Transaction({
            userId: user._id, type: 'vip_daily_bonus',
            amount: { coins: tier.dailyCoins },
            balanceBefore, balanceAfter: { coins: user.coins, gems: user.gems },
            description: `VIP ${tier.name} daily bonus`, status: 'completed', completedAt: new Date()
        });
        await txn.save();

        const io = req.app.get('io');
        if (io) io.to(`user:${user._id}`).emit('balance_update', { coins: user.coins, gems: user.gems });

        res.json({ success: true, dailyCoins: tier.dailyCoins, newBalance: { coins: user.coins, gems: user.gems } });
    } catch (error) { next(error); }
};

