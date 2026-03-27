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

// ── Redis ───────────────────────────────────────────────────────────────────────
const redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
redisClient.on('error', err => console.error('Redis Client Error', err));
redisClient.on('connect', () => console.log('✅ Redis Connected'));
redisClient.connect().catch(err => console.error('Redis initial connect error:', err.message));
app.set('redis', redisClient);

// ── Ranking service ─────────────────────────────────────────────────────────────
const rankingService = require('./src/services/rankingService');
const economyController = require('./src/controllers/economyController');
rankingService.initialize().catch(console.error);

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

// ── Socket.IO connection ────────────────────────────────────────────────────────
io.on('connection', (socket) => {
    console.log('🔌 User connected:', socket.userId);

    socket.joinedRoomIds = new Set();
    socket.activePresenceRoomIds = new Set();
    const voiceStateByRoom = new Map();
    const questHeartbeatByRoom = new Map();
    socket.join(`user:${socket.userId}`);
    const isActiveRoomParticipant = (roomId) => socket.activePresenceRoomIds.has(roomId);

    // Mark online
    (async () => {
        try {
            if (redisClient.isReady) await redisClient.sAdd('online:users', socket.userId.toString());
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
        socket.join(`room:${roomId}`);
        socket.currentRoomId = roomId;
        socket.joinedRoomIds.add(roomId);

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

        socket.activePresenceRoomIds.add(roomId);
        io.to(`room:${roomId}`).emit('user_joined', {
            userId: socket.userId, username: socket.username, avatar: socket.avatar
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
        io.to(`room:${roomId}`).emit('user_left', { userId: socket.userId });
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

    // ── Room chat ─────────────────────────────────────────────────────────────
    socket.on('room:message', async (data) => {
        const { roomId, content, type = 'text', emojis, seatIndex } = data || {};
        if (!roomId || !content) return;
        if (!isActiveRoomParticipant(roomId)) return;
        try {
            const Message = require('./src/models/Message');
            const Room    = require('./src/models/Room');
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
        const payload = { userId: socket.userId, username: socket.username, isTyping };
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

    // ── XP heartbeat ──────────────────────────────────────────────────────────
    socket.on('room:heartbeat', async ({ roomId } = {}) => {
        if (!roomId || !socket.userId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        try {
            const User = require('./src/models/User');
            const user = await User.findById(socket.userId);
            if (!user) return;
            const leveledUp = await user.addXP(2);
            await user.save();
            const now = Date.now();
            const lastQuestTick = questHeartbeatByRoom.get(roomId) || 0;
            if (now - lastQuestTick >= 55000) {
                questHeartbeatByRoom.set(roomId, now);
                economyController._progressQuest(redisClient, socket.userId, 'room_heartbeat', 1).catch(() => {});
            }
            if (leveledUp) io.to(`user:${socket.userId}`).emit('level_up', { newLevel: user.level, xp: user.xp });
            io.to(`user:${socket.userId}`).emit('balance_update', {
                coins: user.coins, gems: user.gems, xp: user.xp, level: user.level
            });
        } catch (err) { console.error('room:heartbeat error:', err.message); }
    });

    // ── Room invite ───────────────────────────────────────────────────────────
    socket.on('room:invite', ({ roomId, roomName, targetUserId } = {}) => {
        if (!roomId || !targetUserId) return;
        io.to(`user:${targetUserId}`).emit('room:invite', {
            roomId, inviterId: socket.userId, inviterName: socket.username,
            inviterAvatar: socket.avatar, roomName: roomName || 'A Voice Room'
        });
    });

    // ── Rally fans ────────────────────────────────────────────────────────────
    socket.on('room:rally_fans', ({ roomId, roomName } = {}) => {
        if (!roomId) return;
        if (!isActiveRoomParticipant(roomId)) return;
        (async () => {
            try {
                const Room = require('./src/models/Room');
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
            const Gift        = require('./src/models/Gift');
            const User        = require('./src/models/User');
            const gift = await Gift.findById(giftId);
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
                giftId: gift._id, giftName: gift.name, giftIcon: gift.icon,
                animation: gift.animation, roomId,
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
        if (redisClient.isReady) {
            redisClient.sRem('online:users', socket.userId.toString()).catch(() => {});
            socket.activePresenceRoomIds.forEach(rid => {
                const key = `room:${rid}:users`;
                redisClient.sRem(key, socket.userId.toString())
                    .then(() => redisClient.sCard(key))
                    .then(cnt => redisClient.set(`room:${rid}:count`, cnt.toString()))
                    .catch(() => {});
            });
        }
        try {
            const User = require('./src/models/User');
            await User.findByIdAndUpdate(socket.userId, {
                'status.isOnline': false, 'status.lastActive': new Date()
            });
            broadcastToFriends(socket, 'friend:offline');
        } catch (err) { console.error('disconnect user update error:', err.message); }

        if (socket.currentRoomId && socket.activePresenceRoomIds.has(socket.currentRoomId)) {
            io.to(`room:${socket.currentRoomId}`).emit('user_left', { userId: socket.userId });
            try {
                const Room = require('./src/models/Room');
                const room = await Room.findById(socket.currentRoomId);
                if (room) {
                    const p = room.participants.find(x => x.userId.toString() === socket.userId);
                    if (p && p.seatIndex !== -1) {
                        p.seatIndex = -1;
                        if (p.role === 'speaker') p.role = 'listener';
                        await room.save();
                        io.to(`room:${room._id}`).emit('room:updated', room);
                    }
                }
            } catch (err) { console.error('disconnect seat-free error:', err.message); }
        }
    });
});

// ── Start ───────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 5000;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
    console.log(`🔍 Environment: ${process.env.NODE_ENV}`);
});
