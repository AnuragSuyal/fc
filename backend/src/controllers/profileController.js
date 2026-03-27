const User = require('../models/User');
const Post = require('../models/Post');
const { applyAvatarUpdate } = require('../utils/avatarUploadLimit');

const getResolvedUser = (identifier) => User.findByIdOrUid(identifier);

// @desc    Get current user profile
exports.getMyProfile = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('uid username avatar coverPhoto bio level xp coins gems vipLevel status lastActive gameStats badges profileVisitors')
            .populate('badges');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const posts = await Post.find({ userId: req.userId, isDeleted: false })
            .sort({ createdAt: -1 })
            .limit(5)
            .populate('userId', 'username avatar');

        const visitorCount = user.profileVisitors?.length || 0;
        const totalGames =
            (user.gameStats?.werewolf?.played || 0) +
            (user.gameStats?.drawing?.played || 0) +
            (user.gameStats?.karaoke?.played || 0) +
            (user.gameStats?.uno?.played || 0);

        const totalWins =
            (user.gameStats?.werewolf?.won || 0) +
            (user.gameStats?.drawing?.won || 0) +
            (user.gameStats?.karaoke?.won || 0) +
            (user.gameStats?.uno?.won || 0);

        const winRate = totalGames > 0 ? ((totalWins / totalGames) * 100).toFixed(1) : 0;

        res.json({
            user: {
                id: user._id,
                uid: user.uid,
                username: user.username,
                avatar: user.avatar,
                coverPhoto: user.coverPhoto,
                bio: user.bio,
                level: user.level,
                xp: user.xp,
                coins: user.coins,
                gems: user.gems,
                vipLevel: user.vipLevel,
                status: user.status,
                lastActive: user.status?.lastActive,
                gameStats: user.gameStats,
                badges: user.badges,
                stats: { totalGames, totalWins, winRate, visitorCount }
            },
            posts
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get user profile by ID
exports.getProfile = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const user = await getResolvedUser(userId)
            .select('uid username avatar coverPhoto bio level xp coins gems vipLevel status lastActive gameStats badges profileVisitors')
            .populate('badges');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const posts = await Post.find({ userId: user._id, isDeleted: false })
            .sort({ createdAt: -1 })
            .limit(5)
            .populate('userId', 'username avatar');

        const visitorCount = user.profileVisitors?.length || 0;
        const totalGames = (user.gameStats?.werewolf?.played || 0) + (user.gameStats?.drawing?.played || 0) + (user.gameStats?.karaoke?.played || 0) + (user.gameStats?.uno?.played || 0);
        const totalWins = (user.gameStats?.werewolf?.won || 0) + (user.gameStats?.drawing?.won || 0) + (user.gameStats?.karaoke?.won || 0) + (user.gameStats?.uno?.won || 0);
        const winRate = totalGames > 0 ? ((totalWins / totalGames) * 100).toFixed(1) : 0;

        res.json({
            user: {
                id: user._id,
                uid: user.uid,
                username: user.username,
                avatar: user.avatar,
                coverPhoto: user.coverPhoto,
                bio: user.bio,
                level: user.level,
                xp: user.xp,
                coins: user.coins,
                gems: user.gems,
                vipLevel: user.vipLevel,
                status: user.status,
                lastActive: user.status?.lastActive,
                gameStats: user.gameStats,
                badges: user.badges,
                stats: { totalGames, totalWins, winRate, visitorCount }
            },
            posts
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Update profile
exports.updateProfile = async (req, res, next) => {
    try {
        const { bio, avatar, coverPhoto } = req.body;
        const user = await User.findById(req.userId);

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (bio !== undefined) user.bio = bio;
        if (avatar !== undefined) applyAvatarUpdate(user, avatar);
        if (coverPhoto !== undefined) user.coverPhoto = coverPhoto;

        await user.save();

        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.del(`cache:user:${req.userId}`);
        }

        res.json({ success: true, user: user.toJSON() });
    } catch (error) {
        next(error);
    }
};

// @desc    Get badges
exports.getBadges = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const user = await getResolvedUser(userId).select('badges');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        res.json(user.badges || []);
    } catch (error) {
        next(error);
    }
};

// @desc    Get game stats
exports.getGameStats = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const user = await getResolvedUser(userId).select('gameStats');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        res.json(user.gameStats || {});
    } catch (error) {
        next(error);
    }
};

// @desc    Get profile visitors
exports.getVisitors = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const { page = 1, limit = 20 } = req.query;

        const user = await getResolvedUser(userId)
            .populate({ path: 'profileVisitors.userId', select: 'uid username avatar level' });

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const visitors = user.profileVisitors || [];
        const sorted = visitors.sort((a, b) => b.visitedAt - a.visitedAt);
        const start = (parseInt(page) - 1) * parseInt(limit);
        const paginated = sorted.slice(start, start + parseInt(limit));

        res.json({ visitors: paginated, total: visitors.length, page: parseInt(page), limit: parseInt(limit) });
    } catch (error) {
        next(error);
    }
};

// @desc    Add a profile visitor
exports.addVisitor = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const user = await getResolvedUser(userId);

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (user._id.toString() === req.userId) {
            const error = new Error('Cannot visit your own profile');
            error.status = 400;
            throw error;
        }

        if (!user.profileVisitors) user.profileVisitors = [];

        const recentVisit = user.profileVisitors.find(v => v.userId.toString() === req.userId && (Date.now() - new Date(v.visitedAt).getTime()) < 3600000);

        if (recentVisit) {
            recentVisit.visitedAt = Date.now();
            if (req.body.message) recentVisit.message = req.body.message;
        } else {
            user.profileVisitors.unshift({ userId: req.userId, visitedAt: Date.now(), message: req.body.message || null });
            if (user.profileVisitors.length > 100) user.profileVisitors = user.profileVisitors.slice(0, 100);
        }

        await user.save();
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

// @desc    Update game statistics
exports.updateGameStats = async (req, res, next) => {
    try {
        const { game, won } = req.body;
        const validGames = ['werewolf', 'drawing', 'karaoke', 'uno'];
        if (!validGames.includes(game)) {
            const error = new Error('Invalid game');
            error.status = 400;
            throw error;
        }

        const user = await User.findById(req.userId);
        if (!user.gameStats) user.gameStats = {};
        if (!user.gameStats[game]) user.gameStats[game] = { played: 0, won: 0, level: 1 };

        user.gameStats[game].played += 1;
        if (won) user.gameStats[game].won += 1;

        const wins = user.gameStats[game].won;
        user.gameStats[game].level = Math.floor(wins / 10) + 1;

        await user.save();
        res.json({ success: true, gameStats: user.gameStats[game] });
    } catch (error) {
        next(error);
    }
};

// @desc    Add badge
exports.addBadge = async (req, res, next) => {
    try {
        const { badgeId, name, description, icon, rarity } = req.body;
        const user = await User.findById(req.userId);
        if (!user.badges) user.badges = [];

        const exists = user.badges.some(b => b.id === badgeId);
        if (exists) {
            const error = new Error('Badge already earned');
            error.status = 400;
            throw error;
        }

        user.badges.push({ id: badgeId, name, description, icon, rarity, earnedAt: Date.now() });
        await user.save();
        res.json({ success: true, badge: user.badges[user.badges.length - 1] });
    } catch (error) {
        next(error);
    }
};




