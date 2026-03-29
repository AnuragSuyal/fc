const Message = require('../models/Message');
const User = require('../models/User');
const Room = require('../models/Room');
const Group = require('../models/Group');
const mongoose = require('mongoose');
const economyController = require('./economyController');
const {
    ROOM_ACTIONS,
    canPerformRoomAction,
    isRoomAdmin
} = require('../services/roomPermissionService');

const INTRO_MESSAGE_LIMIT = 3;
const NON_FRIEND_BLOCKED_DM_TYPES = new Set(['gift', 'system']);

const resolveRoomFeedStartAt = (room, userId) => {
    if (!room || !userId) return null;

    const participant = (room.participants || []).find(
        (entry) => entry?.userId?.toString() === userId.toString()
    );
    if (!participant) {
        return null;
    }

    const joinedAt = participant.joinedAt || participant.lastActive;
    if (!joinedAt) {
        return null;
    }

    const parsed = new Date(joinedAt);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const sanitizeMessageForViewer = (message) => {
    if (!message) return message;

    const payload = typeof message.toObject === 'function'
        ? message.toObject({ virtuals: false })
        : { ...message };

    if (payload.type === 'private_image' || payload.metadata?.privateImage === true) {
        const ephemeralSeconds = Number(payload.metadata?.ephemeralSeconds || 5);
        payload.metadata = {
            ...(payload.metadata || {}),
            privateImage: true,
            ephemeralSeconds,
            screenshotProtection: payload.metadata?.screenshotProtection !== false
        };
    }

    return payload;
};

const emitMessageRealtime = (io, message, event, payload) => {
    if (!io || !message) return;

    if (message.roomId) {
        io.to(`room:${message.roomId}`).emit(event, payload);
        return;
    }

    if (message.groupId) {
        io.to(`group:${message.groupId}`).emit(event, payload);
        return;
    }

    const targets = new Set();
    if (message.senderId) targets.add(`user:${message.senderId}`);
    if (message.recipientId) targets.add(`user:${message.recipientId}`);
    targets.forEach((target) => io.to(target).emit(event, payload));
};

const resolveUserOrThrow = async (identifier, message = 'User not found') => {
    const user = await User.findByIdOrUid(identifier);
    if (user) {
        return user;
    }

    const error = new Error(message);
    error.status = 404;
    throw error;
};

const countIntroMessagesSent = (senderId, recipientId) =>
    Message.countDocuments({
        senderId,
        recipientId,
        isDeleted: false,
        type: { $ne: 'system' }
    });

// @desc    Send a direct message
exports.sendDirectMessage = async (req, res, next) => {
    try {
        const { recipientId, content, type = 'text', replyTo, metadata = {} } = req.body;

        const recipient = await resolveUserOrThrow(recipientId, 'Recipient not found');
        const sender = await User.findById(req.userId).select('username friends blockedUsers');
        if (!sender) {
            const error = new Error('Sender not found');
            error.status = 404;
            throw error;
        }
        const recipientUserId = recipient._id.toString();

        const isBlocked = (sender.blockedUsers || []).some(
            (blockedId) => blockedId?.toString() === recipientUserId
        ) || (recipient.blockedUsers || []).some(
            (blockedId) => blockedId?.toString() === req.userId
        );
        if (isBlocked) {
            const error = new Error('Direct chat is unavailable for this user');
            error.status = 403;
            throw error;
        }

        const isFriend = (sender.friends || []).some(
            (friendId) => friendId?.toString() === recipientUserId
        );

        if (!isFriend) {
            if (NON_FRIEND_BLOCKED_DM_TYPES.has(type)) {
                const error = new Error('Become friends first to send this in direct chat');
                error.status = 403;
                throw error;
            }

            const introMessagesUsed = await countIntroMessagesSent(req.userId, recipient._id);
            if (introMessagesUsed >= INTRO_MESSAGE_LIMIT) {
                const error = new Error(
                    `You have used your ${INTRO_MESSAGE_LIMIT} intro messages. Add each other as friends to continue chatting.`
                );
                error.status = 403;
                throw error;
            }
        }

        const message = new Message({
            senderId: req.userId,
            recipientId: recipient._id,
            content,
            type,
            replyTo: replyTo || null,
            metadata: metadata && typeof metadata === 'object' ? metadata : {}
        });

        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        const messagePayload = sanitizeMessageForViewer(message);
        if (io) {
            emitMessageRealtime(io, message, 'dm:received', {
                message: messagePayload,
                from: { id: req.userId, username: sender.username }
            });
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(messagePayload);
    } catch (error) {
        next(error);
    }
};

// @desc    Send room message
exports.sendRoomMessage = async (req, res, next) => {
    try {
        const { roomId, content, type = 'text', replyTo, metadata = {} } = req.body;

        const room = await Room.findById(roomId);
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }

        const isInRoom = room.participants.some(p => p.userId.toString() === req.userId);
        if (!isInRoom) {
            const error = new Error('You are not in this room');
            error.status = 403;
            throw error;
        }

        const messageAction = type === 'image'
            ? ROOM_ACTIONS.SEND_ROOM_IMAGE
            : ROOM_ACTIONS.SEND_ROOM_MESSAGE;
        if (!canPerformRoomAction({
            room,
            actorUserId: req.userId,
            action: messageAction
        })) {
            const error = new Error(
                type === 'image'
                    ? 'Photo sharing is not available for your role in this room'
                    : 'You cannot send room chat right now'
            );
            error.status = 403;
            throw error;
        }

        const message = new Message({
            roomId,
            senderId: req.userId,
            content,
            type,
            replyTo: replyTo || null,
            metadata: metadata && typeof metadata === 'object' ? metadata : {}
        });
        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        const messagePayload = sanitizeMessageForViewer(message);
        if (io) io.to(`room:${roomId}`).emit('room:message', messagePayload);

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(messagePayload);
    } catch (error) {
        next(error);
    }
};

// @desc    Send group message
exports.sendGroupMessage = async (req, res, next) => {
    try {
        const { groupId, content, type = 'text', replyTo, metadata = {} } = req.body;
        const group = await Group.findById(groupId);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const isInGroup = group.members.some(m => m.userId.toString() === req.userId);
        if (!isInGroup) {
            const error = new Error('You are not in this group');
            error.status = 403;
            throw error;
        }

        const message = new Message({
            groupId,
            senderId: req.userId,
            content,
            type,
            replyTo: replyTo || null,
            metadata: metadata && typeof metadata === 'object' ? metadata : {}
        });
        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        const messagePayload = sanitizeMessageForViewer(message);
        if (io) io.to(`group:${groupId}`).emit('group:message', messagePayload);

        group.lastActivityAt = new Date();
        group.stats = {
            ...(group.stats || {}),
            totalMessages: Number(group.stats?.totalMessages || 0) + 1
        };
        await group.save();

        if (io) {
            const groupUpdatePayload = {
                action: 'chat_activity',
                groupId: group._id.toString(),
                memberUserId: req.userId,
                updatedAt: new Date().toISOString()
            };
            io.to(`group:${groupId}`).emit('group:updated', groupUpdatePayload);
            const memberIds = new Set(
                (group.members || []).map((member) => member.userId?.toString()).filter(Boolean)
            );
            for (const memberId of memberIds) {
                io.to(`user:${memberId}`).emit('group:updated', groupUpdatePayload);
            }
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(messagePayload);
    } catch (error) {
        next(error);
    }
};

// @desc    Get conversation
exports.getDirectMessages = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const { page = 1, limit = 50 } = req.query;
        const peerUser = await resolveUserOrThrow(userId);
        const peerUserId = peerUser._id;

        const messages = await Message.find({
            $or: [{ senderId: req.userId, recipientId: peerUserId }, { senderId: peerUserId, recipientId: req.userId }],
            isDeleted: false
        })
            .populate('senderId', 'username avatar')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments({
            $or: [{ senderId: req.userId, recipientId: peerUserId }, { senderId: peerUserId, recipientId: req.userId }],
            isDeleted: false
        });

        await Message.updateMany(
            { senderId: peerUserId, recipientId: req.userId, 'readBy.userId': { $ne: req.userId } },
            { $push: { readBy: { userId: req.userId, readAt: Date.now() } } }
        );

        res.json({
            messages: messages.reverse().map(sanitizeMessageForViewer),
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get room messages
exports.getRoomMessages = async (req, res, next) => {
    try {
        const { roomId } = req.params;
        const { page = 1, limit = 50 } = req.query;
        const room = await Room.findById(roomId).select('participants bans');
        if (!room) {
            const error = new Error('Room not found');
            error.status = 404;
            throw error;
        }
        const isInRoom = room.participants.some((participant) => participant.userId.toString() === req.userId);
        if (!isInRoom) {
            const error = new Error('Join the room to view its messages');
            error.status = 403;
            throw error;
        }
        const isBanned = room.bans?.some((ban) =>
            ban.userId.toString() === req.userId &&
            (!ban.expiresAt || ban.expiresAt > Date.now())
        );
        if (isBanned) {
            const error = new Error('You are banned from this room');
            error.status = 403;
            throw error;
        }

        const feedStartAt = resolveRoomFeedStartAt(room, req.userId);
        const messageQuery = {
            roomId,
            isDeleted: false,
            ...(feedStartAt ? { createdAt: { $gte: feedStartAt } } : {})
        };

        const messages = await Message.find(messageQuery)
            .populate('senderId', 'username avatar level')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments(messageQuery);
        res.json({
            messages: messages.reverse().map(sanitizeMessageForViewer),
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get group messages
exports.getGroupMessages = async (req, res, next) => {
    try {
        const { groupId } = req.params;
        const { page = 1, limit = 50 } = req.query;
        const group = await Group.findById(groupId).select('members');
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const isInGroup = (group.members || []).some(
            (member) => member.userId?.toString() === req.userId
        );
        if (!isInGroup) {
            const error = new Error('You are not in this group');
            error.status = 403;
            throw error;
        }

        const messages = await Message.find({ groupId, isDeleted: false })
            .populate('senderId', 'username avatar level')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments({ groupId, isDeleted: false });
        res.json({
            messages: messages.reverse().map(sanitizeMessageForViewer),
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get conversations list
exports.getConversations = async (req, res, next) => {
    try {
        const userObjectId = new mongoose.Types.ObjectId(req.userId);
        const conversations = await Message.aggregate([
            { $match: { $or: [{ senderId: userObjectId }, { recipientId: userObjectId }], isDeleted: false } },
            { $sort: { createdAt: -1 } },
            {
                $group: {
                    _id: { $cond: [{ $eq: ['$senderId', userObjectId] }, '$recipientId', '$senderId'] },
                    lastMessage: { $first: '$$ROOT' },
                    unreadCount: { $sum: { $cond: [{ $and: [{ $eq: ['$recipientId', userObjectId] }, { $not: { $in: [userObjectId, '$readBy.userId'] } }] }, 1, 0] } }
                }
            },
            { $lookup: { from: 'users', localField: '_id', foreignField: '_id', as: 'user' } },
            { $unwind: '$user' },
            { $project: { 'user.password': 0, 'user.email': 0 } },
            { $sort: { 'lastMessage.createdAt': -1 } }
        ]);
        res.json(conversations);
    } catch (error) {
        next(error);
    }
};

// @desc    Add reaction
exports.addReaction = async (req, res, next) => {
    try {
        const { reaction } = req.body;
        const message = await Message.findById(req.params.messageId);
        if (!message || message.isDeleted) {
            const error = new Error('Message not found');
            error.status = 404;
            throw error;
        }

        const reactIdx = message.reactions.findIndex(r => r.userId.toString() === req.userId && r.reaction === reaction);
        if (reactIdx === -1) {
            message.reactions.push({ userId: req.userId, reaction });
        } else {
            message.reactions.splice(reactIdx, 1);
        }

        await message.save();
        const io = req.app.get('io');
        if (io) {
            emitMessageRealtime(io, message, 'message:reaction', {
                messageId: message._id,
                userId: req.userId,
                reaction,
                active: reactIdx === -1,
                createdAt: new Date().toISOString()
            });
        }
        res.json({ success: true, reactions: message.reactions });
    } catch (error) {
        next(error);
    }
};

// @desc    Delete message
exports.deleteMessage = async (req, res, next) => {
    try {
        const message = await Message.findById(req.params.messageId);
        if (!message) {
            const error = new Error('Message not found');
            error.status = 404;
            throw error;
        }

        if (message.senderId.toString() !== req.userId) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        message.isDeleted = true;
        message.deletedAt = Date.now();
        await message.save();

        const io = req.app.get('io');
        if (io) {
            emitMessageRealtime(io, message, 'message:deleted', {
                messageId: message._id
            });
        }
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

// @desc    Get unread message count
exports.getUnreadCount = async (req, res, next) => {
    try {
        const userObjectId = new mongoose.Types.ObjectId(req.userId);
        const count = await Message.countDocuments({
            recipientId: userObjectId,
            'readBy.userId': { $ne: userObjectId },
            isDeleted: false
        });
        res.json({ unread: count });
    } catch (error) { next(error); }
};

// @desc    Mark messages read and emit socket read-receipt
exports.markAsRead = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const peerUser = await resolveUserOrThrow(userId);
        const peerUserId = peerUser._id;
        await Message.updateMany(
            { senderId: peerUserId, recipientId: req.userId, 'readBy.userId': { $ne: req.userId } },
            { $push: { readBy: { userId: req.userId, readAt: Date.now() } } }
        );

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${peerUserId}`).emit('message:read', {
                byUserId: req.userId,
                fromUserId: peerUserId.toString()
            });
        }

        res.json({ success: true });
    } catch (error) { next(error); }
};
