const Message = require('../models/Message');
const User = require('../models/User');
const Room = require('../models/Room');
const Group = require('../models/Group');
const mongoose = require('mongoose');
const economyController = require('./economyController');
const { isRoomAdmin } = require('../utils/roomPermissions');

// @desc    Send a direct message
exports.sendDirectMessage = async (req, res, next) => {
    try {
        const { recipientId, content, type = 'text', replyTo } = req.body;

        const recipient = await User.findById(recipientId);
        if (!recipient) {
            const error = new Error('Recipient not found');
            error.status = 404;
            throw error;
        }

        const sender = await User.findById(req.userId);
        if (!sender.friends.includes(recipientId)) {
            const error = new Error('You can only message friends');
            error.status = 403;
            throw error;
        }

        const message = new Message({
            senderId: req.userId,
            recipientId,
            content,
            type,
            replyTo: replyTo || null
        });

        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${recipientId}`).emit('dm:received', {
                message,
                from: { id: req.userId, username: sender.username }
            });
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(message);
    } catch (error) {
        next(error);
    }
};

// @desc    Send room message
exports.sendRoomMessage = async (req, res, next) => {
    try {
        const { roomId, content, type = 'text', replyTo } = req.body;

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

        const canModerate = isRoomAdmin(room, req.userId);
        if (type === 'text' && room.settings?.banTextChat && !canModerate) {
            const error = new Error('Text chat is currently limited to hosts and admins');
            error.status = 403;
            throw error;
        }
        if (type === 'image' && room.settings?.banPhotoChat && !canModerate) {
            const error = new Error('Photo sharing is currently disabled in this room');
            error.status = 403;
            throw error;
        }

        const message = new Message({ roomId, senderId: req.userId, content, type, replyTo: replyTo || null });
        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        if (io) io.to(`room:${roomId}`).emit('room:message', message);

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(message);
    } catch (error) {
        next(error);
    }
};

// @desc    Send group message
exports.sendGroupMessage = async (req, res, next) => {
    try {
        const { groupId, content, type = 'text', replyTo } = req.body;
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

        const message = new Message({ groupId, senderId: req.userId, content, type, replyTo: replyTo || null });
        await message.save();
        await message.populate([
            { path: 'senderId', select: 'username avatar level' },
            { path: 'replyTo' }
        ]);

        const io = req.app.get('io');
        if (io) io.to(`group:${groupId}`).emit('group:message', message);

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_message', 1).catch(() => {});

        res.status(201).json(message);
    } catch (error) {
        next(error);
    }
};

// @desc    Get conversation
exports.getDirectMessages = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const { page = 1, limit = 50 } = req.query;

        const messages = await Message.find({
            $or: [{ senderId: req.userId, recipientId: userId }, { senderId: userId, recipientId: req.userId }],
            isDeleted: false
        })
            .populate('senderId', 'username avatar')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments({
            $or: [{ senderId: req.userId, recipientId: userId }, { senderId: userId, recipientId: req.userId }],
            isDeleted: false
        });

        await Message.updateMany(
            { senderId: userId, recipientId: req.userId, 'readBy.userId': { $ne: req.userId } },
            { $push: { readBy: { userId: req.userId, readAt: Date.now() } } }
        );

        res.json({
            messages: messages.reverse(),
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

        const messages = await Message.find({ roomId, isDeleted: false })
            .populate('senderId', 'username avatar level')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments({ roomId, isDeleted: false });
        res.json({
            messages: messages.reverse(),
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

        const messages = await Message.find({ groupId, isDeleted: false })
            .populate('senderId', 'username avatar level')
            .populate('replyTo')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Message.countDocuments({ groupId, isDeleted: false });
        res.json({
            messages: messages.reverse(),
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
            const target = message.roomId ? `room:${message.roomId}` : message.groupId ? `group:${message.groupId}` : `user:${message.recipientId}`;
            io.to(target).emit('message:reaction', { messageId: message._id, userId: req.userId, reaction });
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
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};

// @desc    Mark read
exports.markAsRead = async (req, res, next) => {
    try {
        const { userId } = req.params;
        await Message.updateMany(
            { senderId: userId, recipientId: req.userId, 'readBy.userId': { $ne: req.userId } },
            { $push: { readBy: { userId: req.userId, readAt: Date.now() } } }
        );
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
        await Message.updateMany(
            { senderId: userId, recipientId: req.userId, 'readBy.userId': { $ne: req.userId } },
            { $push: { readBy: { userId: req.userId, readAt: Date.now() } } }
        );

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${userId}`).emit('message:read', { byUserId: req.userId, fromUserId: userId });
        }

        res.json({ success: true });
    } catch (error) { next(error); }
};
