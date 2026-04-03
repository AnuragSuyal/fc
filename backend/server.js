'use strict';

const express      = require('express');
const mongoose     = require('mongoose');
const cors         = require('cors');
const { Server }   = require('socket.io');
const http         = require('http');
const redis        = require('redis');
require('./src/config/env');
const passport     = require('./src/config/passport');

const connectDB = require('./src/config/db');
const { backfillMissingUserUids } = require('./src/services/userUidService');

const app = express();

const helmet         = require('helmet');
const mongoSanitize  = require('express-mongo-sanitize');
const xss            = require('xss-clean');
const hpp            = require('hpp');
const compression    = require('compression');
const { apiLimiter } = require('./src/middleware/rateLimit');
const requestLogger  = require('./src/middleware/requestLogger');
const RALLY_DURATION_MS = 5 * 60 * 1000;
const ROOM_STAGE_FEATURE_LABELS = {
    aura_pick: 'Aura Pick',
    crown_drop: 'Crown Drop',
    number_rush: 'Number Rush',
    fortune_digits: 'Fortune Digits'
};

function pickRandomItem(items = []) {
    if (!Array.isArray(items) || items.length === 0) return null;
    return items[Math.floor(Math.random() * items.length)] || null;
}

function buildUniqueNumbers({ count, min, max }) {
    const values = new Set();
    while (values.size < count) {
        const value = Math.floor(Math.random() * (max - min + 1)) + min;
        values.add(value);
    }
    return Array.from(values).sort((a, b) => a - b);
}

function normalizeRoomParticipants(room, socket) {
    const participants = Array.isArray(room?.participants)
        ? room.participants.map((entry) => {
            const user = entry?.userId && typeof entry.userId === 'object'
                ? entry.userId
                : null;

            return {
                userId: user?._id?.toString() || entry?.userId?.toString() || '',
                username: user?.username || 'Guest',
                avatar: user?.avatar || '',
                role: entry?.role || 'listener',
                seatIndex: Number.isInteger(entry?.seatIndex) ? entry.seatIndex : -1,
                contribution: Number(entry?.contribution || 0)
            };
        }).filter((participant) => participant.userId)
        : [];

    if (!participants.some((participant) => participant.userId === socket.userId)) {
        participants.unshift({
            userId: socket.userId,
            username: socket.username || 'Guest',
            avatar: socket.avatar || '',
            role: 'listener',
            seatIndex: -1,
            contribution: 0
        });
    }

    return participants;
}

function buildRoomStageFeaturePayload({ featureId, room, participants, socket }) {
    const featureName = ROOM_STAGE_FEATURE_LABELS[featureId];
    if (!featureName) return null;

    const actor = {
        userId: socket.userId,
        username: socket.username || 'Someone',
        avatar: socket.avatar || ''
    };
    const speakers = participants.filter((participant) =>
        participant.seatIndex >= 0 ||
        ['host', 'cohost', 'moderator', 'speaker'].includes(participant.role)
    );

    if (featureId === 'aura_pick') {
        const winner = pickRandomItem(participants) || actor;
        return {
            roomId: room._id.toString(),
            featureId,
            featureName,
            actor,
            winner,
            summary: `${actor.username} launched Aura Pick. ${winner.username} caught the spotlight.`,
            detail: `${winner.username} is the room's fresh spotlight pick for this round.`,
            triggeredAt: new Date().toISOString()
        };
    }

    if (featureId === 'crown_drop') {
        const highestContribution = participants.reduce(
            (max, participant) => Math.max(max, participant.contribution || 0),
            0
        );
        const contributionLeaders = highestContribution > 0
            ? participants.filter((participant) => participant.contribution === highestContribution)
            : [];
        const winnerPool = contributionLeaders.length > 0
            ? contributionLeaders
            : (speakers.length > 0 ? speakers : participants);
        const winner = pickRandomItem(winnerPool) || actor;
        const detail = highestContribution > 0
            ? `${winner.username} leads the room right now with ${highestContribution} room points.`
            : `${winner.username} gets the live-stage crown for this round.`;

        return {
            roomId: room._id.toString(),
            featureId,
            featureName,
            actor,
            winner,
            summary: `${actor.username} dropped a Crown Drop. ${winner.username} takes the crown.`,
            detail,
            triggeredAt: new Date().toISOString()
        };
    }

    if (featureId === 'number_rush') {
        const numbers = buildUniqueNumbers({ count: 5, min: 1, max: 60 });
        return {
            roomId: room._id.toString(),
            featureId,
            featureName,
            actor,
            numbers,
            summary: `${actor.username} fired Number Rush: ${numbers.map((number) => number.toString().padStart(2, '0')).join(' • ')}.`,
            detail: 'Everyone sees the same fast board numbers in realtime.',
            triggeredAt: new Date().toISOString()
        };
    }

    if (featureId === 'fortune_digits') {
        const luckyNumber = buildUniqueNumbers({ count: 1, min: 1, max: 99 })[0];
        return {
            roomId: room._id.toString(),
            featureId,
            featureName,
            actor,
            luckyNumber,
            summary: `${actor.username} unlocked Fortune Digits ${luckyNumber.toString().padStart(2, '0')}.`,
            detail: `Today's room fortune number landed on ${luckyNumber}.`,
            triggeredAt: new Date().toISOString()
        };
    }

    return null;
}

// ── Redis ───────────────────────────────────────────────────────────────────────
const redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
redisClient.on('error', err => console.error('Redis Client Error', err));
redisClient.on('connect', () => console.log('✅ Redis Connected'));
redisClient.connect().catch(err => console.error('Redis initial connect error:', err.message));
app.set('redis', redisClient);

// ── Ranking service ─────────────────────────────────────────────────────────────
const rankingService = require('./src/services/rankingService');
const economyController = require('./src/controllers/economyController');
const registerColorClashSocket = require('./src/socket/colorClashSocket');
const registerDragonPacketSocket = require('./src/socket/dragonPacketSocket');
const {
    ROOM_ACTIONS,
    canPerformRoomAction,
    isRoomOwner
} = require('./src/services/roomPermissionService');
const { findGiftByIdentifier, syncGiftCatalog } = require('./src/services/giftCatalogService');
const {
    ROOM_UPDATE_EVENTS,
    emitRoomUpdate
} = require('./src/services/roomSettingsService');
const {
    markParticipantPresence,
    recalculateRoomPresenceState
} = require('./src/services/roomPresenceService');
const {
    appendPendingStroke,
    beginPendingStroke,
    buildMiniDrawSummary,
    clearPendingStrokesForSocket,
    commitPendingStroke
} = require('./src/services/miniDrawService');
const {
    awardUserXp,
    buildProgressPayload,
    emitLevelDrivenRealtime
} = require('./src/services/levelProgressionService');
const {
    initializeDragonPacketRuntime
} = require('./src/services/dragonPacketService');
rankingService.initialize({ redisClient }).catch(console.error);

// ── Security headers ────────────────────────────────────────────────────────────
app.use(helmet());

// ── CORS ────────────────────────────────────────────────────────────────────────
const allowedOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',')
    : ['*'];
app.use(cors({
    origin: (origin, cb) => {
        if (!origin || allowedOrigins.includes('*') || allowedOrigins.includes(origin)) cb(null, true);
        else cb(new Error('Not allowed by CORS'));
    },
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Idempotency-Key', 'X-Idempotency-Key'],
    credentials: true
}));

// ── Logging & Rate-limiting ─────────────────────────────────────────────────────
app.use(requestLogger);
app.use('/api', apiLimiter);

// ── Performance ─────────────────────────────────────────────────────────────────
app.use(compression());

// ── Body parsing (webhook routes must stay raw) ─────────────────────────────────
app.use('/api/payments/webhook', express.raw({ type: 'application/json' }));
app.use('/webhooks/stripe',      express.raw({ type: 'application/json' }));
app.use('/webhooks/livekit',     express.text({ type: '*/*' }));
app.use(express.json({ limit: '10kb' }));
app.use(express.urlencoded({ extended: true, limit: '10kb' }));

// ── Sanitization ────────────────────────────────────────────────────────────────
// app.use(mongoSanitize());
// app.use(xss());
// app.use(hpp({ whitelist: ['sort', 'fields', 'page', 'limit', 'category', 'type', 'tag'] }));

// ── Auth ────────────────────────────────────────────────────────────────────────
app.use(passport.initialize());

// ── DB ──────────────────────────────────────────────────────────────────────────
connectDB()
    .then(() => backfillMissingUserUids().catch(() => {}));

// ── Routes ──────────────────────────────────────────────────────────────────────
const paymentRoutes  = require('./src/routes/paymentRoutes');
const authRoutes     = require('./src/routes/authRoutes');
const roomRoutes     = require('./src/routes/roomRoutes');
const giftRoutes     = require('./src/routes/giftRoutes');
const vipRoutes      = require('./src/routes/vipRoutes');
const economyRoutes  = require('./src/routes/economyRoutes');
const postRoutes     = require('./src/routes/postRoutes');
const groupRoutes    = require('./src/routes/groupRoutes');
const locationRoutes = require('./src/routes/locationRoutes');
const friendRoutes   = require('./src/routes/friendRoutes');
const messageRoutes  = require('./src/routes/messageRoutes');
const walletRoutes   = require('./src/routes/walletRoutes');
const settingsRoutes = require('./src/routes/settingsRoutes');
const profileRoutes  = require('./src/routes/profileRoutes');
const rankingRoutes  = require('./src/routes/rankingRoutes');
const uploadRoutes   = require('./src/routes/uploadRoutes');
const userRoutes     = require('./src/routes/userRoutes');
const colorClashRoutes = require('./src/routes/colorClashRoutes');
const shopRoutes     = require('./src/routes/shopRoutes');
const coinTransferRoutes = require('./src/routes/coinTransferRoutes');
const dragonPacketRoutes = require('./src/routes/dragonPacketRoutes');
const dragonEventRoutes = require('./src/routes/dragonEventRoutes');
// const livekitRoutes  = require('./src/routes/livekitRoutes');
// const webhookRoutes  = require('./src/routes/webhookRoutes');

app.use('/api/auth',      authRoutes);
app.use('/api/payments',  paymentRoutes);
app.use('/api/rooms',     roomRoutes);
app.use('/api/gifts',     giftRoutes);
app.use('/api/vip',       vipRoutes);
app.use('/api/messages',  (req, _res, next) => { req.io = req.app.get('io'); next(); }, messageRoutes);
app.use('/api/wallet',    walletRoutes);
app.use('/api/economy',   economyRoutes);
app.use('/api/posts',     postRoutes);
app.use('/api/groups',    groupRoutes);
app.use('/api/location',  locationRoutes);
app.use('/api/friends',   friendRoutes);
app.use('/api/settings',  settingsRoutes);
app.use('/api/profile',   profileRoutes);
app.use('/api/rankings',  rankingRoutes);
app.use('/api/uploads',   uploadRoutes);
app.use('/api/users',     userRoutes);
app.use('/api/shop',      shopRoutes);
app.use('/api/coin-transfer', coinTransferRoutes);
app.use('/api/dragon-packets', dragonPacketRoutes);
app.use('/api/dragon-events', dragonEventRoutes);
app.use('/api/color-clash', colorClashRoutes);
// app.use('/api/livekit',   livekitRoutes);
// app.use('/webhooks',      webhookRoutes);
const weddingRoutes = require('./src/routes/weddingRoutes');
app.use('/api/wedding', weddingRoutes);

// ── Health ──────────────────────────────────────────────────────────────────────
const healthHandler = async (_req, res) => {
    try {
        const mongoOk = mongoose.connection.readyState === 1;
        let redisOk   = false;
        try { redisOk = redisClient.isReady && (await redisClient.ping()) === 'PONG'; } catch (_) {}
        const status  = mongoOk && redisOk ? 'ok' : 'degraded';
        res.status(mongoOk ? 200 : 503).json({
            status,
            services: { mongodb: mongoOk ? 'connected' : 'disconnected', redis: redisOk ? 'connected' : 'disconnected' },
            uptime: process.uptime()
        });
    } catch (err) {
        res.status(503).json({ status: 'error', message: err.message });
    }
};
app.get('/',           (_req, res) => res.send('🚀 Friend Circle API is running'));
app.get('/health',     healthHandler);
app.get('/api/health', healthHandler);

// ── Global error handler ────────────────────────────────────────────────────────
const { errorMiddleware } = require('./src/middleware/errorMiddleware');
app.use(errorMiddleware);

// ── HTTP + Socket.IO ────────────────────────────────────────────────────────────
const server = http.createServer(app);

const { createAdapter } = require('@socket.io/redis-adapter');
const pubClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
const subClient = pubClient.duplicate();

const io = new Server(server, {
    cors: { origin: '*', methods: ['GET', 'POST'] },
    pingTimeout: 60000,
    pingInterval: 25000,
    transports: ['websocket', 'polling']
});

Promise.all([pubClient.connect(), subClient.connect()])
    .then(() => {
        io.adapter(createAdapter(pubClient, subClient));
        console.log('✅ Socket.IO Redis Adapter connected');
    })
    .catch(err => console.error('Socket.IO Redis adapter error (continuing without):', err.message));

app.set('io', io);
initializeDragonPacketRuntime({ io, redis: redisClient });

// ── Socket.IO auth middleware ───────────────────────────────────────────────────
io.use(async (socket, next) => {
    try {
        const token = socket.handshake.auth.token ||
                      socket.handshake.headers.authorization?.replace('Bearer ', '');
        if (!token) return next(new Error('Authentication required'));

        const jwt     = require('jsonwebtoken');
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        socket.userId = decoded.userId;

        const User = require('./src/models/User');
        const user = await User.findById(decoded.userId).select('username avatar friends');
        if (!user) return next(new Error('User not found'));

        socket.username  = user.username;
        socket.avatar    = user.avatar;
        socket.friendIds = (user.friends || []).map(id => id.toString());
        next();
    } catch (err) {
        next(new Error('Invalid token'));
    }
});

// ── Helper: broadcast presence event to all friends ────────────────────────────
function broadcastToFriends(socket, event, extraData = {}) {
    if (!socket.friendIds?.length) return;
    const payload = { userId: socket.userId, username: socket.username, avatar: socket.avatar, ...extraData };
    socket.friendIds.forEach(fid => io.to(`user:${fid}`).emit(event, payload));
}

const activeSocketIdsByUserId = new Map();
const roomCacheKey = (roomId) => `cache:room:${roomId}`;
const STREAM_ROOM_TYPE = 'video';
const STREAM_HOST_SEAT_INDEX = 1;

const invalidateRoomCache = async (roomId) => {
    if (!roomId || !redisClient.isReady) return;
    await redisClient.del(roomCacheKey(roomId.toString())).catch(() => {});
};

const syncStreamHostSeat = (room) => {
    if (!room || room.type !== STREAM_ROOM_TYPE) return;
    const hostId = room.hostId?.toString();
    if (!hostId) return;

    let hostParticipant = null;
    room.participants = (room.participants || []).map((participant) => {
        if (participant.userId?.toString() === hostId && participant.isPresent !== false) {
            participant.seatIndex = STREAM_HOST_SEAT_INDEX;
            participant.role = 'host';
            hostParticipant = participant;
            return participant;
        }

        if (participant.seatIndex === STREAM_HOST_SEAT_INDEX) {
            participant.seatIndex = -1;
            participant.isSpeaking = false;
            participant.raisedHand = false;
            if (participant.role === 'speaker') {
                participant.role = 'listener';
            }
        }

        return participant;
    });

    if (!hostParticipant) {
        return;
    }
};

const syncSocketRoomParticipantPresence = async ({
    roomId,
    userId,
    present,
    lobbyAction
}) => {
    if (!roomId || !userId) return null;

    try {
        const Room = require('./src/models/Room');
        const room = await Room.findById(roomId);
        if (!room) return null;

        const participant = room.participants?.find(
            (entry) => entry.userId?.toString() === userId.toString()
        );
        if (!participant) return null;

        if ((participant.isPresent !== false) === present) {
            return room;
        }

        markParticipantPresence(room, userId, { present });
        recalculateRoomPresenceState(room);
        syncStreamHostSeat(room);
        await room.save();
        await invalidateRoomCache(room._id);

        emitRoomUpdate(io, room, {
            updateEvent: ROOM_UPDATE_EVENTS.ROLES,
            lobbyAction,
            extraPayload: {
                userId,
                present,
                hostPresent: room.hostPresent === true,
                adminCount: Number(room.adminCount || 0),
                activeControllersCount: Number(room.activeControllersCount || 0),
                roomActive: room.roomActive !== false,
                inactiveSince: room.inactiveSince || null
            }
        });

        return room;
    } catch (error) {
        console.error('syncSocketRoomParticipantPresence error:', error.message);
        return null;
    }
};

// ── Socket.IO connection ────────────────────────────────────────────────────────
io.on('connection', (socket) => {
    console.log('🔌 User connected:', socket.userId);

    socket.joinedRoomIds = new Set();
    socket.joinedProfileIds = new Set();
    socket.activePresenceRoomIds = new Set();
    const voiceStateByRoom = new Map();
    const questHeartbeatByRoom = new Map();
    socket.join(`user:${socket.userId}`);
    const isActiveRoomParticipant = (roomId) => socket.activePresenceRoomIds.has(roomId);
    const resolvedUserId = socket.userId.toString();
    const activeSocketsForUser = activeSocketIdsByUserId.get(resolvedUserId) || new Set();
    const wasOfflineBeforeConnect = activeSocketsForUser.size === 0;
    activeSocketsForUser.add(socket.id);
    activeSocketIdsByUserId.set(resolvedUserId, activeSocketsForUser);

    registerColorClashSocket({
        io,
        socket,
        redis: redisClient
    });
    registerDragonPacketSocket({
        io,
        socket,
        redis: redisClient,
        isActiveRoomParticipant
    });

    // Mark online
    (async () => {
        try {
            if (!wasOfflineBeforeConnect) return;
            if (redisClient.isReady) await redisClient.sAdd('online:users', resolvedUserId);
            const User = require('./src/models/User');
            await User.findByIdAndUpdate(socket.userId, {
                'status.isOnline': true, 'status.lastActive': new Date()
            });
            broadcastToFriends(socket, 'friend:online');
        } catch (err) { console.error('markOnline error:', err.message); }
    })();

    // ── Room join / leave ─────────────────────────────────────────────────────
    const joinRoom = async (data) => {
        const roomId = typeof data === 'string' ? data : data?.roomId;
        if (!roomId) return;

        let isParticipant = false;
        try {
            const Room = require('./src/models/Room');
            const room = await Room.findOne({
                _id: roomId,
                'participants.userId': socket.userId
            }).select('_id');
            isParticipant = !!room;
        } catch (err) {
            console.error('room join membership check failed:', err.message);
        }

        if (!isParticipant) return;

        socket.join(`room:${roomId}`);
        socket.currentRoomId = roomId;
        socket.joinedRoomIds.add(roomId);
        socket.activePresenceRoomIds.add(roomId);
        await syncSocketRoomParticipantPresence({
            roomId,
            userId: socket.userId,
            present: true,
            lobbyAction: 'participant_joined'
        });
        io.to(`room:${roomId}`).emit('user_joined', {
            roomId,
            userId: socket.userId,
            username: socket.username,
            avatar: socket.avatar
        });
        if (redisClient.isReady) {
            const key = `room:${roomId}:users`;
            redisClient.sAdd(key, socket.userId.toString())
                .then(() => redisClient.sCard(key))
                .then(cnt => redisClient.set(`room:${roomId}:count`, cnt.toString()))
                .catch(() => {});
        }
    };

    const leaveRoom = (data) => {
        const roomId = typeof data === 'string' ? data : data?.roomId;
        if (!roomId) return;
        socket.leave(`room:${roomId}`);
        socket.joinedRoomIds.delete(roomId);
        const hadPresence = socket.activePresenceRoomIds.has(roomId);
        socket.activePresenceRoomIds.delete(roomId);
        voiceStateByRoom.delete(roomId);
        questHeartbeatByRoom.delete(roomId);
        if (socket.currentRoomId === roomId) socket.currentRoomId = null;
        if (!hadPresence) return;
        void syncSocketRoomParticipantPresence({
            roomId,
            userId: socket.userId,
            present: false,
            lobbyAction: 'participant_left'
        });
        io.to(`room:${roomId}`).emit('user_left', { roomId, userId: socket.userId });
        if (redisClient.isReady) {
            const key = `room:${roomId}:users`;
            redisClient.sRem(key, socket.userId.toString())
                .then(() => redisClient.sCard(key))
                .then(cnt => redisClient.set(`room:${roomId}:count`, cnt.toString()))
                .catch(() => {});
        }
    };

    socket.on('room:join',  joinRoom);
    socket.on('join_room',  d => joinRoom(d));
    socket.on('room:leave', leaveRoom);
    socket.on('leave_room', d => leaveRoom(d));

    // ── Groups ────────────────────────────────────────────────────────────────
    socket.on('group:join',  async ({ groupId } = {}) => {
        if (!groupId) return;
        try {
            const Group = require('./src/models/Group');
            const group = await Group.findOne({
                _id: groupId,
                'members.userId': socket.userId
            }).select('_id');
            if (!group) return;
        } catch (err) {
            console.error('group join membership check failed:', err.message);
            return;
        }
        socket.join(`group:${groupId}`);
        io.to(`group:${groupId}`).emit('user_joined', { userId: socket.userId, username: socket.username });
    });
    socket.on('group:leave', ({ groupId } = {}) => {
        if (!groupId) return;
        socket.leave(`group:${groupId}`);
    });
    socket.on('profile:join', ({ userId } = {}) => {
        if (!userId) return;
        const resolvedUserId = userId.toString();
        socket.join(`profile:${resolvedUserId}`);
        socket.joinedProfileIds.add(resolvedUserId);
    });
    socket.on('profile:leave', ({ userId } = {}) => {
        if (!userId) return;
        const resolvedUserId = userId.toString();
        socket.leave(`profile:${resolvedUserId}`);
        socket.joinedProfileIds.delete(resolvedUserId);
    });

    // ── Room chat ─────────────────────────────────────────────────────────────
    socket.on('room:message', async (data) => {
        const { roomId, content, type = 'text', emojis, seatIndex } = data || {};
        if (!roomId || !content) return;
        if (!isActiveRoomParticipant(roomId)) return;
        try {
            const Message = require('./src/models/Message');
            const Room = require('./src/models/Room');
            const room = await Room.findById(roomId).select('participants settings bans mode coHosts moderators hostId');
            if (!room) return;
            const action = type === 'image'
                ? ROOM_ACTIONS.SEND_ROOM_IMAGE
                : ROOM_ACTIONS.SEND_ROOM_MESSAGE;
            if (!canPerformRoomAction({
                room,
                actorUserId: socket.userId,
                action
            })) {
                socket.emit('room:error', {
                    code: 'ROOM_MESSAGE_DENIED',
                    message: 'You cannot send that message in this room right now.'
                });
                return;
            }
            const message = await Message.create({
                roomId, senderId: socket.userId, content: String(content), type
            });
            Room.findByIdAndUpdate(roomId, { $inc: { 'metrics.totalMessages': 1 } }).exec();
            io.to(`room:${roomId}`).emit('room:message', {
                _id: message._id, userId: socket.userId, username: socket.username,
                avatar: socket.avatar, content: message.content,
                type: message.type || 'text', emojis: emojis || [], seatIndex,
                timestamp: message.createdAt
            });
            economyController._progressQuest(redisClient, socket.userId, 'send_message', 1).catch(() => {});
        } catch (err) { console.error('room:message error:', err.message); }
    });

    // ── Typing ────────────────────────────────────────────────────────────────
    socket.on('typing', ({ roomId, groupId, recipientId, isTyping } = {}) => {
        const payload = {
            userId: socket.userId,
            username: socket.username,
            isTyping,
            roomId: roomId || null,
            groupId: groupId || null,
            recipientId: recipientId || null
        };
        if (roomId)      socket.to(`room:${roomId}`).emit('typing', payload);
        else if (groupId)     socket.to(`group:${groupId}`).emit('typing', payload);
        else if (recipientId) socket.to(`user:${recipientId}`).emit('typing', payload);
    });

    // ── Voice ─────────────────────────────────────────────────────────────────
    socket.on('voice:mute', ({ roomId, muted } = {}) => {
        if (!roomId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        const nextMuted = Boolean(muted);
        const current = voiceStateByRoom.get(roomId) || {};
        if (current.muted === nextMuted) return;

        voiceStateByRoom.set(roomId, { ...current, muted: nextMuted });
        io.to(`room:${roomId}`).emit('voice:mute', {
            userId: socket.userId,
            muted: nextMuted
        });
    });
    socket.on('voice:speaking', ({ roomId, speaking } = {}) => {
        if (!roomId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        const nextSpeaking = Boolean(speaking);
        const current = voiceStateByRoom.get(roomId) || {};
        if (current.speaking === nextSpeaking) return;

        voiceStateByRoom.set(roomId, { ...current, speaking: nextSpeaking });
        io.to(`room:${roomId}`).emit('voice:speaking', {
            userId: socket.userId,
            speaking: nextSpeaking
        });
    });

    // ── Reactions & sounds ────────────────────────────────────────────────────
    socket.on('room:reaction', ({ roomId, emoji, seatIndex } = {}) => {
        if (roomId && !isActiveRoomParticipant(roomId)) return;
        if (roomId) io.to(`room:${roomId}`).emit('room:reaction', {
            userId: socket.userId, username: socket.username, emoji, seatIndex
        });
    });
    socket.on('room:sound_effect', ({ roomId, soundId, seatIndex } = {}) => {
        if (roomId && !isActiveRoomParticipant(roomId)) return;
        if (roomId) io.to(`room:${roomId}`).emit('room:sound_effect', {
            userId: socket.userId, soundId, seatIndex
        });
    });
    socket.on('room:stage_feature', async ({ roomId, featureId } = {}) => {
        if (!roomId || !featureId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        if (!ROOM_STAGE_FEATURE_LABELS[featureId]) return;

        try {
            const Room = require('./src/models/Room');
            const room = await Room.findById(roomId)
                .populate('participants.userId', 'username avatar')
                .lean();

            if (!room || room.type !== 'voice') return;

            const participants = normalizeRoomParticipants(room, socket);
            const payload = buildRoomStageFeaturePayload({
                featureId,
                room,
                participants,
                socket
            });

            if (!payload) return;

            io.to(`room:${roomId}`).emit('room:stage_feature', payload);
        } catch (err) {
            console.error('room:stage_feature error:', err.message);
        }
    });

    socket.on('room:draw:stroke_begin', async ({
        roomId,
        strokeId,
        sessionId,
        toolType,
        colorValue,
        thickness,
        points
    } = {}) => {
        if (!roomId || !strokeId) return;
        if (!isActiveRoomParticipant(roomId)) return;

        try {
            const Room = require('./src/models/Room');
            const room = await Room.findById(roomId)
                .select('participants hostId ownerId coHosts moderators roomActive miniDraw');
            if (!room) return;
            if (sessionId && room.miniDraw?.sessionId && room.miniDraw.sessionId !== sessionId) {
                socket.emit('room:draw:error', {
                    roomId,
                    code: 'MINI_DRAW_SESSION_STALE',
                    message: 'Mini Draw session changed. Please resync the board.',
                    summary: buildMiniDrawSummary(room, socket.userId)
                });
                return;
            }

            const payload = beginPendingStroke({
                room,
                socketId: socket.id,
                userId: socket.userId,
                strokeId,
                toolType,
                colorValue,
                thickness,
                points
            });

            socket.to(`room:${roomId}`).emit('room:draw:progress', payload);
        } catch (err) {
            socket.emit('room:draw:error', {
                roomId,
                code: err.code || 'MINI_DRAW_BEGIN_FAILED',
                message: err.message || 'Could not start that stroke'
            });
        }
    });

    socket.on('room:draw:stroke_chunk', async ({
        roomId,
        strokeId,
        sessionId,
        points
    } = {}) => {
        if (!roomId || !strokeId) return;
        if (!isActiveRoomParticipant(roomId)) return;

        try {
            const payload = appendPendingStroke({
                roomId,
                userId: socket.userId,
                strokeId,
                sessionId,
                points
            });
            if (!payload) return;

            socket.to(`room:${roomId}`).emit('room:draw:progress', payload);
        } catch (err) {
            socket.emit('room:draw:error', {
                roomId,
                code: err.code || 'MINI_DRAW_PROGRESS_FAILED',
                message: err.message || 'Could not update that stroke'
            });
        }
    });

    socket.on('room:draw:stroke_end', async ({
        roomId,
        strokeId,
        sessionId,
        points
    } = {}) => {
        if (!roomId || !strokeId) return;
        if (!isActiveRoomParticipant(roomId)) return;

        try {
            const Room = require('./src/models/Room');
            const room = await Room.findById(roomId)
                .select('participants hostId ownerId coHosts moderators roomActive miniDraw');
            if (!room) return;
            if (sessionId && room.miniDraw?.sessionId && room.miniDraw.sessionId !== sessionId) {
                socket.emit('room:draw:error', {
                    roomId,
                    code: 'MINI_DRAW_SESSION_STALE',
                    message: 'Mini Draw session changed. Please resync the board.',
                    summary: buildMiniDrawSummary(room, socket.userId)
                });
                return;
            }

            const result = await commitPendingStroke({
                room,
                userId: socket.userId,
                strokeId,
                points
            });

            io.to(`room:${roomId}`).emit('room:draw:commit', {
                roomId,
                sessionId: result.summary.sessionId,
                stroke: result.stroke,
                summary: buildMiniDrawSummary(room, null)
            });
        } catch (err) {
            socket.emit('room:draw:error', {
                roomId,
                code: err.code || 'MINI_DRAW_COMMIT_FAILED',
                message: err.message || 'Could not finish that stroke'
            });
        }
    });

    // ── XP heartbeat ──────────────────────────────────────────────────────────
    socket.on('room:heartbeat', async ({ roomId } = {}) => {
        if (!roomId || !socket.userId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        try {
            const User = require('./src/models/User');
            const user = await User.findById(socket.userId);
            if (!user) return;
            const heartbeatProgress = await awardUserXp({
                user,
                amount: 2,
                sourceType: 'room_heartbeat',
                sourceReferenceId: roomId.toString(),
                sourceReferenceType: 'room',
                redis: redisClient,
                metadata: {
                    roomId: roomId.toString()
                }
            });
            const progressedUser = heartbeatProgress?.user || user;
            const now = Date.now();
            const lastQuestTick = questHeartbeatByRoom.get(roomId) || 0;
            if (now - lastQuestTick >= 55000) {
                questHeartbeatByRoom.set(roomId, now);
                economyController._progressQuest(redisClient, socket.userId, 'room_heartbeat', 1).catch(() => {});
            }
            io.to(`user:${socket.userId}`).emit(
                'balance_update',
                buildProgressPayload(progressedUser, {
                    xpGained: heartbeatProgress?.xpGained || 0,
                    source: 'room_heartbeat'
                })
            );
            await emitLevelDrivenRealtime(io, progressedUser, heartbeatProgress, {
                source: 'room_heartbeat'
            });
        } catch (err) { console.error('room:heartbeat error:', err.message); }
    });

    // ── Room invite ───────────────────────────────────────────────────────────
    socket.on('room:invite', ({ roomId, roomName, targetUserId } = {}) => {
        if (!roomId || !targetUserId) return;
        (async () => {
            try {
                const Room = require('./src/models/Room');
                const User = require('./src/models/User');
                const room = await Room.findById(roomId).select('name participants bans coHosts moderators hostId');
                if (!room) return;
                if (!canPerformRoomAction({
                    room,
                    actorUserId: socket.userId,
                    action: ROOM_ACTIONS.INVITE_USER
                })) {
                    socket.emit('room:error', {
                        code: 'ROOM_INVITE_DENIED',
                        message: 'Only hosts and admins can invite users right now.'
                    });
                    return;
                }
                const inviter = await User.findById(socket.userId).select('friends');
                if (!(inviter?.friends || []).some((entry) => entry?.toString() === targetUserId.toString())) {
                    socket.emit('room:error', {
                        code: 'ROOM_INVITE_DENIED',
                        message: 'You can only invite your friends.'
                    });
                    return;
                }
                const isTargetBanned = room.bans?.some((ban) =>
                    ban.userId?.toString() === targetUserId.toString() &&
                    (!ban.expiresAt || new Date(ban.expiresAt) > new Date())
                );
                if (isTargetBanned) {
                    socket.emit('room:error', {
                        code: 'ROOM_INVITE_DENIED',
                        message: 'That user cannot join this room right now.'
                    });
                    return;
                }

                io.to(`user:${targetUserId}`).emit('room:invite', {
                    roomId, inviterId: socket.userId, inviterName: socket.username,
                    inviterAvatar: socket.avatar, roomName: roomName || room.name || 'A Voice Room'
                });
            } catch (err) {
                console.error('room:invite error:', err.message);
            }
        })();
    });

    // ── Rally fans ────────────────────────────────────────────────────────────
    socket.on('room:rally_fans', ({ roomId, roomName } = {}) => {
        if (!roomId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        (async () => {
            try {
                const Room = require('./src/models/Room');
                const roomForPermission = await Room.findById(roomId).select('participants coHosts moderators hostId settings');
                if (!roomForPermission) return;
                if (!canPerformRoomAction({
                    room: roomForPermission,
                    actorUserId: socket.userId,
                    action: ROOM_ACTIONS.RALLY_FANS
                })) {
                    socket.emit('room:error', {
                        code: 'ROOM_RALLY_DENIED',
                        message: 'Only hosts and admins can rally the room.'
                    });
                    return;
                }
                const rallyExpiresAt = new Date(Date.now() + RALLY_DURATION_MS);
                const room = await Room.findByIdAndUpdate(
                    roomId,
                    {
                        $set: {
                            rallyActive: true,
                            rallyExpiresAt
                        }
                    },
                    { new: true }
                ).populate('hostId', 'username avatar level vipLevel');

                if (!room) return;

                io.to(`room:${roomId}`).emit('room:rally_fans', {
                    roomId,
                    roomName: roomName || room.name,
                    hostId: socket.userId,
                    hostName: socket.username,
                    rallyActive: true,
                    rallyExpiresAt
                });

                io.emit('room:lobby:update', {
                    roomId: room._id.toString(),
                    action: 'rally_started',
                    name: room.name,
                    category: room.category,
                    type: room.type,
                    hostAvatar: room.hostId?.avatar || '',
                    coverImage: room.theme?.coverImage || '',
                    participantCount: room.participantCount ?? room.participants?.length ?? 0,
                    onlineCount: room.onlineCount ?? 0,
                    rallyActive: true,
                    rallyExpiresAt,
                    endedAt: room.endedAt || null,
                    updatedAt: new Date().toISOString()
                });
            } catch (err) {
                console.error('room:rally_fans error:', err.message);
            }
        })();
    });

    // ── Real-time gift (socket-only path) ─────────────────────────────────────
    socket.on('send_gift', async ({ toUserId, giftId, roomId } = {}) => {
        if (!toUserId || !giftId) return;
        try {
            const User        = require('./src/models/User');
            await syncGiftCatalog();
            if (roomId) {
                const Room = require('./src/models/Room');
                const room = await Room.findById(roomId).select('participants settings bans mode coHosts moderators hostId');
                if (!room || !canPerformRoomAction({
                    room,
                    actorUserId: socket.userId,
                    action: ROOM_ACTIONS.SEND_ROOM_GIFT
                })) {
                    return socket.emit('gift_error', { message: 'Gifting is disabled for your role in this room' });
                }
            }
            const gift = await findGiftByIdentifier(giftId, { activeOnly: true });
            if (!gift) return socket.emit('gift_error', { message: 'Gift not found' });

            const sender = await User.findOneAndUpdate(
                { _id: socket.userId, coins: { $gte: gift.price?.coins || 0 } },
                { $inc: { coins: -(gift.price?.coins || 0), 'stats.giftsSent': 1 } },
                { new: true }
            );
            if (!sender) return socket.emit('gift_error', { message: 'Insufficient funds' });

            const recipient = await User.findByIdAndUpdate(
                toUserId,
                { $inc: { coins: Math.floor((gift.price?.coins || 0) * 0.8), 'stats.giftsReceived': 1 } },
                { new: true }
            );

            const giftData = {
                giftId: gift.giftId || gift._id,
                giftName: gift.name,
                giftIcon: gift.icon,
                animation: gift.animation, roomId,
                giftCategory: gift.category,
                giftRarity: gift.rarity || gift.category,
                sender:    { userId: sender._id,    username: sender.username,    avatar: sender.avatar,    newBalance: { coins: sender.coins, gems: sender.gems } },
                recipient: { userId: recipient?._id, username: recipient?.username, avatar: recipient?.avatar, newBalance: { coins: recipient?.coins, gems: recipient?.gems } }
            };

            io.to(`user:${socket.userId}`).emit('balance_update', { coins: sender.coins, gems: sender.gems });
            io.to(`user:${toUserId}`).emit('balance_update', { coins: recipient?.coins, gems: recipient?.gems });
            if (roomId) io.to(`room:${roomId}`).emit('receive_gift', giftData);
            else {
                io.to(`user:${toUserId}`).emit('receive_gift', giftData);
                socket.emit('receive_gift', giftData);
            }

            economyController._progressQuest(redisClient, socket.userId, 'send_gift', 1).catch(() => {});
            economyController._progressQuest(redisClient, socket.userId, 'weekly_gift', 1).catch(() => {});
        } catch (err) {
            console.error('send_gift socket error:', err.message);
            socket.emit('gift_error', { message: err.message });
        }
    });

    // ── Disconnect ────────────────────────────────────────────────────────────
    socket.on('disconnect', async () => {
        console.log('🔌 User disconnected:', socket.userId);
        clearPendingStrokesForSocket(socket.id);
        const activeSockets = activeSocketIdsByUserId.get(resolvedUserId);
        let isLastActiveSocket = true;
        if (activeSockets) {
            activeSockets.delete(socket.id);
            if (activeSockets.size === 0) {
                activeSocketIdsByUserId.delete(resolvedUserId);
            } else {
                isLastActiveSocket = false;
            }
        }
        if (redisClient.isReady) {
            if (isLastActiveSocket) {
                redisClient.sRem('online:users', resolvedUserId).catch(() => {});
            }
            socket.activePresenceRoomIds.forEach(rid => {
                const key = `room:${rid}:users`;
                redisClient.sRem(key, resolvedUserId)
                    .then(() => redisClient.sCard(key))
                    .then(cnt => redisClient.set(`room:${rid}:count`, cnt.toString()))
                    .catch(() => {});
            });
        }
        try {
            if (isLastActiveSocket) {
                const User = require('./src/models/User');
                await User.findByIdAndUpdate(socket.userId, {
                    'status.isOnline': false, 'status.lastActive': new Date()
                });
                broadcastToFriends(socket, 'friend:offline');
            }
        } catch (err) { console.error('disconnect user update error:', err.message); }

        for (const roomId of socket.activePresenceRoomIds) {
            io.to(`room:${roomId}`).emit('user_left', {
                roomId,
                userId: socket.userId
            });
            await syncSocketRoomParticipantPresence({
                roomId,
                userId: socket.userId,
                present: false,
                lobbyAction: 'participant_left'
            });
        }
    });
});

// ── Start ───────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🔍 Environment: ${process.env.NODE_ENV}`);
});
