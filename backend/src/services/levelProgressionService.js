const mongoose = require('mongoose');

const Room = require('../models/Room');
const User = require('../models/User');
const XpLog = require('../models/XpLog');
const {
    XP_SOURCE_DEFINITIONS
} = require('../config/leveling');
const {
    applyXpCategoryAward,
    buildLevelFields,
    ensureXpStatsShape,
    normalizeXp,
    resolveBadgeTier,
    syncUserLevelState
} = require('./levelingRulesService');
const {
    ROOM_UPDATE_EVENTS,
    decorateRoomPayload
} = require('./roomSettingsService');
const {
    buildVipMembershipSnapshot
} = require('./vipMembershipService');

const withSession = (query, session) => (session ? query.session(session) : query);

const runWithOptionalTransaction = async (work) => {
    const session = await mongoose.startSession();
    try {
        session.startTransaction();
        const result = await work(session);
        await session.commitTransaction();
        return result;
    } catch (error) {
        await session.abortTransaction();
        if (error?.message?.includes('Transaction numbers are only allowed')) {
            return await work(null);
        }
        throw error;
    } finally {
        await session.endSession();
    }
};

const normalizeSourceType = (sourceType) => {
    const normalized = String(sourceType || '').trim().toLowerCase();
    return normalized || 'manual';
};

const getSourceDefinition = (sourceType) => {
    const normalized = normalizeSourceType(sourceType);
    return XP_SOURCE_DEFINITIONS[normalized] || {
        key: normalized,
        label: normalized,
        category: 'reward',
        enabled: true
    };
};

const windowBucketKey = (windowMs) => {
    if (!windowMs || windowMs <= 0) return 'always';
    return Math.floor(Date.now() / windowMs).toString();
};

const buildCooldownKey = ({
    userId,
    sourceType,
    sourceReferenceId,
    dedupeKey
}) => [
    'xp',
    'cooldown',
    userId,
    sourceType,
    sourceReferenceId || dedupeKey || 'global'
].join(':');

const buildWindowKey = ({
    userId,
    sourceType,
    windowMs
}) => [
    'xp',
    'window',
    userId,
    sourceType,
    windowBucketKey(windowMs)
].join(':');

const setRedisValue = async (redis, key, value, ttlSeconds) => {
    if (!redis || !(redis.isReady ?? redis.isOpen)) return;

    try {
        if (ttlSeconds && ttlSeconds > 0) {
            await redis.set(key, value, { EX: ttlSeconds });
            return;
        }
        await redis.set(key, value);
    } catch (_) {
        await redis.set(key, value);
    }
};

const tryAcquireCooldown = async (redis, key, cooldownMs) => {
    if (!redis || !(redis.isReady ?? redis.isOpen) || !cooldownMs || cooldownMs <= 0) {
        return true;
    }

    try {
        const result = await redis.set(key, '1', {
            EX: Math.max(1, Math.ceil(cooldownMs / 1000)),
            NX: true
        });
        if (result === 'OK' || result === true) {
            return true;
        }
        if (result === null) {
            return false;
        }
    } catch (_) {}

    const existing = await redis.get(key);
    if (existing != null) {
        return false;
    }

    await setRedisValue(redis, key, '1', Math.max(1, Math.ceil(cooldownMs / 1000)));
    return true;
};

const incrementWindowCounter = async (redis, key, windowMs) => {
    if (!redis || !(redis.isReady ?? redis.isOpen)) {
        return 1;
    }

    if (typeof redis.incr === 'function') {
        const nextCount = await redis.incr(key);
        if (nextCount === 1 && typeof redis.expire === 'function') {
            await redis.expire(key, Math.max(1, Math.ceil((windowMs || 1000) / 1000)));
        }
        return Number(nextCount || 1);
    }

    const existingRaw = await redis.get(key);
    const nextCount = Math.max(Number(existingRaw || 0), 0) + 1;
    await setRedisValue(redis, key, String(nextCount), Math.max(1, Math.ceil((windowMs || 1000) / 1000)));
    return nextCount;
};

const buildRealtimeIdentityPayload = (user) => ({
    id: user._id,
    uid: user.uid,
    username: user.username,
    avatar: user.avatar,
    coverPhoto: user.coverPhoto,
    bio: user.bio,
    region: user.region || 'Global',
    coins: Number(user.coins || 0),
    gems: Number(user.gems || 0),
    vipLevel: Number(user.vipLevel || 0),
    vipMembership: buildVipMembershipSnapshot(user),
    shopProfile: user.shopProfile || {},
    status: user.status || {},
    lastActive: user.status?.lastActive || null,
    gameStats: user.gameStats || {},
    badges: user.badges || [],
    stats: user.stats || {},
    ...buildLevelFields(user)
});

const buildProgressPayload = (user, extra = {}) => ({
    coins: Number(user?.coins || 0),
    gems: Number(user?.gems || 0),
    vipLevel: Number(user?.vipLevel || 0),
    vipMembership: buildVipMembershipSnapshot(user),
    shopProfile: user?.shopProfile || {},
    ...buildLevelFields(user),
    ...extra
});

const buildLevelUpPayload = (user, result, extra = {}) => ({
    userId: user?._id?.toString() || '',
    previousLevel: Number(result?.previousLevel || user?.level || 1),
    newLevel: Number(result?.newLevel || user?.level || 1),
    xp: Number(user?.xp || 0),
    xpGained: Number(result?.xpGained || 0),
    source: result?.sourceType || 'manual',
    previousTier: result?.previousTier || resolveBadgeTier(result?.previousLevel || user?.level || 1).key,
    newTier: result?.newTier || resolveBadgeTier(user?.level || 1).key,
    milestoneTierChanged: result?.tierChanged === true,
    levelInfo: buildLevelFields(user).levelInfo,
    ...extra
});

const emitRoomIdentityUpdates = async (io, userId) => {
    if (!io || !userId) return;

    const rooms = await Room.find({
        'participants.userId': userId
    })
        .populate('ownerId', 'username avatar level vipLevel shopProfile')
        .populate('hostId', 'username avatar level vipLevel shopProfile')
        .populate('coHosts', 'username avatar level vipLevel shopProfile')
        .populate('moderators', 'username avatar level vipLevel shopProfile')
        .populate('participants.userId', 'username avatar level vipLevel shopProfile status.isOnline')
        .populate('bans.userId', 'username avatar')
        .populate('reports.userId', 'username avatar');

    for (const room of rooms) {
        const payload = decorateRoomPayload(room, null, {
            includeCapabilities: false,
            includeModeration: false
        });
        const roomId = payload?._id?.toString() || payload?.id?.toString();
        if (!roomId) continue;

        io.to(`room:${roomId}`).emit('room:updated', payload);
        io.to(`room:${roomId}`).emit(ROOM_UPDATE_EVENTS.IDENTITY, {
            roomId,
            room: payload,
            roomSettings: payload.roomSettings,
            updatedAt: new Date().toISOString(),
            actorUserId: userId.toString()
        });
    }
};

const emitLevelDrivenRealtime = async (io, user, result, extra = {}) => {
    if (!io || !user?._id || !result) return;
    if (!result.leveledUp && !result.tierChanged) return;

    const userId = user._id.toString();
    io.to(`user:${userId}`).emit('level_up', buildLevelUpPayload(user, result, extra));
    io.to(`user:${userId}`).emit('profile:updated', {
        userId,
        timestamp: new Date().toISOString(),
        user: buildRealtimeIdentityPayload(user),
        fields: {
            level: user.level,
            xp: user.xp,
            levelMilestoneTier: result.newTier
        }
    });
    io.to(`profile:${userId}`).emit('profile:updated', {
        userId,
        timestamp: new Date().toISOString(),
        user: buildRealtimeIdentityPayload(user),
        fields: {
            level: user.level,
            xp: user.xp,
            levelMilestoneTier: result.newTier
        }
    });

    await emitRoomIdentityUpdates(io, user._id);
};

const awardUserXp = async ({
    user,
    userId,
    amount,
    sourceType,
    sourceReferenceId = '',
    sourceReferenceType = '',
    dedupeKey = '',
    metadata = {},
    redis
} = {}) => {
    const normalizedSourceType = normalizeSourceType(sourceType);
    const sourceDefinition = getSourceDefinition(normalizedSourceType);
    const safeAmount = normalizeXp(
        amount != null ? amount : sourceDefinition.defaultAmount || 0
    );
    const targetUserId = user?._id?.toString() || userId?.toString() || '';

    if (!targetUserId) {
        return null;
    }

    if (!sourceDefinition.enabled) {
        return {
            user: user || await User.findById(targetUserId),
            xpGained: 0,
            skipped: true,
            reason: 'source_disabled',
            sourceType: normalizedSourceType
        };
    }

    if (safeAmount <= 0) {
        return {
            user: user || await User.findById(targetUserId),
            xpGained: 0,
            skipped: true,
            reason: 'invalid_amount',
            sourceType: normalizedSourceType
        };
    }

    const cooldownAllowed = await tryAcquireCooldown(
        redis,
        buildCooldownKey({
            userId: targetUserId,
            sourceType: normalizedSourceType,
            sourceReferenceId,
            dedupeKey
        }),
        sourceDefinition.cooldownMs
    );
    if (!cooldownAllowed) {
        return {
            user: user || await User.findById(targetUserId),
            xpGained: 0,
            skipped: true,
            reason: 'cooldown',
            sourceType: normalizedSourceType
        };
    }

    if (sourceDefinition.maxAwardsPerWindow && sourceDefinition.windowMs) {
        const windowCount = await incrementWindowCounter(
            redis,
            buildWindowKey({
                userId: targetUserId,
                sourceType: normalizedSourceType,
                windowMs: sourceDefinition.windowMs
            }),
            sourceDefinition.windowMs
        );
        if (windowCount > sourceDefinition.maxAwardsPerWindow) {
            return {
                user: user || await User.findById(targetUserId),
                xpGained: 0,
                skipped: true,
                reason: 'window_limit',
                sourceType: normalizedSourceType
            };
        }
    }

    try {
        return await runWithOptionalTransaction(async (session) => {
            const targetUser = user || await withSession(User.findById(targetUserId), session);
            if (!targetUser) {
                return null;
            }

            const trimmedDedupeKey = String(dedupeKey || '').trim();
            if (trimmedDedupeKey) {
                const existingLog = await withSession(
                    XpLog.findOne({
                        userId: targetUser._id,
                        sourceType: normalizedSourceType,
                        dedupeKey: trimmedDedupeKey
                    }),
                    session
                );
                if (existingLog) {
                    return {
                        user: targetUser,
                        xpGained: 0,
                        duplicate: true,
                        skipped: true,
                        reason: 'duplicate',
                        sourceType: normalizedSourceType,
                        previousLevel: Number(targetUser.level || 1),
                        newLevel: Number(targetUser.level || 1),
                        previousTier: resolveBadgeTier(targetUser.level || 1).key,
                        newTier: resolveBadgeTier(targetUser.level || 1).key,
                        leveledUp: false,
                        tierChanged: false
                    };
                }
            }

            const previousLevel = Number(targetUser.level || 1);
            const previousTier = resolveBadgeTier(previousLevel).key;
            const activeBoosts = targetUser.shopProfile?.activeBoosts || {};
            const xpBoostExpiresAt = activeBoosts.xpBoostExpiresAt
                ? new Date(activeBoosts.xpBoostExpiresAt)
                : null;
            const xpBoostMultiplier = xpBoostExpiresAt &&
                !Number.isNaN(xpBoostExpiresAt.getTime()) &&
                xpBoostExpiresAt > new Date()
                ? Math.max(Number(activeBoosts.xpBoostMultiplier || 1), 1)
                : 1;
            if (xpBoostMultiplier <= 1 && targetUser.shopProfile?.activeBoosts?.xpBoostMultiplier > 1) {
                targetUser.shopProfile.activeBoosts.xpBoostMultiplier = 1;
                targetUser.shopProfile.activeBoosts.xpBoostItemId = '';
                targetUser.shopProfile.activeBoosts.xpBoostExpiresAt = null;
                targetUser.markModified('shopProfile');
            }
            const effectiveXpAmount = normalizeXp(Math.round(safeAmount * xpBoostMultiplier));
            const nextXpStats = applyXpCategoryAward(
                ensureXpStatsShape(targetUser.xpStats),
                sourceDefinition.category,
                effectiveXpAmount
            );
            nextXpStats.totalAwarded += effectiveXpAmount;
            nextXpStats.totalAwards += 1;
            nextXpStats.lastAwardedAt = new Date();
            nextXpStats.lastSourceType = normalizedSourceType;
            nextXpStats.lastAwardAmount = effectiveXpAmount;

            targetUser.xp = Number(targetUser.xp || 0) + effectiveXpAmount;
            targetUser.xpStats = nextXpStats;

            const syncResult = syncUserLevelState(targetUser);
            await targetUser.save(session ? { session } : undefined);

            const logPayload = {
                userId: targetUser._id,
                sourceType: normalizedSourceType,
                amount: effectiveXpAmount,
                sourceReferenceId: String(sourceReferenceId || ''),
                sourceReferenceType: String(sourceReferenceType || ''),
                dedupeKey: trimmedDedupeKey || undefined,
                metadata,
                previousLevel,
                newLevel: syncResult.newLevel,
                awardedTier: syncResult.newTier,
                leveledUp: syncResult.leveledUp,
                tierChanged: syncResult.tierChanged
            };

            if (session) {
                await XpLog.create([logPayload], { session });
            } else {
                await XpLog.create(logPayload);
            }

            return {
                user: targetUser,
                xpGained: effectiveXpAmount,
                duplicate: false,
                skipped: false,
                reason: null,
                sourceType: normalizedSourceType,
                previousLevel,
                newLevel: syncResult.newLevel,
                previousTier,
                newTier: syncResult.newTier,
                leveledUp: syncResult.leveledUp,
                tierChanged: syncResult.tierChanged,
                levelInfo: syncResult.snapshot
            };
        });
    } catch (error) {
        if (error?.code === 11000) {
            return {
                user: user || await User.findById(targetUserId),
                xpGained: 0,
                duplicate: true,
                skipped: true,
                reason: 'duplicate',
                sourceType: normalizedSourceType
            };
        }
        throw error;
    }
};

module.exports = {
    awardUserXp,
    buildLevelUpPayload,
    buildProgressPayload,
    buildRealtimeIdentityPayload,
    emitLevelDrivenRealtime
};
