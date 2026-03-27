const User        = require('../models/User');
const Transaction = require('../models/Transaction');

// Quest definitions (per-day refresh)
const QUEST_TEMPLATES = [
    { id: 'send_message',  title: 'Send 1 message',   description: 'Send a message in any room or DM.',    type: 'daily', target: 1,  reward: { coins: 100,  xp: 10 } },
    { id: 'join_room',     title: 'Join 1 room',       description: 'Join any voice room.',                 type: 'daily', target: 1,  reward: { coins: 150,  xp: 15 } },
    { id: 'send_gift',     title: 'Send 1 gift',       description: 'Send a gift to any user.',             type: 'daily', target: 1,  reward: { coins: 200,  gems: 2, xp: 20 } },
    { id: 'room_heartbeat',title: 'Stay 5 min in room',description: 'Spend 5 minutes in any room.',         type: 'daily', target: 5,  reward: { coins: 250,  xp: 25 } },
    { id: 'post_feed',     title: 'Create a post',     description: 'Share something on your feed.',        type: 'daily', target: 1,  reward: { coins: 120,  xp: 12 } },
    { id: 'add_friend',    title: 'Accept a friend',   description: 'Accept a friend request.',             type: 'daily', target: 1,  reward: { coins: 180,  xp: 18 } },
    { id: 'weekly_gift',   title: 'Send 10 gifts',     description: 'Send gifts to users this week.',       type: 'weekly',target: 10, reward: { coins: 1500, gems: 10, xp: 100 } },
    { id: 'weekly_rooms',  title: 'Visit 5 rooms',     description: 'Join 5 different rooms this week.',    type: 'weekly',target: 5,  reward: { coins: 1000, xp: 80 } }
];

const getQuestKey   = (userId, type) => `quests:${userId}:${type}:${new Date().toISOString().slice(0, type === 'daily' ? 10 : 7)}`;

const getOrCreateQuests = async (redis, userId) => {
    const dailyKey  = getQuestKey(userId, 'daily');
    const weeklyKey = getQuestKey(userId, 'weekly');

    const buildSet = (type) => {
        const now = new Date();
        const expiresAt = type === 'daily'
            ? new Date(new Date().setHours(23, 59, 59, 999))
            : new Date(now.getTime() + 7 * 24 * 3600 * 1000);
        return QUEST_TEMPLATES.filter(q => q.type === type).map(t => ({
            questId: `${userId}-${t.id}-${now.toISOString().slice(0, type === 'daily' ? 10 : 7)}`,
            title: t.title, description: t.description, type: t.type,
            target: t.target, progress: 0, completed: false, claimed: false,
            reward: t.reward, templateId: t.id, startedAt: now, expiresAt
        }));
    };

    let daily  = [];
    let weekly = [];

    if (redis && redis.isReady) {
        const dRaw = await redis.get(dailyKey);
        const wRaw = await redis.get(weeklyKey);
        if (dRaw) daily  = JSON.parse(dRaw);
        else {
            daily = buildSet('daily');
            await redis.set(dailyKey,  JSON.stringify(daily),  { EX: 86400 });
        }
        if (wRaw) weekly = JSON.parse(wRaw);
        else {
            weekly = buildSet('weekly');
            await redis.set(weeklyKey, JSON.stringify(weekly), { EX: 7 * 86400 });
        }
    } else {
        daily  = buildSet('daily');
        weekly = buildSet('weekly');
    }

    return { daily, weekly };
};

const saveQuests = async (redis, userId, type, quests) => {
    if (!redis || !redis.isReady) return;
    const key = getQuestKey(userId, type);
    const ttl = type === 'daily' ? 86400 : 7 * 86400;
    await redis.set(key, JSON.stringify(quests), { EX: ttl });
};

// ── Endpoints ────────────────────────────────────────────────────────────────

exports.claimDailyReward = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        const today = new Date(); today.setHours(0, 0, 0, 0);
        if (user.lastDailyReward) {
            const last = new Date(user.lastDailyReward); last.setHours(0, 0, 0, 0);
            if (last.getTime() === today.getTime()) {
                return res.json({ success: true, alreadyClaimed: true, streak: user.loginStreak || 0, day: user.loginStreak || 1, coins: 0, message: 'Already claimed today' });
            }
        }

        const streakBonus  = Math.min((user.loginStreak || 0) * 10, 200);
        const vipBonus     = user.vipLevel > 0 ? (user.vipLevel * 115) + 20 : 0;
        const totalCoins   = 100 + streakBonus + vipBonus;
        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };

        user.coins         = (user.coins || 0) + totalCoins;
        user.lastDailyReward = new Date();
        user.loginStreak   = (user.loginStreak || 0) + 1;
        if (user.loginStreak > (user.longestStreak || 0)) user.longestStreak = user.loginStreak;
        await user.save();

        await Transaction.create({
            userId: user._id, type: 'daily_bonus', amount: { coins: totalCoins },
            balanceBefore, balanceAfter: { coins: user.coins, gems: user.gems },
            description: `Daily login reward (Day ${user.loginStreak})`, status: 'completed', completedAt: new Date()
        });

        const io = req.app.get('io');
        if (io) io.to(`user:${user._id}`).emit('balance_update', { coins: user.coins, gems: user.gems });

        // Auto-progress daily quests
        const redis = req.app.get('redis');
        exports._progressQuest(redis, req.userId, 'join_room', 0).catch(() => {});

        res.json({ success: true, reward: totalCoins, coins: totalCoins, newBalance: { coins: user.coins, gems: user.gems }, streak: user.loginStreak, day: user.loginStreak, message: `Day ${user.loginStreak} reward claimed!` });
    } catch (error) { next(error); }
};

exports.getUserStats = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        res.json({
            coins: user.coins || 0, gems: user.gems || 0,
            level: user.level || 1, xp: user.xp || 0,
            vipLevel: user.vipLevel || 0,
            loginStreak: user.loginStreak || 0,
            longestStreak: user.longestStreak || 0
        });
    } catch (error) { next(error); }
};

exports.getBalance = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId).select('coins gems tickets vipLevel');
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        res.json({ coins: user.coins || 0, gems: user.gems || 0, tickets: user.tickets || 0, vipLevel: user.vipLevel || 0 });
    } catch (error) { next(error); }
};

exports.getDailyQuests = async (req, res, next) => {
    try {
        const redis = req.app.get('redis');
        const { daily, weekly } = await getOrCreateQuests(redis, req.userId);
        const type = String(req.query?.type || '').toLowerCase();

        if (type === 'daily') {
            return res.json(daily);
        }

        if (type === 'weekly') {
            return res.json(weekly);
        }

        res.json([...daily, ...weekly]);
    } catch (error) { next(error); }
};

exports.updateQuestProgress = async (req, res, next) => {
    try {
        const { questId, increment = 1, templateId } = req.body;
        const redis = req.app.get('redis');
        const { daily, weekly } = await getOrCreateQuests(redis, req.userId);

        let updated = false;
        const updateList = (list, type) => {
            const q = list.find(x => x.questId === questId || x.templateId === templateId);
            if (!q || q.completed) return list;
            q.progress = Math.min(q.progress + Number(increment), q.target);
            if (q.progress >= q.target) { q.completed = true; q.completedAt = new Date(); }
            updated = true;
            saveQuests(redis, req.userId, type, list).catch(() => {});
            return list;
        };
        updateList(daily, 'daily');
        updateList(weekly, 'weekly');

        if (!updated) return res.json({ success: false, message: 'Quest not found or already completed' });
        const quest = [...daily, ...weekly].find(x => x.questId === questId || x.templateId === templateId);
        res.json({ success: true, questId: quest.questId, progress: quest.progress, completed: quest.completed });
    } catch (error) { next(error); }
};

exports.claimQuestReward = async (req, res, next) => {
    try {
        const { questId } = req.body;
        const redis = req.app.get('redis');
        const { daily, weekly } = await getOrCreateQuests(redis, req.userId);

        const allQuests = [...daily, ...weekly];
        const quest = allQuests.find(q => q.questId === questId);
        if (!quest) { const e = new Error('Quest not found'); e.status = 404; throw e; }
        if (!quest.completed) { const e = new Error('Quest not completed'); e.status = 400; throw e; }
        if (quest.claimed)   return res.json({ success: true, alreadyClaimed: true, rewards: quest.reward });

        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        const { coins = 0, gems = 0, xp: xpReward = 0 } = quest.reward;
        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };
        user.coins = (user.coins || 0) + coins;
        user.gems  = (user.gems  || 0) + gems;
        user.xp    = (user.xp   || 0) + xpReward;
        await user.save();

        await Transaction.create({
            userId: user._id, type: 'quest_reward', amount: { coins, gems },
            balanceBefore, balanceAfter: { coins: user.coins, gems: user.gems },
            description: `Quest reward: ${quest.title}`, status: 'completed', completedAt: new Date()
        });

        quest.claimed = true;
        const type = quest.type;
        if (type === 'daily') { const idx = daily.findIndex(q => q.questId === questId); if (idx !== -1) { daily[idx] = quest; await saveQuests(redis, req.userId, 'daily', daily); } }
        else { const idx = weekly.findIndex(q => q.questId === questId); if (idx !== -1) { weekly[idx] = quest; await saveQuests(redis, req.userId, 'weekly', weekly); } }

        const io = req.app.get('io');
        if (io) io.to(`user:${user._id}`).emit('balance_update', { coins: user.coins, gems: user.gems });

        res.json({ success: true, rewards: quest.reward, newBalance: { coins: user.coins, gems: user.gems } });
    } catch (error) { next(error); }
};

// Coin/gem conversion rates
exports.getConversionRates = (_req, res) => {
    res.json({
        coinsToGems: { rate: 100, description: '100 coins = 1 gem', min: 100 },
        gemsToCoins: { rate: 80, description: '1 gem = 80 coins', min: 1 },
        message: 'Coins can be converted to gems at 100:1. Gems to coins at 1:80 (20% fee applies).'
    });
};

// Internal helper for quest auto-progress
exports._progressQuest = async (redis, userId, templateId, increment = 1) => {
    if (!redis || !redis.isReady) return;
    try {
        const { daily, weekly } = await getOrCreateQuests(redis, userId);
        const type = QUEST_TEMPLATES.find(t => t.id === templateId)?.type || 'daily';
        const list = type === 'daily' ? daily : weekly;
        const q = list.find(x => x.templateId === templateId);
        if (!q || q.completed) return;
        q.progress = Math.min(q.progress + increment, q.target);
        if (q.progress >= q.target) { q.completed = true; q.completedAt = new Date(); }
        await saveQuests(redis, userId, type, list);
    } catch (_) {}
};

exports.getTransactions = async (req, res, next) => {
    try {
        const { page = 1, limit = 20, type } = req.query;
        const query = { userId: req.userId };
        if (type) query.type = type;
        const transactions = await Transaction.find(query)
            .sort({ createdAt: -1 }).limit(parseInt(limit)).skip((parseInt(page)-1)*parseInt(limit));
        const total = await Transaction.countDocuments(query);
        res.json({ transactions, pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total/parseInt(limit)) } });
    } catch (error) { next(error); }
};

exports.purchase = async (req, res, next) => {
    try {
        const { productId } = req.body;
        const packs = {
            'coins_small':1000,'coins_medium':5000,'coins_large':12000,'coins_xl':25000,'coins_xxl':60000,'coins_legendary':150000,
            'gems_small':100,'gems_medium':500,'gems_large':1200,'gems_xl':3000,'gems_xxl':8000
        };
        const amount = packs[productId];
        if (!amount) { const e = new Error('Invalid product'); e.status = 400; throw e; }
        const isGems = productId.startsWith('gems_');
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };
        if (isGems) user.gems = (user.gems || 0) + amount;
        else        user.coins = (user.coins || 0) + amount;
        await user.save();
        await Transaction.create({
            userId: user._id, type: isGems ? 'purchase_gems' : 'purchase_coins',
            amount: isGems ? { gems: amount } : { coins: amount },
            balanceBefore, balanceAfter: { coins: user.coins, gems: user.gems },
            reference: { productId }, paymentMethod: 'mock', status: 'completed', completedAt: new Date()
        });
        const io = req.app.get('io');
        if (io) io.to(`user:${user._id}`).emit('balance_update', { coins: user.coins, gems: user.gems });
        res.json({ newBalance: { coins: user.coins, gems: user.gems } });
    } catch (error) { next(error); }
};

