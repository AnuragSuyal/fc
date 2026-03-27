// const { AccessToken, WebhookReceiver } = require('livekit-server-sdk');
const Room = require('../models/Room');
const User = require('../models/User');

const resolveRoom = async (roomIdOrName) => {
    if (!roomIdOrName) return null;

    const byObjectId = await Room.findById(roomIdOrName).catch(() => null);
    if (byObjectId) return byObjectId;

    const byRoomId = await Room.findOne({ roomId: roomIdOrName });
    if (byRoomId) return byRoomId;

    return Room.findOne({ name: roomIdOrName });
};

// @desc    Generate LiveKit token
exports.generateToken = async (req, res, next) => {
    try {
        const { roomName, roomId, identity } = req.body;
        const requested = roomId || roomName;
        if (!requested) {
            const error = new Error('roomName or roomId is required');
            error.status = 400;
            throw error;
        }

        const room = await resolveRoom(requested);
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
        const metadata = JSON.stringify({
            username: user?.username || 'User',
            avatar: user?.avatar || ''
        });

        /*
        const token = new AccessToken(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET, {
            identity: identity || req.userId.toString(),
            ttl: '2h',
            metadata,
            name: user?.username || 'User'
        });

        token.addGrant({
            roomJoin: true,
            room: room.roomId || room._id.toString(),
            canPublish: true,
            canSubscribe: true
        });

        const jwt = await token.toJwt();
        */
        const jwt = 'disabled';
        res.json({ token: jwt, serverUrl: process.env.LIVEKIT_URL || 'ws://localhost:7880' });
    } catch (error) {
        next(error);
    }
};

// @desc    LiveKit webhook handler
exports.handleWebhook = async (req, res, next) => {
    try {
        const body = Buffer.isBuffer(req.body)
            ? req.body.toString('utf8')
            : (typeof req.body === 'string' ? req.body : JSON.stringify(req.body || {}));
        const authHeader = req.headers.authorization;
        /*
        const receiver = new WebhookReceiver(process.env.LIVEKIT_API_KEY, process.env.LIVEKIT_API_SECRET);

        let event;
        try {
            event = await receiver.receive(body, authHeader, false);
        } catch (err) {
            // If signature is missing or invalid, return 401
            const error = new Error('Invalid LiveKit webhook signature');
            error.status = 401;
            throw error;
        }
        */
        const event = {};

        if (event?.event === 'participant_joined') {
            const room = await resolveRoom(event.room?.name);
            if (room && event.participant?.identity) {
                const userId = event.participant.identity;
                const existing = room.participants.find(p => p.userId.toString() === userId);
                if (!existing) {
                    room.participants.push({
                        userId,
                        role: 'listener',
                        joinedAt: Date.now(),
                        lastActive: Date.now()
                    });
                } else {
                    existing.lastActive = Date.now();
                }
                await room.save();
            }
        }

        if (event?.event === 'participant_left') {
            const room = await resolveRoom(event.room?.name);
            if (room && event.participant?.identity) {
                const userId = event.participant.identity;
                room.participants = room.participants.filter(p => p.userId.toString() !== userId);
                await room.save();
            }
        }

        res.json({ received: true });
    } catch (error) {
        next(error);
    }
};






