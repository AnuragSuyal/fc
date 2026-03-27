const AVATAR_UPLOAD_LIMIT_PER_DAY = 15;
const AVATAR_UPLOAD_WINDOW_MS = 24 * 60 * 60 * 1000;

const normalizeAvatarUploadHistory = (user, now = new Date()) => {
    const cutoff = new Date(now.getTime() - AVATAR_UPLOAD_WINDOW_MS);
    const history = Array.isArray(user.avatarUploadHistory) ? user.avatarUploadHistory : [];

    const normalized = history
        .map((entry) => entry instanceof Date ? entry : new Date(entry))
        .filter((entry) => !Number.isNaN(entry.getTime()) && entry > cutoff)
        .sort((a, b) => a.getTime() - b.getTime());

    user.avatarUploadHistory = normalized;
    return normalized;
};

const getAvatarUploadStats = (user, now = new Date()) => {
    const history = normalizeAvatarUploadHistory(user, now);
    return {
        uploadsUsedToday: history.length,
        uploadsRemainingToday: Math.max(0, AVATAR_UPLOAD_LIMIT_PER_DAY - history.length),
    };
};

const applyAvatarUpdate = (user, nextAvatar, now = new Date()) => {
    const normalizedAvatar = String(nextAvatar || '').trim();
    const stats = getAvatarUploadStats(user, now);

    if (!normalizedAvatar || normalizedAvatar === user.avatar) {
        return {
            updated: false,
            ...stats,
        };
    }

    if (stats.uploadsUsedToday >= AVATAR_UPLOAD_LIMIT_PER_DAY) {
        const error = new Error('Profile photo can only be updated 15 times per day.');
        error.status = 429;
        throw error;
    }

    user.avatar = normalizedAvatar;
    user.avatarUploadHistory = [...user.avatarUploadHistory, new Date(now)];

    return {
        updated: true,
        uploadsUsedToday: stats.uploadsUsedToday + 1,
        uploadsRemainingToday: Math.max(0, AVATAR_UPLOAD_LIMIT_PER_DAY - (stats.uploadsUsedToday + 1)),
    };
};

module.exports = {
    AVATAR_UPLOAD_LIMIT_PER_DAY,
    applyAvatarUpdate,
    getAvatarUploadStats,
    normalizeAvatarUploadHistory,
};
