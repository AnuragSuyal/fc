const User = require('../models/User');
const Post = require('../models/Post');
const Message = require('../models/Message');
const { applyAvatarUpdate } = require('../utils/avatarUploadLimit');

const getResolvedUser = (identifier) => User.findByIdOrUid(identifier);
const INTRO_MESSAGE_LIMIT = 3;

const idsEqual = (left, right) =>
    !!left && !!right && left.toString() === right.toString();

const buildProfileStats = (user) => {
    const visitorCount = user.profileVisitors?.length || 0;
    const totalGames =
        (user.gameStats?.werewolf?.played || 0) +
        (user.gameStats?.drawing?.played || 0) +
        (user.gameStats?.karaoke?.played || 0) +
        (user.gameStats?.colorClash?.played || 0);

    const totalWins =
        (user.gameStats?.werewolf?.won || 0) +
        (user.gameStats?.drawing?.won || 0) +
        (user.gameStats?.karaoke?.won || 0) +
        (user.gameStats?.colorClash?.won || 0);

    const winRate = totalGames > 0 ? ((totalWins / totalGames) * 100).toFixed(1) : 0;

    return {
        totalGames,
        totalWins,
        winRate,
        visitorCount,
        friendCount: user.friends?.length || 0,
        followerCount: user.followers?.length || 0,
        followingCount: user.following?.length || 0,
        giftsSent: user.stats?.giftsSent || 0,
        giftsReceived: user.stats?.giftsReceived || 0
    };
};

const buildRealtimeProfileUser = (user) => ({
    id: user._id,
    uid: user.uid,
    username: user.username,
    avatar: user.avatar,
    coverPhoto: user.coverPhoto,
    bio: user.bio,
    region: user.region || 'Global',
    level: user.level,
    xp: user.xp,
    coins: user.coins,
    gems: user.gems,
    vipLevel: user.vipLevel,
    status: user.status,
    lastActive: user.status?.lastActive,
    gameStats: user.gameStats,
    badges: user.badges,
    stats: buildProfileStats(user)
});

const emitProfileRealtime = (req, user, event, payload = {}) => {
    const io = req.app.get('io');
    if (!io || !user?._id) return;

    const userId = user._id.toString();
    const basePayload = {
        userId,
        timestamp: new Date().toISOString(),
        ...payload
    };

    io.to(`user:${userId}`).emit(event, basePayload);
    io.to(`profile:${userId}`).emit(event, basePayload);
};

const buildRelationship = async ({ viewer, targetUser }) => {
    const base = {
        isSelf: false,
        isFriend: false,
        hasIncomingRequest: false,
        hasOutgoingRequest: false,
        canSendFriendRequest: false,
        canMessage: false,
        isBlocked: false,
        introMessageLimit: INTRO_MESSAGE_LIMIT,
        introMessagesUsed: 0,
        introMessagesRemaining: 0,
        requiresFriendshipForMore: false
    };

    if (!viewer || !targetUser) {
        return base;
    }

    if (idsEqual(viewer._id, targetUser._id)) {
        return {
            ...base,
            isSelf: true,
            canMessage: true,
            introMessagesRemaining: INTRO_MESSAGE_LIMIT
        };
    }

    const isFriend = (viewer.friends || []).some(id => idsEqual(id, targetUser._id));
    const hasIncomingRequest = (viewer.friendRequests || []).some(
        request => idsEqual(request.from, targetUser._id) && request.status === 'pending'
    );
    const hasOutgoingRequest = (targetUser.friendRequests || []).some(
        request => idsEqual(request.from, viewer._id) && request.status === 'pending'
    );
    const isBlocked = (viewer.blockedUsers || []).some(id => idsEqual(id, targetUser._id)) ||
        (targetUser.blockedUsers || []).some(id => idsEqual(id, viewer._id));
    const canSendFriendRequest = !isFriend &&
        !hasIncomingRequest &&
        !hasOutgoingRequest &&
        !isBlocked &&
        targetUser.settings?.privacy?.allowFriendRequests !== false;

    let introMessagesUsed = 0;
    if (!isFriend && !isBlocked) {
        introMessagesUsed = await Message.countDocuments({
            senderId: viewer._id,
            recipientId: targetUser._id,
            isDeleted: false,
            type: { $ne: 'system' }
        });
    }
    const introMessagesRemaining = isFriend
        ? INTRO_MESSAGE_LIMIT
        : Math.max(0, INTRO_MESSAGE_LIMIT - introMessagesUsed);

    return {
        isSelf: false,
        isFriend,
        hasIncomingRequest,
        hasOutgoingRequest,
        canSendFriendRequest,
        canMessage: !isBlocked && (isFriend || introMessagesRemaining > 0),
        isBlocked,
        introMessageLimit: INTRO_MESSAGE_LIMIT,
        introMessagesUsed,
        introMessagesRemaining,
        requiresFriendshipForMore: !isFriend && introMessagesRemaining <= 0
    };
};

const buildProfileResponse = async ({ user, viewerId, postsLimit = 20 }) => {
    const rawPosts = await Post.find({ userId: user._id, isDeleted: false })
        .sort({ createdAt: -1 })
        .limit(postsLimit)
        .populate('userId', 'username avatar level');

    const viewerIdString = viewerId?.toString?.() || '';
    const posts = rawPosts.map((post) => {
        const postObj = post.toObject();
        postObj.isLikedByUser = viewerIdString
            ? post.likes.some((like) => like.userId?.toString() === viewerIdString)
            : false;
        return postObj;
    });

    let viewer = null;
    if (viewerId) {
        viewer = idsEqual(user._id, viewerId)
            ? user
            : await User.findById(viewerId)
                .select('friends friendRequests blockedUsers');
    }

    return {
        user: {
            id: user._id,
            uid: user.uid,
            username: user.username,
            avatar: user.avatar,
            coverPhoto: user.coverPhoto,
            bio: user.bio,
            region: user.region || 'Global',
            level: user.level,
            xp: user.xp,
            coins: user.coins,
            gems: user.gems,
            vipLevel: user.vipLevel,
            status: user.status,
            lastActive: user.status?.lastActive,
            gameStats: user.gameStats,
            badges: user.badges,
            stats: buildProfileStats(user)
        },
        relationship: await buildRelationship({ viewer, targetUser: user }),
        posts
    };
};

// @desc    Get current user profile
exports.getMyProfile = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('uid username avatar coverPhoto bio region level xp coins gems vipLevel status lastActive gameStats badges profileVisitors friends followers following stats friendRequests blockedUsers settings')
            .populate('badges');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json(await buildProfileResponse({ user, viewerId: req.userId }));
    } catch (error) {
        next(error);
    }
};

// @desc    Get user profile by ID
exports.getProfile = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const user = await getResolvedUser(userId)
            .select('uid username avatar coverPhoto bio region level xp coins gems vipLevel status lastActive gameStats badges profileVisitors friends followers following stats friendRequests blockedUsers settings')
            .populate('badges');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json(await buildProfileResponse({ user, viewerId: req.userId }));
    } catch (error) {
        next(error);
    }
};

// @desc    Update profile
exports.updateProfile = async (req, res, next) => {
    try {
        const { bio, avatar, coverPhoto, region } = req.body;
        const user = await User.findById(req.userId);

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (bio !== undefined) user.bio = bio;
        if (avatar !== undefined) applyAvatarUpdate(user, avatar);
        if (coverPhoto !== undefined) user.coverPhoto = coverPhoto;
        if (region !== undefined) user.region = String(region).trim() || 'Global';

        await user.save();

        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.del(`cache:user:${req.userId}`);
        }

        emitProfileRealtime(req, user, 'profile:updated', {
            user: buildRealtimeProfileUser(user),
            fields: {
                bio: user.bio,
                avatar: user.avatar,
                coverPhoto: user.coverPhoto,
                region: user.region
            }
        });

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
        const visitorUser = await User.findById(req.userId)
            .select('uid username avatar level');

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${user._id.toString()}`).emit('profile:visitor', {
                userId: user._id.toString(),
                timestamp: new Date().toISOString(),
                visitorCount: user.profileVisitors.length,
                visitor: visitorUser
                    ? {
                        id: visitorUser._id,
                        uid: visitorUser.uid,
                        username: visitorUser.username,
                        avatar: visitorUser.avatar,
                        level: visitorUser.level
                    }
                    : null,
                message: req.body.message || null
            });
        }

        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

// @desc    Update game statistics
exports.updateGameStats = async (req, res, next) => {
    try {
        const { game, won } = req.body;
        const validGames = ['werewolf', 'drawing', 'karaoke', 'colorClash'];
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
        emitProfileRealtime(req, user, 'profile:stats_updated', {
            game,
            gameStats: user.gameStats[game],
            stats: buildProfileStats(user)
        });
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
        emitProfileRealtime(req, user, 'profile:badge_awarded', {
            badge: user.badges[user.badges.length - 1],
            user: buildRealtimeProfileUser(user)
        });
        res.json({ success: true, badge: user.badges[user.badges.length - 1] });
    } catch (error) {
        next(error);
    }
};
