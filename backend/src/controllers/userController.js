const User = require('../models/User');
const { applyAvatarUpdate } = require('../utils/avatarUploadLimit');

const cacheKeyForUser = (userId) => `cache:user:${userId}`;
const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const buildUserPayload = (user) => ({
    id: user._id,
    uid: user.uid,
    username: user.username,
    avatar: user.avatar,
    bio: user.bio,
    level: user.level,
    xp: user.xp,
    vipLevel: user.vipLevel,
    stats: user.stats || {},
    badges: user.badges || [],
    status: user.status || {}
});

const invalidateUserCache = async (redis, userId) => {
    if (!redis || !redis.isReady) return;
    await redis.del(cacheKeyForUser(userId));
};

// @desc    Get user profile by ID (cached)
exports.getUserById = async (req, res, next) => {
    try {
        const { id } = req.params;
        const redis = req.app.get('redis');

        if (redis && redis.isReady && /^[0-9a-fA-F]{24}$/.test(id)) {
            const cached = await redis.get(cacheKeyForUser(id));
            if (cached) {
                const payload = JSON.parse(cached);
                return res.json({ user: payload });
            }
        }

        const user = await User.findByIdOrUid(id)
            .select('uid username avatar bio level xp vipLevel stats badges status blockedUsers');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const currentUser = await User.findById(req.userId).select('blockedUsers');
        if (currentUser?.blockedUsers?.some((blockedId) => blockedId.toString() === user._id.toString())) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (user.blockedUsers?.some((uid) => uid.toString() === req.userId)) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const payload = buildUserPayload(user);
        const resolvedId = user._id.toString();

        if (redis && redis.isReady) {
            await redis.set(cacheKeyForUser(resolvedId), JSON.stringify(payload), { EX: 300 });
        }

        res.json({ user: payload });
    } catch (error) {
        next(error);
    }
};

// @desc    Update user profile
exports.updateUser = async (req, res, next) => {
    try {
        const { id } = req.params;
        if (id !== req.userId) {
            const error = new Error('Forbidden');
            error.status = 403;
            throw error;
        }

        const { username, bio, avatar, settings } = req.body;
        const user = await User.findById(id);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (username !== undefined) {
            const trimmed = String(username).trim();
            if (trimmed.length < 3 || trimmed.length > 20) {
                const error = new Error('Username must be between 3 and 20 characters');
                error.status = 400;
                throw error;
            }
            if (!/^[a-zA-Z0-9_]+$/.test(trimmed)) {
                const error = new Error('Username can only contain letters, numbers, and underscores');
                error.status = 400;
                throw error;
            }
            if (trimmed !== user.username) {
                const existing = await User.findOne({ username: trimmed, _id: { $ne: user._id } }).select('_id');
                if (existing) {
                    const error = new Error('Username already taken');
                    error.status = 409;
                    throw error;
                }
            }
            user.username = trimmed;
        }

        if (bio !== undefined) user.bio = bio;
        if (avatar !== undefined) applyAvatarUpdate(user, avatar);

        if (settings && typeof settings === 'object') {
            user.settings = { ...(user.settings || {}), ...settings };
            user.markModified('settings');
        }

        await user.save();

        const redis = req.app.get('redis');
        await invalidateUserCache(redis, id);

        res.json({ user: buildUserPayload(user) });
    } catch (error) {
        next(error);
    }
};

// @desc    Search users
exports.searchUsers = async (req, res, next) => {
    try {
        const { q, page = 1, limit = 20 } = req.query;
        const queryText = String(q || '').trim();
        const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
        const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);

        if (!queryText) {
            return res.json({ users: [], total: 0, page: parsedPage, hasMore: false });
        }

        const currentUser = await User.findById(req.userId).select('blockedUsers');
        const blockedIds = currentUser?.blockedUsers || [];
        const normalizedSearch = escapeRegex(queryText);

        const query = {
            _id: { $ne: req.userId, $nin: blockedIds },
            $or: [
                { username: { $regex: normalizedSearch, $options: 'i' } },
                { uid: { $regex: normalizedSearch } }
            ]
        };

        let users = await User.find(query)
            .select('uid username avatar level vipLevel stats badges status')
            .limit(parsedLimit + 1)
            .skip((parsedPage - 1) * parsedLimit);

        if (parsedPage === 1) {
            const exactUidMatch = await User.findOne({
                uid: queryText,
                _id: { $ne: req.userId, $nin: blockedIds }
            }).select('uid username avatar level vipLevel stats badges status');

            if (exactUidMatch) {
                users = [
                    exactUidMatch,
                    ...users.filter((user) => user._id.toString() !== exactUidMatch._id.toString())
                ];
            }
        }

        users = users.slice(0, parsedLimit);

        const total = await User.countDocuments(query);
        res.json({
            users,
            total,
            page: parsedPage,
            hasMore: (parsedPage * parsedLimit) < total
        });
    } catch (error) {
        next(error);
    }
};

exports.invalidateUserCache = invalidateUserCache;



