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
    canJoinStageDirectly,
    canManageStage,
    canManageTarget,
    countActiveSpeakers,
    getMaxActiveSpeakers,
    getParticipant,
    isRoomAdmin,
    isRoomOwner,
    sanitizeRoomUpdatePayload
} = require('../utils/roomPermissions');

const roomCacheKey = (roomId) => `cache:room:${roomId}`;
const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const RALLY_DURATION_MS = 5 * 60 * 1000;
const STREAM_ROOM_TYPE = 'video';
const STREAM_HOST_SEAT_INDEX = 1;
const STREAM_PLAYBACK_STATES = new Set(['paused', 'playing']);
const YOUTUBE_SEARCH_RESULT_LIMIT = 12;
const ROOM_INVITE_MESSAGE_TYPE = 'system';

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
        videoId: String(entry.videoId || '').trim(),
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
        theme.youtubePositionMs = 0;
        theme.youtubePlaybackState = 'paused';
        return null;
    }

    theme.youtubeUrl = current.url;
    theme.youtubeTitle = current.title || '';
    theme.youtubeThumbnail = current.thumbnailUrl || '';
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

    return patch;
};

const resetSeatsForStreamMode = (room) => {
    if (!room) return;

    room.lockedSeats = (room.lockedSeats || []).filter(
        (seatIndex) => seatIndex !== STREAM_HOST_SEAT_INDEX
    );

    const hostId = room.hostId?.toString();
    let hostParticipant = null;
    room.participants = (room.participants || []).map((participant) => {
        participant.raisedHand = false;

        if (participant.userId?.toString() === hostId) {
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
            seatIndex: STREAM_HOST_SEAT_INDEX,
            joinedAt: new Date(),
            lastActive: new Date(),
            raisedHand: false
        });
    }
};

const anchorHostToStreamSeat = (room) => {
    if (!room || room.type !== STREAM_ROOM_TYPE) return;

    const hostId = room.hostId?.toString();
    if (!hostId) return;

    room.lockedSeats = (room.lockedSeats || []).filter(
        (seatIndex) => seatIndex !== STREAM_HOST_SEAT_INDEX
    );

    let hostParticipant = null;
    room.participants = (room.participants || []).map((participant) => {
        if (participant.userId?.toString() === hostId) {
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

    if (!hostParticipant) {
        room.participants.unshift({
            userId: room.hostId,
            role: 'host',
            seatIndex: STREAM_HOST_SEAT_INDEX,
            joinedAt: new Date(),
            lastActive: new Date(),
            raisedHand: false
        });
    }
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
    const filters = [{ endedAt: null }, { showInExplore: { $ne: false } }];

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

const emitLobbyUpdate = (io, room, action = 'updated') => {
    if (!io || !room) return;

    const roomId = room._id?.toString() || room.id?.toString() || room.roomId?.toString();
    if (!roomId) return;

    io.emit('room:lobby:update', {
        roomId,
        action,
        name: room.name,
        category: room.category,
        type: room.type,
        hostAvatar: room.hostId?.avatar || room.hostAvatar || '',
        coverImage: room.theme?.coverImage || room.coverImage || '',
        participantCount: room.participantCount ?? room.participants?.length ?? 0,
        onlineCount: room.onlineCount ?? 0,
        rallyActive: room.rallyActive === true &&
            (!room.rallyExpiresAt || new Date(room.rallyExpiresAt) > new Date()),
        rallyExpiresAt: room.rallyExpiresAt || null,
        endedAt: room.endedAt || null,
        updatedAt: new Date().toISOString()
    });
};

const populateRoomById = async (roomId) => Room.findById(roomId)
    .populate('hostId', 'username avatar level vipLevel')
    .populate('coHosts', 'username avatar level vipLevel')
    .populate('moderators', 'username avatar level vipLevel')
    .populate('participants.userId', 'username avatar level vipLevel status.isOnline')
    .populate('bans.userId', 'username avatar');

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

// @desc    Create a new room
// @route   POST /api/rooms
// @access  Private
exports.createRoom = async (req, res, next) => {
    try {
        const {
            name,
            description,
            type,
            category,
            tags,
            settings,
            theme
        } = req.body;

        const room = new Room({
            name,
            description: description || '',
            type: type || 'voice',
            category: category || 'all',
            tags: tags || [],
            hostId: req.userId,
            settings: {
                isPrivate: settings?.isPrivate || false,
                password: settings?.password,
                maxParticipants: settings?.maxParticipants || 20,
                entryFee: settings?.entryFee || 0,
                hdVoice: settings?.hdVoice || false,
                banTextChat: settings?.banTextChat || false,
                banPhotoChat: settings?.banPhotoChat || false,
                banRedPacket: settings?.banRedPacket || false,
                allowGifts: settings?.allowGifts ?? true,
                allowScreenShare: settings?.allowScreenShare || false,
                allowVideo: settings?.allowVideo || false,
                stageJoinsLocked: settings?.stageJoinsLocked || false,
                maxActiveSpeakers: settings?.maxActiveSpeakers || 8,
                requireApproval: settings?.requireApproval || false,
                slowMode: settings?.slowMode || 0,
                ageRestricted: settings?.ageRestricted || false
            },
            theme: theme || { background: 'default' },
            participants: [{
                userId: req.userId,
                role: 'host',
                joinedAt: Date.now()
            }]
        });

        if (room.type === STREAM_ROOM_TYPE) {
            resetSeatsForStreamMode(room);
        }

        await room.save();

        const populatedRoom = await populateRoomById(room._id);

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, req.userId, 'join');

        const livekitToken = await buildLivekitToken(
            populatedRoom.roomId || populatedRoom._id,
            req.userId,
            populatedRoom.hostId?.username,
            populatedRoom.hostId?.avatar
        );
        const roomPayload = populatedRoom.toObject();

        const io = req.app.get('io');
        if (io) {
            io.emit('room:created', roomPayload);
            emitLobbyUpdate(io, roomPayload, 'created');
        }

        res.status(201).json({ ...roomPayload, livekitToken });
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
                return res.json(parsed);
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

        res.json(room);
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

        if (room.participants.length >= room.settings.maxParticipants) {
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
        if (didJoinRoom) {
            let role = 'listener';
            if (room.hostId.toString() === req.userId) role = 'host';
            else if (room.coHosts?.some(id => id.toString() === req.userId)) role = 'cohost';
            else if (room.moderators?.some(id => id.toString() === req.userId)) role = 'moderator';

            room.participants.push({
                userId: req.userId,
                role,
                joinedAt: Date.now(),
                lastActive: Date.now()
            });

            if (room.participants.length > room.metrics.peakParticipants) {
                room.metrics.peakParticipants = room.participants.length;
            }
        } else {
            room.participants[existingIdx].lastActive = Date.now();
        }

        anchorHostToStreamSeat(room);

        await room.save();

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
                userId: req.userId,
                username: user.username,
                avatar: user.avatar,
                joinedAt: Date.now()
            });
            // Update balance for the user
            io.to(`user:${user._id}`).emit('balance_update', { coins: user.coins, gems: user.gems });
            emitLobbyUpdate(io, populatedRoom, 'participant_joined');
        }

        const roomPayload = populatedRoom.toObject();
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
            room.endedAt = Date.now();
        } else if (room.hostId.toString() === req.userId) {
            // Assign new host
            let newHostP = room.participants.find(p => room.coHosts?.some(id => id.toString() === p.userId.toString())) ||
                room.participants.find(p => room.moderators?.some(id => id.toString() === p.userId.toString())) ||
                room.participants[0];

            if (newHostP) {
                room.hostId = newHostP.userId;
                newHostP.role = 'host';
            }
        }

        anchorHostToStreamSeat(room);

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, req.userId, 'leave');

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:left', { userId: req.userId });
            io.to(`room:${room._id}`).emit('room:updated', room);
            emitLobbyUpdate(io, room, room.endedAt ? 'ended' : 'participant_left');
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

        const previousType = room.type;
        const previousYoutubeUrl = room.theme?.youtubeUrl || '';
        const normalizedThemePatch = normalizeThemePatch(patch.theme);
        const allowedUpdates = ['name', 'description', 'type', 'category', 'tags', 'settings', 'theme', 'announcement'];
        allowedUpdates.forEach(field => {
            if (patch[field] !== undefined) {
                if (field === 'settings') {
                    room.settings = { ...room.settings, ...patch.settings };
                } else if (field === 'theme') {
                    room.theme = { ...room.theme, ...normalizedThemePatch };
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
        const youtubeVideoChanged =
            (
                normalizedThemePatch.youtubeQueue !== undefined ||
                normalizedThemePatch.youtubeUrl !== undefined ||
                normalizedThemePatch.youtubeTitle !== undefined ||
                normalizedThemePatch.youtubeThumbnail !== undefined
            ) &&
            nextYoutubeUrl !== previousYoutubeUrl;
        const youtubePlaybackPatchProvided =
            normalizedThemePatch.youtubePositionMs !== undefined ||
            normalizedThemePatch.youtubePlaybackState !== undefined;

        if (room.type === STREAM_ROOM_TYPE) {
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
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'updated');
        }

        res.json(populatedRoom);
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
        if (seatIndex > maxActiveSpeakers) {
            const error = new Error(`Only ${maxActiveSpeakers} active speaker seats are open right now`);
            error.status = 403;
            throw error;
        }

        if ((room.lockedSeats || []).includes(seatIndex)) {
            const error = new Error('This seat is locked');
            error.status = 403;
            throw error;
        }

        const occupied = room.participants.find(
            (p) => p.seatIndex === seatIndex && p.userId.toString() !== req.userId
        );
        if (occupied) {
            const error = new Error('Seat already occupied');
            error.status = 400;
            throw error;
        }

        const participant = getParticipant(room, req.userId);
        if (!participant) {
            const error = new Error('User not in room');
            error.status = 400;
            throw error;
        }

        if (participant.seatIndex === seatIndex) {
            const populatedRoom = await populateRoomById(room._id);
            res.json(populatedRoom);
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
                io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
                emitLobbyUpdate(io, populatedRoom, 'stage_request');
            }

            res.json(populatedRoom);
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
                io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
                emitLobbyUpdate(io, populatedRoom, 'seat_updated');
            }

            res.json(populatedRoom);
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
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'seat_updated');
        }

        res.json(populatedRoom);
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
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'seat_updated');
        }

        res.json(populatedRoom);
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

        const results = (searchResponse.videos || [])
            .slice(0, YOUTUBE_SEARCH_RESULT_LIMIT)
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
            .filter((video) => video.id);

        res.json({ results });
    } catch (error) {
        next(error);
    }
};

exports.getTrendingRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const rooms = await Room.find({ endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({ rallyActive: -1, rallyExpiresAt: -1, onlineCount: -1, participantCount: -1 })
            .limit(10);
        res.json(rooms);
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
        room.endedAt = Date.now();
        await room.save();
        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:deleted', { roomId: room._id });
            emitLobbyUpdate(io, room, 'deleted');
        }
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

exports.getMyRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const rooms = await Room.find({ 'participants.userId': req.userId, endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({ rallyActive: -1, rallyExpiresAt: -1, updatedAt: -1 });
        res.json(rooms);
    } catch (error) {
        next(error);
    }
};

exports.getFollowedRooms = async (req, res, next) => {
    try {
        await cleanupExpiredRallies();
        const rooms = await Room.find({ followers: req.userId, endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({ rallyActive: -1, rallyExpiresAt: -1, updatedAt: -1 });
        res.json(rooms);
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

        if (!canManageStage(room, req.userId)) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        if (!canManageTarget(room, req.userId, userId)) {
            const error = new Error('You cannot moderate that participant');
            error.status = 403;
            throw error;
        }

        const participant = getParticipant(room, userId);
        if (!participant) {
            const error = new Error('User not in room');
            error.status = 404;
            throw error;
        }

        const shouldMute = muted === undefined ? true : Boolean(muted);
        participant.isMuted = shouldMute;

        if (shouldMute) {
            const exists = room.mutes?.some(m => m.userId.toString() === userId);
            if (!exists) {
                room.mutes.push({ userId });
            }
        } else {
            room.mutes = (room.mutes || []).filter(m => m.userId.toString() !== userId);
        }

        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:muted', { userId, muted: shouldMute });
            io.to(`user:${userId}`).emit('room:mute', { roomId: room._id, muted: shouldMute });
            emitLobbyUpdate(io, room, 'moderation_updated');
        }

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

        if (!canManageStage(room, req.userId)) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        if (!canManageTarget(room, req.userId, userId)) {
            const error = new Error('You cannot remove that participant');
            error.status = 403;
            throw error;
        }

        const beforeCount = room.participants.length;
        room.participants = room.participants.filter(p => p.userId.toString() !== userId);
        if (room.participants.length === beforeCount) {
            const error = new Error('User not in room');
            error.status = 404;
            throw error;
        }
        await room.save();

        const redis = req.app.get('redis');
        await invalidateRoomCache(redis, room._id);
        await updateRoomPresence(redis, room._id, userId, 'leave');

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:left', { userId });
            io.to(`user:${userId}`).emit('user:kicked', { roomId: room._id, reason: reason || null });
            emitLobbyUpdate(io, room, 'participant_left');
        }

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
            emitLobbyUpdate(io, room, 'roles_updated');
        }

        res.json({ admins: room.moderators });
    } catch (error) {
        next(error);
    }
};
