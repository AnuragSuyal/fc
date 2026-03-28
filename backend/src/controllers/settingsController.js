const User = require('../models/User');
const { applyAvatarUpdate, getAvatarUploadStats } = require('../utils/avatarUploadLimit');

const emitProfileUpdated = (req, user) => {
    const io = req.app.get('io');
    if (!io || !user?._id) return;

    const userId = user._id.toString();
    const payload = {
        userId,
        timestamp: new Date().toISOString(),
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
            status: user.status
        }
    };

    io.to(`user:${userId}`).emit('profile:updated', payload);
    io.to(`profile:${userId}`).emit('profile:updated', payload);
};

const defaultSettings = {
    notifications: {
        friendOnline: true,
        messages: true,
        gifts: true,
        gameInvites: true,
        eventReminders: false,
        sound: true,
        vibrate: true
    },
    privacy: {
        showOnline: true,
        showActivity: true,
        allowFriendRequests: true,
        showLocation: false
    },
    quietHours: {
        enabled: false,
        start: '22:00',
        end: '08:00'
    },
    language: 'en',
    currency: 'USD'
};

// @desc    Get user settings
exports.getSettings = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('settings username avatar coverPhoto bio region avatarUploadHistory');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json({
            username: user.username,
            avatar: user.avatar,
            coverPhoto: user.coverPhoto,
            bio: user.bio || '',
            region: user.region || 'Global',
            avatarUploadsRemainingToday: getAvatarUploadStats(user).uploadsRemainingToday,
            settings: user.settings || defaultSettings
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Update notification settings
exports.updateNotifications = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!user.settings) user.settings = JSON.parse(JSON.stringify(defaultSettings));
        Object.assign(user.settings.notifications, req.body);
        user.markModified('settings.notifications');
        await user.save();

        res.json({ success: true, notifications: user.settings.notifications });
    } catch (error) {
        next(error);
    }
};

// @desc    Update privacy settings
exports.updatePrivacy = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!user.settings) user.settings = JSON.parse(JSON.stringify(defaultSettings));
        Object.assign(user.settings.privacy, req.body);
        user.markModified('settings.privacy');
        await user.save();

        res.json({ success: true, privacy: user.settings.privacy });
    } catch (error) {
        next(error);
    }
};

// @desc    Update quiet hours
exports.updateQuietHours = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!user.settings) user.settings = JSON.parse(JSON.stringify(defaultSettings));
        Object.assign(user.settings.quietHours, req.body);
        user.markModified('settings.quietHours');
        await user.save();

        res.json({ success: true, quietHours: user.settings.quietHours });
    } catch (error) {
        next(error);
    }
};

// @desc    Update language & region
exports.updateLanguage = async (req, res, next) => {
    try {
        const { language, currency } = req.body;
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!user.settings) user.settings = JSON.parse(JSON.stringify(defaultSettings));
        if (language) user.settings.language = language;
        if (currency) user.settings.currency = currency;
        user.markModified('settings');
        await user.save();

        res.json({ success: true, language: user.settings.language, currency: user.settings.currency });
    } catch (error) {
        next(error);
    }
};

// @desc    Update profile (username/bio/avatar/cover)
exports.updateProfile = async (req, res, next) => {
    try {
        const { username, bio, avatar, coverPhoto, region } = req.body;
        const user = await User.findById(req.userId);
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
        let avatarUploadStats = getAvatarUploadStats(user);
        if (avatar !== undefined) {
            avatarUploadStats = applyAvatarUpdate(user, avatar);
        }
        if (coverPhoto !== undefined) user.coverPhoto = coverPhoto;
        if (region !== undefined) {
            user.region = String(region).trim() || 'Global';
        }

        await user.save();

        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.del(`cache:user:${req.userId}`);
        }

        emitProfileUpdated(req, user);

        res.json({
            success: true,
            user: {
                id: user._id,
                username: user.username,
                email: user.email,
                avatar: user.avatar,
                coverPhoto: user.coverPhoto,
                bio: user.bio || '',
                region: user.region || 'Global'
            },
            avatarUploadsRemainingToday: avatarUploadStats.uploadsRemainingToday,
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Change password
exports.changePassword = async (req, res, next) => {
    try {
        const { currentPassword, newPassword } = req.body;
        const user = await User.findById(req.userId).select('+password');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const isMatch = await user.comparePassword(currentPassword);
        if (!isMatch) {
            const error = new Error('Current password is incorrect');
            error.status = 401;
            throw error;
        }

        user.password = newPassword;
        await user.save();

        res.json({ success: true, message: 'Password updated successfully' });
    } catch (error) {
        next(error);
    }
};

// @desc    Delete account
exports.deleteAccount = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        // Soft delete
        user.deletedAt = Date.now();
        user.email = `del_${Date.now()}@deleted.com`;
        user.phone = undefined;
        user.isDeleted = true;

        const suffix = Math.floor(Math.random() * 100000);
        const newUsername = `del_${user._id.toString().substring(0, 5)}_${suffix}`;
        user.username = newUsername.length > 20 ? newUsername.substring(0, 20) : newUsername;

        await user.save();
        res.json({ success: true, message: 'Account deleted successfully' });
    } catch (error) {
        next(error);
    }
};


