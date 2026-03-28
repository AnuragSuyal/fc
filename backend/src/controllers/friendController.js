const User     = require('../models/User');
const mongoose = require('mongoose');
const economyController = require('./economyController');

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
        session.endSession();
    }
};

// @desc    Send friend request
exports.sendFriendRequest = async (req, res, next) => {
    try {
        const { userId } = req.params;
        if (userId === req.userId) {
            const error = new Error('Cannot send friend request to yourself');
            error.status = 400;
            throw error;
        }

        const result = await runWithOptionalTransaction(async (session) => {
            const [currentUser, targetUser] = await Promise.all([
                withSession(User.findById(req.userId), session),
                withSession(User.findById(userId), session)
            ]);

            if (!targetUser) { const e = new Error('User not found'); e.status = 404; throw e; }
            if (currentUser.friends.some(id => id.toString() === userId)) {
                const e = new Error('Already friends'); e.status = 400; throw e;
            }
            if (currentUser.blockedUsers.some(id => id.toString() === userId)) {
                const e = new Error('Cannot send request to blocked user'); e.status = 400; throw e;
            }
            if (targetUser.friendRequests.find(r => r.from.toString() === req.userId && r.status === 'pending')) {
                const e = new Error('Friend request already sent'); e.status = 400; throw e;
            }

            const sentAt = new Date();
            targetUser.friendRequests.push({ from: req.userId, status: 'pending', sentAt });
            await targetUser.save(session ? { session } : undefined);
            return {
                currentUser,
                sentAt,
                targetUser: {
                    _id: targetUser._id,
                    username: targetUser.username,
                    avatar: targetUser.avatar,
                    level: targetUser.level,
                    uid: targetUser.uid,
                    status: targetUser.status
                }
            };
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${userId}`).emit('friend_request_received', {
                sentAt: result.sentAt,
                from: {
                    _id: result.currentUser._id,
                    username: result.currentUser.username,
                    avatar: result.currentUser.avatar,
                    level: result.currentUser.level,
                    uid: result.currentUser.uid
                }
            });
            io.to(`user:${req.userId}`).emit('friend_request_sent', {
                sentAt: result.sentAt,
                user: result.targetUser
            });
        }
        res.json({ success: true, message: 'Friend request sent' });
    } catch (error) { next(error); }
};

// @desc    Accept friend request
exports.acceptFriendRequest = async (req, res, next) => {
    try {
        const { userId } = req.params;

        const result = await runWithOptionalTransaction(async (session) => {
            const [currentUser, requestingUser] = await Promise.all([
                withSession(User.findById(req.userId), session),
                withSession(User.findById(userId), session)
            ]);

            if (!requestingUser) { const e = new Error('User not found'); e.status = 404; throw e; }

            const idx = currentUser.friendRequests.findIndex(r => r.from.toString() === userId && r.status === 'pending');
            if (idx === -1) { const e = new Error('Friend request not found'); e.status = 404; throw e; }

            currentUser.friendRequests[idx].status = 'accepted';
            if (!currentUser.friends.some(id => id.toString() === userId)) currentUser.friends.push(userId);
            if (!requestingUser.friends.some(id => id.toString() === req.userId)) requestingUser.friends.push(req.userId);

            await Promise.all([
                currentUser.save(session ? { session } : undefined),
                requestingUser.save(session ? { session } : undefined)
            ]);
            return { currentUser, requestingUser };
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${userId}`).emit('friend_request_accepted', {
                user: { _id: result.currentUser._id, username: result.currentUser.username, avatar: result.currentUser.avatar }
            });
            io.to(`user:${req.userId}`).emit('friend_request_accepted', {
                user: { _id: result.requestingUser._id, username: result.requestingUser.username, avatar: result.requestingUser.avatar }
            });
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'add_friend', 1).catch(() => {});
        res.json({ success: true, message: 'Friend request accepted' });
    } catch (error) { next(error); }
};

// @desc    Reject friend request
exports.rejectFriendRequest = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const currentUser = await User.findById(req.userId);

        const idx = currentUser.friendRequests.findIndex(r => r.from.toString() === userId && r.status === 'pending');
        if (idx === -1) { const e = new Error('Friend request not found'); e.status = 404; throw e; }

        currentUser.friendRequests.splice(idx, 1);
        await currentUser.save();

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${userId}`).emit('friend_request_rejected', {
                userId: currentUser._id, username: currentUser.username
            });
            io.to(`user:${req.userId}`).emit('friend_request_rejected', {
                userId, username: currentUser.username
            });
        }
        res.json({ success: true, message: 'Friend request rejected' });
    } catch (error) { next(error); }
};

// @desc    Remove friend
exports.removeFriend = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const result = await runWithOptionalTransaction(async (session) => {
            const [currentUser, friendUser] = await Promise.all([
                withSession(User.findById(req.userId), session),
                withSession(User.findById(userId), session)
            ]);
            if (!friendUser) { const e = new Error('User not found'); e.status = 404; throw e; }
            currentUser.friends = currentUser.friends.filter(id => id.toString() !== userId);
            friendUser.friends  = friendUser.friends.filter(id => id.toString() !== req.userId);
            await Promise.all([
                currentUser.save(session ? { session } : undefined),
                friendUser.save(session ? { session } : undefined)
            ]);
            return { currentUser, friendUser };
        });
        const io = req.app.get('io');
        if (io) {
            io.to(`user:${userId}`).emit('friend_removed', {
                userId: req.userId,
                username: result.currentUser.username
            });
            io.to(`user:${req.userId}`).emit('friend_removed', {
                userId,
                username: result.friendUser.username
            });
        }
        res.json({ success: true, message: 'Friend removed' });
    } catch (error) { next(error); }
};

// @desc    Get friends list
exports.getFriends = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .populate('friends', 'username avatar level status.isOnline status.lastActive vipLevel');
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        res.json({
            online:  user.friends.filter(f => f.status?.isOnline),
            offline: user.friends.filter(f => !f.status?.isOnline),
            total:   user.friends.length
        });
    } catch (error) { next(error); }
};

// @desc    Get friend requests
exports.getFriendRequests = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .populate('friendRequests.from', 'username avatar level');
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        res.json(user.friendRequests.filter(r => r.status === 'pending'));
    } catch (error) { next(error); }
};

// @desc    Get friend request overview (incoming + outgoing)
exports.getFriendRequestOverview = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .populate('friendRequests.from', 'username avatar level status.isOnline uid');
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        const incoming = (user.friendRequests || [])
            .filter(r => r.status === 'pending')
            .map((request) => ({
                direction: 'incoming',
                sentAt: request.sentAt,
                from: request.from
            }));

        const outgoingUsers = await User.find({
            friendRequests: {
                $elemMatch: {
                    from: user._id,
                    status: 'pending'
                }
            }
        }).select('username avatar level status.isOnline uid friendRequests');

        const outgoing = outgoingUsers.map((targetUser) => {
            const pending = (targetUser.friendRequests || []).find(
                (request) =>
                    request.from?.toString() === req.userId &&
                    request.status === 'pending'
            );

            return {
                direction: 'outgoing',
                sentAt: pending?.sentAt || null,
                user: {
                    _id: targetUser._id,
                    id: targetUser._id,
                    username: targetUser.username,
                    avatar: targetUser.avatar,
                    level: targetUser.level,
                    uid: targetUser.uid,
                    status: targetUser.status
                }
            };
        });

        res.json({
            incoming,
            outgoing,
            total: incoming.length + outgoing.length
        });
    } catch (error) { next(error); }
};

// @desc    Get friend suggestions
exports.getFriendSuggestions = async (req, res, next) => {
    try {
        const currentUser = await User.findById(req.userId);
        if (!currentUser) { const e = new Error('User not found'); e.status = 404; throw e; }
        const suggestions = await User.find({
            _id: { $ne: req.userId, $nin: [...currentUser.friends, ...(currentUser.blockedUsers || [])] },
            'friendRequests.from': { $ne: req.userId }
        })
            .select('username avatar level status.isOnline')
            .limit(20)
            .sort({ 'status.isOnline': -1, level: -1 });
        res.json(suggestions);
    } catch (error) { next(error); }
};

// @desc    Block user
exports.blockUser = async (req, res, next) => {
    try {
        const { userId } = req.params;
        await runWithOptionalTransaction(async (session) => {
            const currentUser = await withSession(User.findById(req.userId), session);
            if (currentUser.blockedUsers.some(id => id.toString() === userId)) {
                const e = new Error('User already blocked'); e.status = 400; throw e;
            }
            if (currentUser.friends.some(id => id.toString() === userId)) {
                currentUser.friends = currentUser.friends.filter(id => id.toString() !== userId);
                const blockedUser = await withSession(User.findById(userId), session);
                if (blockedUser) {
                    blockedUser.friends = blockedUser.friends.filter(id => id.toString() !== req.userId);
                    await blockedUser.save(session ? { session } : undefined);
                }
            }
            currentUser.friendRequests = currentUser.friendRequests.filter(r => r.from.toString() !== userId);
            currentUser.blockedUsers.push(userId);
            await currentUser.save(session ? { session } : undefined);
        });
        res.json({ success: true, message: 'User blocked' });
    } catch (error) { next(error); }
};

// @desc    Unblock user
exports.unblockUser = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const currentUser = await User.findById(req.userId);
        currentUser.blockedUsers = currentUser.blockedUsers.filter(id => id.toString() !== userId);
        await currentUser.save();
        res.json({ success: true, message: 'User unblocked' });
    } catch (error) { next(error); }
};

// @desc    Get blocked users
exports.getBlockedUsers = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId).populate('blockedUsers', 'username avatar level');
        res.json(user?.blockedUsers || []);
    } catch (error) { next(error); }
};
