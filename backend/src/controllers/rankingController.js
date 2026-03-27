const rankingService = require('../services/rankingService');
const User = require('../models/User');

const VALID_PERIODS = ['daily', 'weekly', 'monthly', 'alltime'];

const enrichWithUserData = async (rankings) => {
    if (!rankings.length) return rankings;
    const ids = rankings.map(r => r.userId).filter(Boolean);
    const users = await User.find({ _id: { $in: ids } }).select('username avatar level vipLevel').lean();
    const map = Object.fromEntries(users.map(u => [u._id.toString(), u]));
    return rankings.map((r, idx) => {
        const u = map[r.userId?.toString()] || {};
        return { rank: idx + 1, ...r, username: r.username || u.username, avatar: r.avatar || u.avatar, level: r.level || u.level, vipLevel: r.vipLevel || u.vipLevel };
    });
};

exports.getGiftRankings = async (req, res, next) => {
    try {
        const { period = 'alltime', limit = 100, roomId } = req.query;
        if (!VALID_PERIODS.includes(period)) { const e = new Error('Invalid period'); e.status = 400; throw e; }
        const raw       = await rankingService.getRankings('gifts', period, parseInt(limit), roomId);
        const rankings  = await enrichWithUserData(raw);
        const userRank  = req.userId ? await rankingService.getUserRank(req.userId, 'gifts', period) : null;
        res.json({ rankings, userRank, period, total: rankings.length });
    } catch (error) { next(error); }
};

exports.getCharmRankings = async (req, res, next) => {
    try {
        const { period = 'alltime', limit = 100 } = req.query;
        if (!VALID_PERIODS.includes(period)) { const e = new Error('Invalid period'); e.status = 400; throw e; }
        const raw      = await rankingService.getRankings('charm', period, parseInt(limit));
        const rankings = await enrichWithUserData(raw);
        const userRank = req.userId ? await rankingService.getUserRank(req.userId, 'charm', period) : null;
        res.json({ rankings, userRank, period, total: rankings.length });
    } catch (error) { next(error); }
};

exports.getGameRankings = async (req, res, next) => {
    try {
        const { gameType } = req.params;
        const { period = 'alltime', limit = 100 } = req.query;
        const raw      = await rankingService.getRankings(`games:${gameType}`, period, parseInt(limit));
        const rankings = await enrichWithUserData(raw);
        const userRank = req.userId ? await rankingService.getUserRank(req.userId, `games:${gameType}`, period) : null;
        res.json({ rankings, userRank, period, gameType, total: rankings.length });
    } catch (error) { next(error); }
};

exports.getOverallRankings = async (req, res, next) => {
    try {
        const { limit = 100 } = req.query;
        // Overall = aggregate of gifts + charm scored by level + XP
        const users = await User.find({ isDeleted: { $ne: true } })
            .select('username avatar level xp vipLevel stats')
            .sort({ level: -1, xp: -1 })
            .limit(parseInt(limit))
            .lean();
        const rankings = users.map((u, i) => ({
            rank: i + 1, userId: u._id, username: u.username, avatar: u.avatar,
            level: u.level, vipLevel: u.vipLevel, xp: u.xp,
            score: (u.level * 1000) + (u.xp || 0) + ((u.stats?.giftsReceived || 0) * 10)
        }));
        res.json({ rankings, total: rankings.length });
    } catch (error) { next(error); }
};

exports.getWealthRankings = async (req, res, next) => {
    try {
        const { limit = 100 } = req.query;
        const users = await User.find({ isDeleted: { $ne: true } })
            .select('username avatar level vipLevel coins gems stats')
            .sort({ 'stats.totalSpent': -1, coins: -1 })
            .limit(parseInt(limit))
            .lean();
        const rankings = users.map((u, i) => ({
            rank: i + 1, userId: u._id, username: u.username, avatar: u.avatar,
            level: u.level, vipLevel: u.vipLevel,
            coins: u.coins, gems: u.gems, totalSpent: u.stats?.totalSpent || 0
        }));
        res.json({ rankings, total: rankings.length });
    } catch (error) { next(error); }
};

exports.getActiveRoomRankings = async (req, res, next) => {
    try {
        const Room = require('../models/Room');
        const rooms = await Room.find({ endedAt: null })
            .populate('hostId', 'username avatar level vipLevel')
            .sort({ onlineCount: -1 })
            .limit(20)
            .lean();
        res.json({ rankings: rooms.map((r, i) => ({ rank: i + 1, ...r })) });
    } catch (error) { next(error); }
};


