const Room = require('../models/Room');
const User = require('../models/User');
const Transaction = require('../models/Transaction');
const { AccessToken } = require('livekit-server-sdk');
const economyController = require('./economyController');
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
        participantCount: room.participantCount ?? room.participants?.length ?? 0,
        onlineCount: room.onlineCount ?? 0,
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

        const query = { endedAt: null };

        if (category && category !== 'all') query.category = category;
        if (type) query.type = type;
        if (search) {
            const normalizedSearch = escapeRegex(String(search).trim());
            if (normalizedSearch) {
                query.$or = [
                    { name: { $regex: normalizedSearch, $options: 'i' } },
                    { roomId: { $regex: normalizedSearch, $options: 'i' } }
                ];
            }
        }
        if (tag) query.tags = tag;

        const sortOptions = {};
        if (sort === 'onlineCount') sortOptions.onlineCount = -1;
        else if (sort === 'newest') sortOptions.createdAt = -1;
        else if (sort === 'oldest') sortOptions.createdAt = 1;

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
                    : 'Admins can only change live safety controls such as text chat, photo chat, high quality audio, and stage lock'
            );
            error.status = 403;
            throw error;
        }

        const allowedUpdates = ['name', 'description', 'type', 'category', 'tags', 'settings', 'theme', 'announcement'];
        allowedUpdates.forEach(field => {
            if (patch[field] !== undefined) {
                if (field === 'settings') {
                    room.settings = { ...room.settings, ...patch.settings };
                } else if (field === 'theme') {
                    room.theme = { ...room.theme, ...patch.theme };
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

        res.json({ token, serverUrl: process.env.LIVEKIT_URL || 'ws://localhost:7880' });
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

        const occupied = room.participants.find(p => p.seatIndex === seatIndex);
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

exports.getTrendingRooms = async (req, res, next) => {
    try {
        const rooms = await Room.find({ endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({ onlineCount: -1, participantCount: -1 })
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
        const rooms = await Room.find({ 'participants.userId': req.userId, endedAt: null })
            .populate('hostId', 'username avatar level')
            .sort({ updatedAt: -1 });
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
        if (room.moderators.length >= 5) {
            const error = new Error('Max admins reached');
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
