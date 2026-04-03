const Room = require('../models/Room');
const Message = require('../models/Message');
const User = require('../models/User');
const Group = require('../models/Group');
const Transaction = require('../models/Transaction');
const { AccessToken } = require('livekit-server-sdk');
const economyController = require('./economyController');
const previousDebugEnv = process.env.DEBUG;
process.env.DEBUG = '0';
const ytSearch = require('yt-search');
if (previousDebugEnv !== undefined) {
    process.env.DEBUG = previousDebugEnv;
} else {
    delete process.env.DEBUG;
}
const {
    getNextAdminUnlockLevel,
    getRoomAdminLimit
} = require('../services/roomProgressionService');
const {
    ROOM_ACTIONS,
    canJoinStageDirectly,
    canManageStage,
    canManageTarget,
    countActiveSpeakers,
    getMaxActiveSpeakers,
    getParticipant,
    isRoomAdmin,
    isRoomOwner,
    sanitizeRoomUpdatePayload,
    assertRoomPermission,
    canPerformRoomAction,
    getRoomMode
} = require('../services/roomPermissionService');
const {
    ROOM_UPDATE_EVENTS,
    applyRoomMode,
    canonicalTypeForMode,
    decorateRoomPayload,
    emitRoomUpdate,
    populateRoomById
} = require('../services/roomSettingsService');
const {
    muteParticipant: applyMuteParticipant,
    kickParticipant: applyKickParticipant
} = require('../services/roomModerationService');
const {
    assertSeatJoinAllowed
} = require('../services/roomSeatService');
const { logRoomAuditEvent } = require('../services/roomAuditService');
const {
    ensureUserPermanentRoom,
    getUserPermanentRoom
} = require('../services/permanentRoomService');
const {
    awardUserXp,
    buildProgressPayload,
    emitLevelDrivenRealtime
} = require('../services/levelProgressionService');
const {
    getPresentParticipants,
    markParticipantPresence,
    recalculateRoomPresenceState,
    trackRecentRoomVisit
} = require('../services/roomPresenceService');

const roomCacheKey = (roomId) => `cache:room:${roomId}`;
const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const RALLY_DURATION_MS = 5 * 60 * 1000;
const STREAM_ROOM_TYPE = 'video';
const STREAM_HOST_SEAT_INDEX = 1;
const STREAM_PLAYBACK_STATES = new Set(['paused', 'playing']);
const YOUTUBE_SEARCH_RESULT_LIMIT = 12;
const ROOM_INVITE_MESSAGE_TYPE = 'system';

const emitRoomSystemMessage = async ({ io, roomId, senderId, content, metadata = {}, createdAt = new Date() }) => {
    if (!io || !roomId || !senderId || !content) return;

    const message = new Message({
        roomId,
        senderId,
        content,
        type: 'system',
        metadata,
        createdAt
    });

    await message.save();
    await message.populate([
        { path: 'senderId', select: 'username avatar level' },
        { path: 'replyTo' }
    ]);

    io.to(`room:${roomId}`).emit('room:message', message.toObject({ virtuals: false }));
};

const clearSeatLockMetadata = (room, seatIndex) => {
    room.lockedSeats = (room.lockedSeats || []).filter((entry) => entry !== seatIndex);
    if (!Array.isArray(room.seatStates)) return;
    const seatState = room.seatStates.find((entry) => Number(entry?.seatIndex) === seatIndex);
    if (!seatState) return;
    seatState.isLocked = false;
    seatState.lockedByUserId = null;
    seatState.lockedAt = null;
    seatState.lockReason = '';
    seatState.updatedAt = new Date();
};

const normalizeYoutubePositionMs = (value) => {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue) || numericValue < 0) {
        return 0;
    }

    return Math.max(0, Math.trunc(numericValue));
};

const normalizeYoutubePlaybackState = (value) => {
    const normalized = String(value || '').trim().toLowerCase();
    if (!STREAM_PLAYBACK_STATES.has(normalized)) {
        return null;
    }

    return normalized;
};

const extractYoutubeVideoId = (input = '') => {
    const value = String(input || '').trim();
    if (!value) {
        return '';
    }

    try {
        const parsed = new URL(value);
        if (parsed.hostname.includes('youtu.be')) {
            return parsed.pathname.replace(/\//g, '').trim();
        }

        const videoId = parsed.searchParams.get('v');
        if (videoId) {
            return videoId.trim();
        }

        const embedMatch = parsed.pathname.match(/\/(?:embed|shorts)\/([A-Za-z0-9_-]{6,})/);
        if (embedMatch) {
            return embedMatch[1];
        }
    } catch (_) {
        // fall back to a lightweight pattern match below
    }

    const match = value.match(/([A-Za-z0-9_-]{11})/);
    return match ? match[1] : '';
};

const normalizeYoutubeQueueEntry = (entry = {}) => {
    if (!entry || typeof entry !== 'object') {
        return null;
    }

    const url = String(entry.url || entry.youtubeUrl || '').trim();
    if (!url) {
        return null;
    }

    const parsedAddedAt = entry.addedAt ? new Date(entry.addedAt) : new Date();
    return {
        videoId: String(entry.videoId || extractYoutubeVideoId(url) || '').trim(),
        url,
        title: String(entry.title || entry.youtubeTitle || '').trim().slice(0, 160),
        thumbnailUrl: String(entry.thumbnailUrl || entry.youtubeThumbnail || '').trim(),
        durationMs: normalizeYoutubePositionMs(entry.durationMs),
        addedBy: String(entry.addedBy || '').trim(),
        addedAt: Number.isNaN(parsedAddedAt.getTime()) ? new Date() : parsedAddedAt
    };
};

const normalizeYoutubeQueue = (queue = []) => {
    if (!Array.isArray(queue)) {
        return [];
    }

    return queue
        .map(normalizeYoutubeQueueEntry)
        .filter(Boolean);
};

const buildYoutubeQueueEntryFromTheme = (theme = {}) => {
    if (!theme?.youtubeUrl) {
        return null;
    }

    return normalizeYoutubeQueueEntry({
        url: theme.youtubeUrl,
        title: theme.youtubeTitle,
        thumbnailUrl: theme.youtubeThumbnail
    });
};

const getYoutubeSessionVersion = (theme = {}) => {
    const rawVersion = Number(theme?.youtubeSessionVersion);
    if (!Number.isFinite(rawVersion) || rawVersion < 0) {
        return 0;
    }

    return Math.trunc(rawVersion);
};

const syncYoutubeThemeQueueState = (theme = {}) => {
    let queue = normalizeYoutubeQueue(theme.youtubeQueue);

    if (queue.length === 0) {
        const currentEntry = buildYoutubeQueueEntryFromTheme(theme);
        if (currentEntry) {
            queue = [currentEntry];
        }
    }

    theme.youtubeQueue = queue;

    const current = queue[0];
    if (!current) {
        theme.youtubeUrl = '';
        theme.youtubeTitle = '';
        theme.youtubeThumbnail = '';
        theme.youtubeActiveVideoId = '';
        theme.youtubePositionMs = 0;
        theme.youtubePlaybackState = 'paused';
        return null;
    }

    theme.youtubeUrl = current.url;
    theme.youtubeTitle = current.title || '';
    theme.youtubeThumbnail = current.thumbnailUrl || '';
    theme.youtubeActiveVideoId = current.videoId || extractYoutubeVideoId(current.url) || '';
    return current;
};

const normalizeThemePatch = (theme = {}) => {
    if (!theme || typeof theme !== 'object') {
        return {};
    }

    const patch = { ...theme };

    if (patch.youtubeUrl !== undefined && patch.youtubeQueue === undefined) {
        const singleQueueEntry = normalizeYoutubeQueueEntry({
            url: patch.youtubeUrl,
            title: patch.youtubeTitle,
            thumbnailUrl: patch.youtubeThumbnail,
            durationMs: patch.youtubeDurationMs,
            addedBy: patch.youtubeAddedBy
        });
        patch.youtubeQueue = singleQueueEntry ? [singleQueueEntry] : [];
    }

    if (patch.youtubeQueue !== undefined) {
        patch.youtubeQueue = normalizeYoutubeQueue(patch.youtubeQueue);
        if (patch.youtubeQueue.length === 0) {
            patch.youtubeUrl = '';
            patch.youtubeTitle = '';
            patch.youtubeThumbnail = '';
        }
    }

    if (patch.youtubePositionMs !== undefined) {
        patch.youtubePositionMs = normalizeYoutubePositionMs(patch.youtubePositionMs);
    }

    if (patch.youtubePlaybackState !== undefined) {
        const playbackState = normalizeYoutubePlaybackState(patch.youtubePlaybackState);
        if (playbackState) {
            patch.youtubePlaybackState = playbackState;
        } else {
            delete patch.youtubePlaybackState;
        }
    }

    if (patch.youtubeSyncedAt !== undefined) {
        delete patch.youtubeSyncedAt;
    }
    if (patch.youtubeActiveVideoId !== undefined) {
        delete patch.youtubeActiveVideoId;
    }
    if (patch.youtubeSessionVersion !== undefined) {
        delete patch.youtubeSessionVersion;
    }

    return patch;
};

const resetSeatsForStreamMode = (room) => {
    if (!room) return;

    clearSeatLockMetadata(room, STREAM_HOST_SEAT_INDEX);

    const hostId = room.hostId?.toString();
    const isHostPresent = (participant) =>
        participant.userId?.toString() === hostId && participant.isPresent !== false;
    let hostParticipant = null;
    room.participants = (room.participants || []).map((participant) => {
        participant.raisedHand = false;

        if (isHostPresent(participant)) {
            participant.seatIndex = STREAM_HOST_SEAT_INDEX;
            participant.role = 'host';
            participant.lastActive = new Date();
            hostParticipant = participant;
            return participant;
        }

        participant.seatIndex = -1;
        if (participant.role === 'speaker') {
            participant.role = 'listener';
        }
        return participant;
    });

    if (!hostParticipant && hostId) {
        room.participants.unshift({
            userId: room.hostId,
            role: 'host',
            seatIndex: -1,
            joinedAt: new Date(),
            lastActive: new Date(),
            isPresent: false,
            raisedHand: false
        });
    }
};

const anchorHostToStreamSeat = (room) => {
    if (!room || room.type !== STREAM_ROOM_TYPE) return;

    const hostId = room.hostId?.toString();
    if (!hostId) return;

    clearSeatLockMetadata(room, STREAM_HOST_SEAT_INDEX);

    let hostParticipant = null;
    room.participants = (room.participants || []).map((participant) => {
        if (participant.userId?.toString() === hostId && participant.isPresent !== false) {
            participant.seatIndex = STREAM_HOST_SEAT_INDEX;
            participant.role = 'host';
            participant.lastActive = new Date();
            hostParticipant = participant;
            return participant;
        }

        if (participant.seatIndex === STREAM_HOST_SEAT_INDEX) {
            participant.seatIndex = -1;
            if (participant.role === 'speaker') {
                participant.role = 'listener';
            }
            participant.raisedHand = false;
        }

        return participant;
    });

    if (!hostParticipant) return;
};

const buildRoomInviteMetadata = ({
    inviter,
    room
}) => ({
    roomInvite: {
        roomId: room._id.toString(),
        roomName: room.name || 'Voice Room',
        roomType: room.type || 'voice',
        inviterId: inviter._id.toString(),
        inviterName: inviter.username || 'Someone',
        inviterAvatar: inviter.avatar || '',
        sentAt: new Date().toISOString()
    }
});

const cleanupExpiredRallies = async () => {
    await Room.updateMany(
        {
            rallyActive: true,
            rallyExpiresAt: { $lte: new Date() }
        },
        {
            $set: { rallyActive: false }
        }
    );
};

const buildRoomQuery = ({
    category,
    type,
    search,
    tag
}) => {
    const filters = [
        { endedAt: null },
        { showInExplore: { $ne: false } },
        { roomActive: true },
        { activeControllersCount: { $gt: 0 } }
    ];

    if (category && category !== 'all') {
        const categoryMatchers = [
            { category },
            { type: category }
        ];

        if (category === 'battle') {
            categoryMatchers.push({ type: 'game' });
        }

        filters.push({ $or: categoryMatchers });
    }

    if (type) {
        filters.push({ type });
    }

    if (search) {
        const normalizedSearch = escapeRegex(String(search).trim());
        if (normalizedSearch) {
            filters.push({
                $or: [
                    { name: { $regex: normalizedSearch, $options: 'i' } },
                    { roomId: { $regex: normalizedSearch, $options: 'i' } }
                ]
            });
        }
    }

    if (tag) {
        filters.push({ tags: tag });
    }

    return filters.length === 1 ? filters[0] : { $and: filters };
};

const buildRoomSortOptions = (sort = 'onlineCount') => {
    const sortOptions = {
        rallyActive: -1,
        rallyExpiresAt: -1
    };

    if (sort === 'newest') sortOptions.createdAt = -1;
    else if (sort === 'oldest') sortOptions.createdAt = 1;
    else {
        sortOptions.onlineCount = -1;
        sortOptions.participantCount = -1;
    }

    return sortOptions;
};

const invalidateRoomCache = async (redis, roomId) => {
    if (!redis || !redis.isReady) return;
    await redis.del(roomCacheKey(roomId));
};

const updateRoomPresence = async (redis, roomId, userId, action) => {
    if (!redis || !redis.isReady) return;
    const setKey = `room:${roomId}:users`;
    if (action === 'join') {
        await redis.sAdd(setKey, userId.toString());
    } else if (action === 'leave') {
        await redis.sRem(setKey, userId.toString());
    }
    const count = await redis.sCard(setKey);
    await redis.set(`room:${roomId}:count`, count.toString());
};

const buildLivekitToken = async (roomId, userId, username, avatar) => {
    if (!process.env.LIVEKIT_API_KEY || !process.env.LIVEKIT_API_SECRET) return null;

    const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
        identity: userId.toString(),
        ttl: '2h',
        metadata: JSON.stringify({ username: username || 'User', avatar: avatar || '' }),
        name: username || 'User'
    });

    token.addGrant({
        roomJoin: true,
        room: roomId.toString(),
        canPublish: true,
        canSubscribe: true
    });

    return token.toJwt();
};

const getLivekitServerUrl = (req) => {
    const configuredUrl = String(process.env.LIVEKIT_URL || '').trim();
    if (configuredUrl) {
        return configuredUrl;
    }

    const protocol = String(req.headers['x-forwarded-proto'] || req.protocol || 'http')
        .split(',')[0]
        .trim()
        .toLowerCase();
    const rawHost = String(req.headers['x-forwarded-host'] || req.get('host') || '')
        .split(',')[0]
        .trim();

    if (!rawHost) {
        return 'ws://localhost:7880';
    }

    try {
        const parsedHost = new URL(`${protocol}://${rawHost}`);
        const livekitHost = parsedHost.hostname.includes(':')
            ? `[${parsedHost.hostname}]`
            : parsedHost.hostname;
        return `${protocol === 'https' ? 'wss' : 'ws'}://${livekitHost}:7880`;
    } catch (_) {
        return 'ws://localhost:7880';
    }
};

// @desc    Ensure the caller permanent room exists
// @route   POST /api/rooms
// @access  Private
exports.createRoom = async (req, res, next) => {
    try {
        const ensured = await ensureUserPermanentRoom(req.userId, req.body || {});
        const populatedRoom = await populateRoomById(ensured.room._id);

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, populatedRoom._id);

        const livekitToken = await buildLivekitToken(
            populatedRoom.roomId || populatedRoom._id,
            req.userId,
            populatedRoom.hostId?.username,
            populatedRoom.hostId?.avatar
        );
        const roomPayload = decorateRoomPayload(populatedRoom, req.userId);

        const io = req.app.get('io');
        if (io) {
            if (ensured.created) {
                io.emit('room:created', roomPayload);
                emitRoomUpdate(io, populatedRoom, {
                    updateEvent: ROOM_UPDATE_EVENTS.IDENTITY,
                    lobbyAction: 'created'
                });
            }
        }

        res.status(ensured.created ? 201 : 200).json({
            room: roomPayload,
            created: ensured.created,
            migrated: ensured.migrated,
            archivedLegacyRoomCount: ensured.archivedLegacyRoomCount,
            livekitToken
        });
    } catch (error) {
        next(error);
    }
};

exports.getMyRoom = async (req, res, next) => {
    try {
        const result = await getUserPermanentRoom(req.userId, {
            allocateIfMissing: req.query.allocate === 'true'
        });

        if (!result.room) {
            return res.status(404).json({
                room: null,
                hasRoom: false,
                created: false,
                migrated: false,
                archivedLegacyRoomCount: 0
            });
        }

        const populatedRoom = await populateRoomById(result.room._id);
        return res.json({
            room: decorateRoomPayload(populatedRoom, req.userId),
            hasRoom: true,
            created: result.created,
            migrated: result.migrated,
            archivedLegacyRoomCount: result.archivedLegacyRoomCount
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get all rooms (with filters)
// @route   GET /api/rooms
// @access  Public
exports.getRooms = async (req, res, next) => {
    try {
        const {
            category,
            type,
            search,
            tag,
            limit = 50,
            page = 1,
            sort = 'onlineCount'
        } = req.query;

        await cleanupExpiredRallies();
        const query = buildRoomQuery({ category, type, search, tag });
        const sortOptions = buildRoomSortOptions(sort);

        const rooms = await Room.find(query)
            .populate('hostId', 'username avatar level vipLevel')
            .sort(sortOptions)
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Room.countDocuments(query);

        const redis = req.app.get('redis');
        let roomPayload = rooms;
        if (redis && redis.isReady && rooms.length > 0) {
            const counts = await Promise.all(rooms.map(room => redis.get(`room:${room._id}:count`)));
            roomPayload = rooms.map((room, index) => {
                const obj = room.toObject();
                const count = counts[index];
                if (count !== null && count !== undefined) {
                    obj.onlineCount = parseInt(count);
                }
                return obj;
            });
        }

        res.json({
            rooms: roomPayload,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                pages: Math.ceil(total / parseInt(limit))
            }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get room by ID
// @route   GET /api/rooms/:id
// @access  Public
exports.getRoomById = async (req, res, next) => {
    try {
        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            const cached = await redis.get(roomCacheKey(req.params.id));
            if (cached) {
                const parsed = JSON.parse(cached);
                if (parsed.groupId) {
                    if (!req.userId) {
                        const error = new Error('Join the group to open this voice lounge');
                        error.status = 403;
                        throw error;
                    }

                    const memberGroup = await Group.findOne({
                        _id: parsed.groupId,
                        'members.userId': req.userId
                    }).select('_id');
                    if (!memberGroup) {
                        const error = new Error('Only group members can open this voice lounge');
                        error.status = 403;
                        throw error;
                    }
                }
                if (req.userId) {
                    const isBanned = parsed.bans?.some(ban => {
                        const banUserId = ban.userId?._id ? ban.userId._id.toString() : ban.userId?.toString();
                        return banUserId === req.userId &&
                            (!ban.expiresAt || new Date(ban.expiresAt) > Date.now());
                    });
                    if (isBanned) {
                        const error = new Error('You are banned from this room');
                        error.status = 403;
                        throw error;
                    }
                }
                return res.json(decorateRoomPayload(parsed, req.userId || null, {
                    includeModeration: Boolean(req.userId)
                }));
            }
        }

        const room = await populateRoomById(req.params.id);

        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        if (room.groupId) {
            if (!req.userId) {
                const error = new Error('Join the group to open this voice lounge');
                error.status = 403;
                throw error;
            }

            const memberGroup = await Group.findOne({
                _id: room.groupId,
                'members.userId': req.userId
            }).select('_id');
            if (!memberGroup) {
                const error = new Error('Only group members can open this voice lounge');
                error.status = 403;
                throw error;
            }
        }

        if (req.userId) {
            const isBanned = room.bans.some(ban =>
                ban.userId.toString() === req.userId &&
                (!ban.expiresAt || ban.expiresAt > Date.now())
            );
            if (isBanned) {
                const error = new Error('You are banned from this room');
                error.status = 403;
                throw error;
            }
        }

        room.metrics.totalVisits += 1;
        await room.save();

        if (redis && redis.isReady) {
            await redis.set(roomCacheKey(room._id), JSON.stringify(room.toObject()), { EX: 60 });
        }

        res.json(decorateRoomPayload(room, req.userId || null, {
            includeModeration: Boolean(req.userId)
        }));
    } catch (error) {
        next(error);
    }
};

// @desc    Join a room
// @route   POST /api/rooms/:id/join
// @access  Private
exports.joinRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id).select('+settings.password');
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }
        if (room.endedAt && !room.isPermanent) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }
        if (room.isPermanent && room.endedAt) {
            room.endedAt = null;
        }

        if (room.groupId) {
            const memberGroup = await Group.findOne({
                _id: room.groupId,
                'members.userId': req.userId
            }).select('_id');
            if (!memberGroup) {
                const error = new Error('Only group members can join this voice lounge');
                error.status = 403;
                throw error;
            }
        }

        const presentParticipantsCount = getPresentParticipants(room).length;
        if (presentParticipantsCount >= room.settings.maxParticipants) {
            const error = new Error('Room is full');
            error.status = 400;
            throw error;
        }

        if (room.settings.isPrivate) {
            const { password } = req.body;
            if (!password || password !== room.settings.password) {
                const error = new Error('Invalid password');
                error.status = 401;
                throw error;
            }
        }

        const isBanned = room.bans.some(ban =>
            ban.userId.toString() === req.userId &&
            (!ban.expiresAt || ban.expiresAt > Date.now())
        );

        if (isBanned) {
            const error = new Error('You are banned from this room');
            error.status = 403;
            throw error;
        }

        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        // Handle entry fee
        if (room.settings.entryFee > 0) {
            if (user.coins < room.settings.entryFee) {
                const error = new Error('Insufficient coins');
                error.status = 400;
                throw error;
            }

            const balanceBefore = { coins: user.coins, gems: user.gems };
            user.coins -= room.settings.entryFee;
            await user.save();

            room.economy.totalEarned += room.settings.entryFee;
            room.economy.todayEarned += room.settings.entryFee;

            // Audit transaction
            const transaction = new Transaction({
                userId: user._id,
                type: 'room_entry',
                amount: { coins: -room.settings.entryFee },
                balanceBefore,
                balanceAfter: { coins: user.coins, gems: user.gems },
                reference: { roomId: room._id },
                description: `Entry fee for room: ${room.name}`,
                status: 'completed'
            });
            await transaction.save();
        }

        // Add to participants if not already there
        const existingIdx = room.participants.findIndex(p => p.userId.toString() === req.userId);
        const didJoinRoom = existingIdx === -1;
        const joinTimestamp = new Date();
        if (didJoinRoom) {
            let role = 'listener';
            if (room.hostId.toString() === req.userId) role = 'host';
            else if (room.coHosts?.some(id => id.toString() === req.userId)) role = 'cohost';
            else if (room.moderators?.some(id => id.toString() === req.userId)) role = 'moderator';

            room.participants.push({
                userId: req.userId,
                role,
                joinedAt: joinTimestamp,
                lastActive: joinTimestamp,
                isPresent: true
            });

            const nextPeakCount = getPresentParticipants(room).length;
            if (nextPeakCount > room.metrics.peakParticipants) {
                room.metrics.peakParticipants = nextPeakCount;
            }
        } else {
            room.participants[existingIdx].lastActive = joinTimestamp;
            room.participants[existingIdx].isPresent = true;
        }

        recalculateRoomPresenceState(room);
        anchorHostToStreamSeat(room);
        trackRecentRoomVisit(user, room._id);

        await Promise.all([room.save(), user.save()]);

        let joinXpProgress = null;
        if (didJoinRoom) {
            joinXpProgress = await awardUserXp({
                user,
                amount: 12,
                sourceType: 'room_join',
                sourceReferenceId: room._id.toString(),
                sourceReferenceType: 'room',
                dedupeKey: `room-join:${room._id}:${new Date().toISOString().slice(0, 10)}`,
                redis: req.app.get('redis'),
                metadata: {
                    roomId: room._id.toString(),
                    roomType: room.type,
                    roomCategory: room.category
                }
            });
        }
        const progressedUser = joinXpProgress?.user || user;

        const populatedRoom = await populateRoomById(room._id);

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, req.userId, 'join');

        if (didJoinRoom) {
            economyController._progressQuest(redis, req.userId, 'join_room', 1).catch(() => {});

            if (redis && redis.isReady) {
                const weekKey = `quests:visited_rooms:${req.userId}:${new Date().toISOString().slice(0, 7)}`;
                const added = await redis.sAdd(weekKey, room._id.toString());
                await redis.expire(weekKey, 7 * 86400);
                if (added) {
                    economyController._progressQuest(redis, req.userId, 'weekly_rooms', 1).catch(() => {});
                }
            } else {
                economyController._progressQuest(redis, req.userId, 'weekly_rooms', 1).catch(() => {});
            }
        }

        const livekitToken = await buildLivekitToken(room.roomId || room._id, req.userId, user.username, user.avatar);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:joined', {
                roomId: room._id.toString(),
                userId: req.userId,
                username: user.username,
                avatar: user.avatar,
                joinedAt: joinTimestamp.toISOString()
            });
            if (didJoinRoom) {
                await emitRoomSystemMessage({
                    io,
                    roomId: room._id,
                    senderId: user._id,
                    content: `Welcome ${user.username}`,
                    metadata: {
                        systemEvent: 'participant_joined',
                        joinedUserId: user._id.toString(),
                        joinedUsername: user.username,
                        joinedAt: joinTimestamp.toISOString()
                    },
                    createdAt: joinTimestamp
                });
            }
            // Update balance for the user
            io.to(`user:${progressedUser._id}`).emit(
                'balance_update',
                buildProgressPayload(progressedUser, {
                    xpGained: joinXpProgress?.xpGained || 0,
                    source: didJoinRoom ? 'room_join' : 'room_entry'
                })
            );
            await emitLevelDrivenRealtime(io, progressedUser, joinXpProgress, {
                source: 'room_join'
            });
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'participant_joined',
                extraPayload: { userId: req.userId }
            });
        }

        const roomPayload = decorateRoomPayload(populatedRoom, req.userId);
        res.json({ ...roomPayload, livekitToken });
    } catch (error) {
        next(error);
    }
};

// @desc    Leave a room
// @route   POST /api/rooms/:id/leave
// @access  Private
exports.leaveRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        room.participants = room.participants.filter(p => p.userId.toString() !== req.userId);

        if (room.participants.length === 0) {
            room.endedAt = room.isPermanent ? null : Date.now();
        }

        recalculateRoomPresenceState(room);
        anchorHostToStreamSeat(room);

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, req.userId, 'leave');

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:left', {
                roomId: room._id.toString(),
                userId: req.userId
            });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: room.endedAt ? 'ended' : 'participant_left',
                extraPayload: { userId: req.userId, ended: Boolean(room.endedAt) }
            });
        }

        res.json({ success: true, message: 'Left room successfully' });
    } catch (error) {
        next(error);
    }
};

// @desc    Update room settings
// @route   PUT /api/rooms/:id
// @access  Private
exports.updateRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const isHost = isRoomOwner(room, req.userId);
        const canManageRoom = isRoomAdmin(room, req.userId);
        if (!canManageRoom) {
            const error = new Error('Only the room owner and admins can update this room');
            error.status = 403;
            throw error;
        }

        const patch = sanitizeRoomUpdatePayload(room, req.userId, req.body);
        if (!patch) {
            const error = new Error(
                isHost
                    ? 'Room update payload is invalid'
                    : 'Admins can only change live safety controls and shared room media playback'
            );
            error.status = 403;
            throw error;
        }

        const previousSnapshot = {
            name: room.name,
            topic: room.topic || '',
            language: room.language || 'en',
            region: room.region || 'Global',
            roomRules: room.roomRules || '',
            announcement: room.announcement?.text || room.announcement || '',
            category: room.category,
            type: room.type,
            mode: room.mode || getRoomMode(room),
            settings: { ...(room.settings?.toObject?.() || room.settings || {}) },
            theme: { ...(room.theme?.toObject?.() || room.theme || {}) }
        };
        const previousType = room.type;
        const previousYoutubeUrl = room.theme?.youtubeUrl || '';
        const previousYoutubeActiveVideoId = String(
            room.theme?.youtubeActiveVideoId || extractYoutubeVideoId(previousYoutubeUrl)
        ).trim();
        const previousYoutubeSessionVersion = getYoutubeSessionVersion(room.theme);
        const normalizedThemePatch = normalizeThemePatch(patch.theme);
        const allowedUpdates = [
            'name',
            'description',
            'type',
            'mode',
            'category',
            'tags',
            'topic',
            'language',
            'region',
            'roomRules',
            'settings',
            'theme',
            'announcement'
        ];
        allowedUpdates.forEach(field => {
            if (patch[field] !== undefined) {
                if (field === 'settings') {
                    room.settings = { ...room.settings, ...patch.settings };
                } else if (field === 'theme') {
                    room.theme = { ...room.theme, ...normalizedThemePatch };
                } else if (field === 'mode') {
                    applyRoomMode(room, patch.mode);
                } else if (field === 'announcement') {
                    room.announcement = {
                        text: patch.announcement,
                        updatedAt: Date.now(),
                        updatedBy: req.userId
                    };
                } else {
                    room[field] = patch[field];
                }
            }
        });

        if (patch.type !== undefined && patch.mode === undefined) {
            room.mode = patch.type === 'auction'
                ? 'auction'
                : patch.type === 'chat'
                    ? 'acquaint'
                    : 'normal';
        }

        const switchedIntoStreamMode =
            patch.type === STREAM_ROOM_TYPE && previousType !== STREAM_ROOM_TYPE;
        if (switchedIntoStreamMode) {
            resetSeatsForStreamMode(room);
        } else if (room.type === STREAM_ROOM_TYPE) {
            anchorHostToStreamSeat(room);
        }

        if (room.type === STREAM_ROOM_TYPE) {
            syncYoutubeThemeQueueState(room.theme);
            room.markModified('theme');
        }

        const nextYoutubeUrl = room.theme?.youtubeUrl || '';
        const nextYoutubeActiveVideoId = String(
            room.theme?.youtubeActiveVideoId || extractYoutubeVideoId(nextYoutubeUrl)
        ).trim();
        const youtubeQueuePatchProvided =
            normalizedThemePatch.youtubeQueue !== undefined ||
                normalizedThemePatch.youtubeUrl !== undefined ||
                normalizedThemePatch.youtubeTitle !== undefined ||
                normalizedThemePatch.youtubeThumbnail !== undefined;
        const youtubeActiveSourceChanged =
            nextYoutubeUrl !== previousYoutubeUrl ||
            nextYoutubeActiveVideoId !== previousYoutubeActiveVideoId;
        const youtubeVideoChanged =
            youtubeQueuePatchProvided &&
            youtubeActiveSourceChanged;
        const youtubePlaybackPatchProvided =
            normalizedThemePatch.youtubePositionMs !== undefined ||
            normalizedThemePatch.youtubePlaybackState !== undefined;
        const youtubeSessionShouldAdvance =
            switchedIntoStreamMode ||
            youtubeActiveSourceChanged ||
            (Boolean(previousYoutubeUrl) && !nextYoutubeUrl);

        if (room.type === STREAM_ROOM_TYPE) {
            if (youtubeSessionShouldAdvance) {
                room.theme.youtubeSessionVersion = previousYoutubeSessionVersion + 1;
            } else {
                room.theme.youtubeSessionVersion = getYoutubeSessionVersion(room.theme);
            }

            if (!nextYoutubeUrl) {
                room.theme.youtubePositionMs = 0;
                room.theme.youtubePlaybackState = 'paused';
                room.theme.youtubeSyncedAt = new Date();
            } else if (youtubeVideoChanged) {
                room.theme.youtubePositionMs = normalizeYoutubePositionMs(
                    normalizedThemePatch.youtubePositionMs
                );
                room.theme.youtubePlaybackState =
                    normalizeYoutubePlaybackState(normalizedThemePatch.youtubePlaybackState) ||
                    'playing';
                room.theme.youtubeSyncedAt = new Date();
            } else if (youtubePlaybackPatchProvided) {
                if (normalizedThemePatch.youtubePositionMs !== undefined) {
                    room.theme.youtubePositionMs = normalizeYoutubePositionMs(
                        normalizedThemePatch.youtubePositionMs
                    );
                }
                if (normalizedThemePatch.youtubePlaybackState !== undefined) {
                    room.theme.youtubePlaybackState =
                        normalizeYoutubePlaybackState(normalizedThemePatch.youtubePlaybackState) ||
                        room.theme.youtubePlaybackState ||
                        'paused';
                }
                room.theme.youtubeSyncedAt = new Date();
            } else if (switchedIntoStreamMode) {
                room.theme.youtubePositionMs = normalizeYoutubePositionMs(
                    room.theme.youtubePositionMs
                );
                room.theme.youtubePlaybackState =
                    normalizeYoutubePlaybackState(room.theme.youtubePlaybackState) ||
                    (nextYoutubeUrl ? 'playing' : 'paused');
                room.theme.youtubeSyncedAt = new Date();
            }
        }

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);

        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(room._id);
        if (io) {
            const themeKeys = Object.keys(normalizedThemePatch || {});
            const hasRealtimeThemePatch = themeKeys.some((key) => key !== 'coverImage');
            const updateEvent =
                hasRealtimeThemePatch ? ROOM_UPDATE_EVENTS.THEME :
                    patch.mode !== undefined || patch.type !== undefined ? ROOM_UPDATE_EVENTS.MODE :
                        patch.name !== undefined || patch.announcement !== undefined || patch.theme?.coverImage !== undefined
                            ? ROOM_UPDATE_EVENTS.IDENTITY
                            : ROOM_UPDATE_EVENTS.SETTINGS;
            emitRoomUpdate(io, populatedRoom, {
                updateEvent,
                lobbyAction: 'updated'
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: isRoomAdmin(room, req.userId) ? 'admin' : 'member',
            action: 'room.update_settings',
            before: previousSnapshot,
            after: {
                name: populatedRoom.name,
                topic: populatedRoom.topic || '',
                language: populatedRoom.language || 'en',
                region: populatedRoom.region || 'Global',
                roomRules: populatedRoom.roomRules || '',
                announcement: populatedRoom.announcement?.text || populatedRoom.announcement || '',
                category: populatedRoom.category,
                type: populatedRoom.type,
                mode: populatedRoom.mode || getRoomMode(populatedRoom),
                settings: populatedRoom.settings,
                theme: populatedRoom.theme
            },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) {
        next(error);
    }
};

// @desc    LiveKit sequence
exports.getRoomToken = async (req, res, next) => {
    try {
        const roomId = req.params.id;

        const room = await Room.findById(roomId);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const isBanned = room.bans?.some(ban =>
            ban.userId.toString() === req.userId &&
            (!ban.expiresAt || ban.expiresAt > Date.now())
        );
        if (isBanned) {
            const error = new Error('You are banned from this room');
            error.status = 403;
            throw error;
        }

        assertRoomPermission({
            room,
            actorUserId: req.userId,
            action: ROOM_ACTIONS.GET_ROOM_TOKEN
        }, 'Join the room before requesting voice access');

        const user = await User.findById(req.userId).select('username avatar');
        const token = await buildLivekitToken(room.roomId || room._id, req.userId, user?.username, user?.avatar);

        if (!token) {
            const error = new Error('LiveKit credentials not configured');
            error.status = 500;
            throw error;
        }

        res.json({ token, serverUrl: getLivekitServerUrl(req) });
    } catch (error) {
        next(error);
    }
};

exports.inviteFriendToRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id)
            .select('name type hostId participants bans endedAt');
        if (!room || room.endedAt) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const participant = getParticipant(room, req.userId);
        if (!participant && !isRoomOwner(room, req.userId)) {
            const error = new Error('Join the room before inviting friends');
            error.status = 403;
            throw error;
        }
        assertRoomPermission({
            room,
            actorUserId: req.userId,
            action: ROOM_ACTIONS.INVITE_USER
        }, 'Only hosts and admins can invite friends');

        const { targetUserId } = req.body;
        if (targetUserId === req.userId) {
            const error = new Error('You are already in this room');
            error.status = 400;
            throw error;
        }

        if (room.participants.some((entry) => entry.userId?.toString() === targetUserId)) {
            const error = new Error('That friend is already in the room');
            error.status = 400;
            throw error;
        }

        const isTargetBanned = room.bans?.some((ban) =>
            ban.userId?.toString() === targetUserId &&
            (!ban.expiresAt || new Date(ban.expiresAt) > new Date())
        );
        if (isTargetBanned) {
            const error = new Error('That friend cannot join this room right now');
            error.status = 403;
            throw error;
        }

        const [inviter, targetUser] = await Promise.all([
            User.findById(req.userId).select('username avatar friends'),
            User.findById(targetUserId).select('username avatar')
        ]);
        if (!inviter || !targetUser) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const isFriend = (inviter.friends || []).some(
            (friendId) => friendId?.toString() === targetUserId
        );
        if (!isFriend) {
            const error = new Error('You can only invite your friends');
            error.status = 403;
            throw error;
        }

        const metadata = buildRoomInviteMetadata({ inviter, room });
        const message = new Message({
            senderId: req.userId,
            recipientId: targetUserId,
            content: `Join me in ${room.name}`,
            type: ROOM_INVITE_MESSAGE_TYPE,
            metadata
        });
        await message.save();
        await message.populate({
            path: 'senderId',
            select: 'username avatar level'
        });

        const messagePayload = message.toObject({ virtuals: false });
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${targetUserId}`).emit('dm:received', {
                message: messagePayload,
                from: { id: req.userId, username: inviter.username }
            });
            io.to(`user:${targetUserId}`).emit('room:invite', {
                roomId: room._id.toString(),
                roomName: room.name,
                roomType: room.type,
                inviterId: req.userId,
                inviterName: inviter.username,
                inviterAvatar: inviter.avatar || ''
            });
        }

        res.status(201).json(messagePayload);
    } catch (error) {
        next(error);
    }
};

exports.takeSeat = async (req, res, next) => {
    try {
        const seatIndex = Number(req.body.seatIndex ?? req.body.seatNumber);
        if (!Number.isInteger(seatIndex)) {
            const error = new Error('Seat number required');
            error.status = 400;
            throw error;
        }
        if (seatIndex < 1 || seatIndex > 8) {
            const error = new Error('Seat number must be between 1 and 8');
            error.status = 400;
            throw error;
        }

        const room = await Room.findById(req.params.id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }
        if (room.roomActive === false) {
            const error = new Error('Room inactive - waiting for host/admin');
            error.status = 403;
            throw error;
        }

        const isStreamRoom = room.type === STREAM_ROOM_TYPE;
        const isHost = isRoomOwner(room, req.userId);
        if (isStreamRoom) {
            anchorHostToStreamSeat(room);
        }

        if (isStreamRoom && isHost && seatIndex !== STREAM_HOST_SEAT_INDEX) {
            const error = new Error('The host stays on seat 1 while stream mode is active');
            error.status = 403;
            throw error;
        }

        if (isStreamRoom && !isHost && seatIndex === STREAM_HOST_SEAT_INDEX) {
            const error = new Error('Seat 1 is reserved for the host in stream mode');
            error.status = 403;
            throw error;
        }

        const maxActiveSpeakers = getMaxActiveSpeakers(room);
        assertSeatJoinAllowed({
            room,
            userId: req.userId,
            seatIndex
        });

        const participant = getParticipant(room, req.userId);
        if (!participant) {
            const error = new Error('User not in room');
            error.status = 400;
            throw error;
        }

        if (participant.seatIndex === seatIndex) {
            const populatedRoom = await populateRoomById(room._id);
            res.json(decorateRoomPayload(populatedRoom, req.userId));
            return;
        }

        if (!canJoinStageDirectly(room, req.userId)) {
            participant.raisedHand = true;
            participant.lastActive = Date.now();

            await room.save();
            const redis = req.app.get('redis');
            await invalidateRoomCache(redis, room._id);
            const io = req.app.get('io');
            const populatedRoom = await populateRoomById(room._id);
            if (io) {
                emitRoomUpdate(io, populatedRoom, {
                    updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                    lobbyAction: 'stage_request',
                    extraPayload: { userId: req.userId, requestPending: true }
                });
            }

            res.json(decorateRoomPayload(populatedRoom, req.userId));
            return;
        }

        if (isStreamRoom && isHost) {
            participant.seatIndex = STREAM_HOST_SEAT_INDEX;
            participant.raisedHand = false;
            participant.role = 'host';

            await room.save();
            const redis = req.app.get('redis');
            await invalidateRoomCache(redis, room._id);
            const io = req.app.get('io');
            const populatedRoom = await populateRoomById(room._id);
            if (io) {
                emitRoomUpdate(io, populatedRoom, {
                    updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                    lobbyAction: 'seat_updated',
                    extraPayload: { userId: req.userId, seatIndex: STREAM_HOST_SEAT_INDEX }
                });
            }

            res.json(decorateRoomPayload(populatedRoom, req.userId));
            return;
        }

        if (participant.seatIndex < 1 && countActiveSpeakers(room) >= maxActiveSpeakers) {
            const error = new Error('All active speaker seats are full right now');
            error.status = 400;
            throw error;
        }

        participant.seatIndex = seatIndex;
        participant.raisedHand = false;
        if (participant.role === 'listener') participant.role = 'speaker';

        await room.save();
        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(room._id);
        if (io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'seat_updated',
                extraPayload: { userId: req.userId, seatIndex }
            });
        }

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) {
        next(error);
    }
};

exports.leaveSeat = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const participant = getParticipant(room, req.userId);
        if (!participant) {
            const error = new Error('User not in room');
            error.status = 400;
            throw error;
        }

        if (room.type === STREAM_ROOM_TYPE && isRoomOwner(room, req.userId)) {
            const error = new Error('The host stays on seat 1 while stream mode is active');
            error.status = 403;
            throw error;
        }

        participant.seatIndex = -1;
        participant.raisedHand = false;
        if (participant.role === 'speaker') participant.role = 'listener';

        await room.save();
        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(room._id);
        if (io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'seat_updated',
                extraPayload: { userId: req.userId, seatIndex: -1 }
            });
        }

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) {
        next(error);
    }
};

exports.searchYoutubeVideos = async (req, res, next) => {
    try {
        const query = String(req.query.query || '').trim();
        if (!query) {
            const error = new Error('Search query required');
            error.status = 400;
            throw error;
        }

        const room = await Room.findById(req.params.id).select('hostId participants type');
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        if (!getParticipant(room, req.userId) && !isRoomOwner(room, req.userId)) {
            const error = new Error('Join the room before searching the stream playlist');
            error.status = 403;
            throw error;
        }

        const searchResponse = await ytSearch({
            query,
            hl: 'en',
            gl: 'US'
        });

        const seenVideoIds = new Set();
        const results = (searchResponse.videos || [])
            .map((video) => ({
                id: video.videoId?.toString() || '',
                title: video.title?.toString() || 'Untitled video',
                author: video.author?.name?.toString() || '',
                durationMs: Number.isFinite(video.seconds)
                    ? Math.trunc(video.seconds * 1000)
                    : null,
                thumbnailUrl:
                    video.thumbnail?.toString() ||
                    video.image?.toString() ||
                    (video.videoId
                        ? `https://i.ytimg.com/vi/${video.videoId}/hqdefault.jpg`
                        : '')
            }))
            .filter((video) => {
                if (!video.id || seenVideoIds.has(video.id)) {
                    return false;
                }
                seenVideoIds.add(video.id);
                return true;
            })
            .slice(0, YOUTUBE_SEARCH_RESULT_LIMIT);

        res.json({ results });
    } catch (error) {
        next(error);
    }
};

exports.getTrendingRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const rooms = await Room.find({
            endedAt: null,
            roomActive: true,
            activeControllersCount: { $gt: 0 }
        })
            .populate('hostId', 'username avatar level')
            .sort({ rallyActive: -1, rallyExpiresAt: -1, onlineCount: -1, participantCount: -1 })
            .limit(10);
        res.json(rooms.map((room) => decorateRoomPayload(room, req.userId || null, {
            includeCapabilities: false,
            includeModeration: false
        })));
    } catch (error) {
        next(error);
    }
};

exports.deleteRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }
        if (!isRoomOwner(room, req.userId)) {
            const error = new Error('Only host can delete room');
            error.status = 403;
            throw error;
        }
        if (room.isPermanent) {
            const error = new Error('Permanent rooms cannot be deleted. You can keep editing the same room instead.');
            error.status = 403;
            throw error;
        }
        room.endedAt = Date.now();
        await room.save();
        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:deleted', { roomId: room._id });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.IDENTITY,
                lobbyAction: 'deleted'
            });
        }
        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            action: 'room.delete',
            source: 'rest',
            success: true,
            requestId: req.id
        });
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

exports.getMyRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const result = await getUserPermanentRoom(req.userId);
        if (!result.room) {
            return res.json([]);
        }

        const rooms = await Room.find({ _id: result.room._id, endedAt: null })
            .populate('ownerId', 'username avatar level vipLevel')
            .populate('hostId', 'username avatar level')
            .sort({ updatedAt: -1 });
        res.json(rooms.map((room) => decorateRoomPayload(room, req.userId, {
            includeCapabilities: false,
            includeModeration: false
        })));
    } catch (error) {
        next(error);
    }
};

exports.getFollowedRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const rooms = await Room.find({ followers: req.userId, endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({
                roomActive: -1,
                activeControllersCount: -1,
                rallyActive: -1,
                rallyExpiresAt: -1,
                updatedAt: -1
            });
        res.json(rooms.map((room) => decorateRoomPayload(room, req.userId, {
            includeCapabilities: false,
            includeModeration: false
        })));
    } catch (error) {
        next(error);
    }
};

exports.getRecentRooms = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('recentRooms')
            .lean();
        const recentEntries = Array.isArray(user?.recentRooms)
            ? [...user.recentRooms]
            : [];
        if (recentEntries.length === 0) {
            return res.json({ rooms: [] });
        }

        recentEntries.sort((left, right) =>
            new Date(right.lastVisitedAt || 0).getTime() -
            new Date(left.lastVisitedAt || 0).getTime()
        );
        const orderedIds = recentEntries
            .map((entry) => entry.roomId?.toString?.() || '')
            .filter(Boolean)
            .slice(0, 10);
        if (orderedIds.length === 0) {
            return res.json({ rooms: [] });
        }

        const rooms = await Room.find({
            _id: { $in: orderedIds },
            endedAt: null
        }).populate('hostId', 'username avatar level');
        const roomById = new Map(
            rooms.map((room) => [room._id.toString(), room])
        );
        const orderedRooms = orderedIds
            .map((roomId) => roomById.get(roomId))
            .filter(Boolean)
            .map((room) => decorateRoomPayload(room, req.userId, {
                includeCapabilities: false,
                includeModeration: false
            }));

        res.json({ rooms: orderedRooms });
    } catch (error) {
        next(error);
    }
};

exports.getCategories = (req, res) => {
    res.json([
        { id: 'all', name: 'All Rooms', icon: 'ðŸŒ' },
        { id: 'voice', name: 'Voice Chat', icon: 'ðŸŽ¤' },
        { id: 'music', name: 'Music', icon: 'ðŸŽµ' },
        { id: 'video', name: 'Video', icon: 'ðŸ“º' },
        { id: 'chat', name: 'Chat', icon: 'ðŸ’¬' },
        { id: 'battle', name: 'Battle', icon: 'âš”ï¸' },
        { id: 'auction', name: 'Auction', icon: 'ðŸ’°' }
    ]);
};

exports.getRoomCategories = exports.getCategories;

// @desc    Mute or unmute a participant
exports.muteParticipant = async (req, res, next) => {
    try {
        const { id, userId } = req.params;
        const { muted } = req.body;

        const room = await Room.findById(id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const shouldMute = muted === undefined ? true : Boolean(muted);
        applyMuteParticipant({ room, actorUserId: req.userId, targetUserId: userId, muted: shouldMute });

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:muted', {
                roomId: room._id.toString(),
                userId,
                muted: shouldMute
            });
            io.to(`user:${userId}`).emit('room:mute', { roomId: room._id, muted: shouldMute });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'moderation_updated',
                extraPayload: { userId, muted: shouldMute }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId: userId,
            action: shouldMute ? 'room.mute_participant' : 'room.unmute_participant',
            after: { muted: shouldMute },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ muted: shouldMute });
    } catch (error) {
        next(error);
    }
};

exports.unmuteParticipant = async (req, res, next) => {
    req.body = { ...(req.body || {}), muted: false };
    return exports.muteParticipant(req, res, next);
};

// @desc    Kick a participant
exports.kickParticipant = async (req, res, next) => {
    try {
        const { id, userId } = req.params;
        const { reason } = req.body;

        const room = await Room.findById(id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        applyKickParticipant({ room, actorUserId: req.userId, targetUserId: userId });
        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, userId, 'leave');

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:left', {
                roomId: room._id.toString(),
                userId
            });
            io.to(`user:${userId}`).emit('user:kicked', { roomId: room._id, reason: reason || null });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'participant_left',
                extraPayload: { userId, kicked: true }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId: userId,
            action: 'room.kick_participant',
            after: { reason: reason || null },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

// @desc    Add admin (moderator) to room
exports.addAdmin = async (req, res, next) => {
    try {
        const { id } = req.params;
        const { userId } = req.body;

        if (!userId) {
            const error = new Error('userId is required');
            error.status = 400;
            throw error;
        }

        const room = await Room.findById(id);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        if (room.hostId.toString() !== req.userId) {
            const error = new Error('Only host can add admins');
            error.status = 403;
            throw error;
        }

        const targetUser = await User.findById(userId).select('_id');
        if (!targetUser) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!room.moderators) room.moderators = [];
        const adminLimit = getRoomAdminLimit(room.level);
        if (room.moderators.length >= adminLimit) {
            const error = new Error('Max admins reached');
            const nextUnlockLevel = getNextAdminUnlockLevel(room.level);
            error.message = nextUnlockLevel == null
                ? `This room already has the max ${adminLimit} admins.`
                : `Room level ${room.level} allows ${adminLimit} admins. Reach level ${nextUnlockLevel} to unlock 5 admins.`;
            error.status = 400;
            throw error;
        }

        const alreadyAdmin = room.moderators.some(id => id.toString() === userId);
        if (!alreadyAdmin) {
            room.moderators.push(userId);
        }

        const participant = room.participants.find(p => p.userId.toString() === userId);
        if (participant) participant.role = 'moderator';

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('admin:added', { userId });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'roles_updated',
                extraPayload: { userId, role: 'moderator' }
            });
        }

        res.json({ admins: room.moderators });
    } catch (error) {
        next(error);
    }
};
