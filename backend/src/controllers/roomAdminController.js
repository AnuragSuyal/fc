// Extra room admin actions – imported into roomController or used standalone
const Room = require('../models/Room');
const User = require('../models/User');
const {
    canEditAnnouncement,
    canManageAdmins,
    canManageStage,
    canManageTarget,
    canTransferOwnership,
    canViewReports,
    countActiveSpeakers,
    findNextAvailableSeat,
    getMaxActiveSpeakers,
    getParticipant,
    idsEqual,
    isRoomAdmin
} = require('../utils/roomPermissions');
const roomCacheKey = (roomId) => `cache:room:${roomId}`;

const populateRoomById = async (roomId) =>
    Room.findById(roomId)
        .populate('hostId', 'username avatar level vipLevel')
        .populate('coHosts', 'username avatar level vipLevel')
        .populate('moderators', 'username avatar level vipLevel')
        .populate('participants.userId', 'username avatar level vipLevel status.isOnline')
        .populate('bans.userId', 'username avatar');

const invalidateRoomCache = async (redis, roomId) => {
    if (!redis || !redis.isReady) return;
    await redis.del(roomCacheKey(roomId));
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

// Lock/unlock a seat (host only)
exports.lockSeat = async (req, res, next) => {
    try {
        const { seatIndex } = req.params;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageStage(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }

        if (!room.lockedSeats) room.lockedSeats = [];
        const idx = parseInt(seatIndex);
        if (!room.lockedSeats.includes(idx)) room.lockedSeats.push(idx);
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:seat_locked', { seatIndex: idx });
            emitLobbyUpdate(io, room, 'seat_updated');
        }

        res.json({ success: true, lockedSeats: room.lockedSeats });
    } catch (error) { next(error); }
};

exports.unlockSeat = async (req, res, next) => {
    try {
        const { seatIndex } = req.params;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageStage(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }

        const idx = parseInt(seatIndex);
        room.lockedSeats = (room.lockedSeats || []).filter(s => s !== idx);
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:seat_unlocked', { seatIndex: idx });
            emitLobbyUpdate(io, room, 'seat_updated');
        }

        res.json({ success: true, lockedSeats: room.lockedSeats });
    } catch (error) { next(error); }
};

// Promote to speaker
exports.promoteParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageStage(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }
        if (!canManageTarget(room, req.userId, req.params.userId)) {
            const e = new Error('You cannot approve that participant');
            e.status = 403;
            throw e;
        }

        const p = getParticipant(room, req.params.userId);
        if (!p) { const e = new Error('Participant not found'); e.status = 404; throw e; }

        if (p.seatIndex < 1) {
            if (countActiveSpeakers(room) >= getMaxActiveSpeakers(room)) {
                const e = new Error('All active speaker seats are already full');
                e.status = 400;
                throw e;
            }

            const seatIndex = findNextAvailableSeat(room);
            if (seatIndex == null) {
                const e = new Error('No open speaker seat is available right now');
                e.status = 400;
                throw e;
            }
            p.seatIndex = seatIndex;
        }

        if (p.role === 'listener') {
            p.role = 'speaker';
        }
        p.raisedHand = false;
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            io.to(`user:${req.params.userId}`).emit('room:promoted', { roomId: room._id });
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json({ success: true, room: populatedRoom });
    } catch (error) { next(error); }
};

// Demote speaker to listener
exports.demoteParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageStage(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }
        if (!canManageTarget(room, req.userId, req.params.userId)) {
            const e = new Error('You cannot move that participant to the audience');
            e.status = 403;
            throw e;
        }

        const p = getParticipant(room, req.params.userId);
        if (!p) { const e = new Error('Participant not found'); e.status = 404; throw e; }
        p.seatIndex = -1;
        p.raisedHand = false;
        if (p.role === 'speaker') {
            p.role = 'listener';
        }
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            io.to(`user:${req.params.userId}`).emit('room:demoted', { roomId: room._id });
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json({ success: true, room: populatedRoom });
    } catch (error) { next(error); }
};

// Assign/remove co-host
exports.assignCoHost = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageAdmins(room, req.userId)) { const e = new Error('Only host can assign co-host'); e.status = 403; throw e; }
        if (!canManageTarget(room, req.userId, req.params.userId)) {
            const e = new Error('You cannot assign that participant as co-host');
            e.status = 403;
            throw e;
        }

        if (!room.coHosts) room.coHosts = [];
        if (!room.coHosts.some(id => id.toString() === req.params.userId)) {
            room.coHosts.push(req.params.userId);
        }
        room.moderators = (room.moderators || []).filter(id => !idsEqual(id, req.params.userId));
        const p = getParticipant(room, req.params.userId);
        if (!p) {
            const e = new Error('Participant must be inside the room to become a co-host');
            e.status = 400;
            throw e;
        }
        if (p) {
            p.role = 'cohost';
            p.raisedHand = false;
        }
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json({ success: true, room: populatedRoom });
    } catch (error) { next(error); }
};

exports.removeCoHost = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageAdmins(room, req.userId)) { const e = new Error('Only host can remove co-host'); e.status = 403; throw e; }
        if (idsEqual(req.params.userId, req.userId)) {
            const e = new Error('Use ownership transfer instead of removing yourself as co-host');
            e.status = 400;
            throw e;
        }

        room.coHosts = (room.coHosts || []).filter(id => id.toString() !== req.params.userId);
        const p = getParticipant(room, req.params.userId);
        if (p && p.role === 'cohost') {
            p.role = p.seatIndex >= 1 ? 'speaker' : 'listener';
        }
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json({ success: true, room: populatedRoom });
    } catch (error) { next(error); }
};

exports.addModerator = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageAdmins(room, req.userId)) { const e = new Error('Only host can manage moderators'); e.status = 403; throw e; }
        if (!canManageTarget(room, req.userId, req.params.userId)) {
            const e = new Error('You cannot assign that participant as moderator');
            e.status = 403;
            throw e;
        }

        const targetUserId = req.params.userId;
        const targetUser = await User.findById(targetUserId).select('_id');
        if (!targetUser) { const e = new Error('User not found'); e.status = 404; throw e; }
        if (room.coHosts?.some(id => idsEqual(id, targetUserId))) {
            const e = new Error('Remove co-host status before assigning moderator');
            e.status = 400;
            throw e;
        }

        if (!room.moderators) room.moderators = [];
        if (!room.moderators.some(id => id.toString() === targetUserId)) {
            room.moderators.push(targetUserId);
        }

        const participant = getParticipant(room, targetUserId);
        if (!participant) {
            const e = new Error('Participant must be inside the room to become a moderator');
            e.status = 400;
            throw e;
        }
        if (participant && participant.role !== 'host' && participant.role !== 'cohost') {
            participant.role = 'moderator';
            participant.raisedHand = false;
        }

        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json(populatedRoom);
    } catch (error) { next(error); }
};

exports.removeModerator = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageAdmins(room, req.userId)) { const e = new Error('Only host can manage moderators'); e.status = 403; throw e; }

        const targetUserId = req.params.userId;
        room.moderators = (room.moderators || []).filter(id => id.toString() !== targetUserId);

        const participant = getParticipant(room, targetUserId);
        if (participant && participant.role === 'moderator') {
            participant.role = participant.seatIndex >= 1 ? 'speaker' : 'listener';
        }

        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'roles_updated');
        }

        res.json(populatedRoom);
    } catch (error) { next(error); }
};

// Report room
exports.reportRoom = async (req, res, next) => {
    try {
        const { reason = 'spam' } = req.body;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!room.reports) room.reports = [];
        room.reports.push({ userId: req.userId, reason, createdAt: new Date() });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);
        res.json({ success: true, message: 'Room reported. Thank you for keeping the community safe.' });
    } catch (error) { next(error); }
};

// Follow/unfollow room
exports.followRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!room.followers) room.followers = [];
        if (!room.followers.some(id => id.toString() === req.userId)) {
            room.followers.push(req.userId);
            room.metrics.followers = (room.metrics.followers || 0) + 1;
        }
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'followers_updated');
        }

        res.json({
            success: true,
            followers: populatedRoom.metrics?.followers ?? room.metrics.followers,
            room: populatedRoom
        });
    } catch (error) { next(error); }
};

exports.unfollowRoom = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        room.followers = (room.followers || []).filter(id => id.toString() !== req.userId);
        room.metrics.followers = Math.max(0, (room.metrics.followers || 0) - 1);
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'followers_updated');
        }

        res.json({
            success: true,
            followers: populatedRoom.metrics?.followers ?? room.metrics.followers,
            room: populatedRoom
        });
    } catch (error) { next(error); }
};

exports.banParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canManageStage(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }
        if (!canManageTarget(room, req.userId, req.params.userId)) {
            const e = new Error('You cannot ban that participant');
            e.status = 403;
            throw e;
        }

        const targetUserId = req.params.userId;
        const { reason = 'Violation of room rules', expiresAt } = req.body || {};

        room.participants = room.participants.filter(p => p.userId.toString() !== targetUserId);
        room.coHosts = (room.coHosts || []).filter(id => !idsEqual(id, targetUserId));
        room.moderators = (room.moderators || []).filter(id => !idsEqual(id, targetUserId));

        const existingBan = (room.bans || []).find(b => b.userId.toString() === targetUserId);
        if (existingBan) {
            existingBan.reason = reason;
            existingBan.bannedAt = new Date();
            existingBan.expiresAt = expiresAt ? new Date(expiresAt) : null;
        } else {
            room.bans.push({
                userId: targetUserId,
                reason,
                bannedAt: new Date(),
                expiresAt: expiresAt ? new Date(expiresAt) : null
            });
        }

        const redis = req.app.get('redis');
        await room.save();
        await invalidateRoomCache(redis, room._id);
        if (redis && redis.isReady) {
            const key = `room:${room._id}:users`;
            await redis.sRem(key, targetUserId.toString());
            const count = await redis.sCard(key);
            await redis.set(`room:${room._id}:count`, count.toString());
        }

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:participant:left', { userId: targetUserId });
            io.to(`user:${targetUserId}`).emit('user:banned', { roomId: room._id, reason });
            emitLobbyUpdate(io, room, 'moderation_updated');
        }

        res.json({ success: true, bans: room.bans });
    } catch (error) { next(error); }
};

exports.unbanParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!isRoomAdmin(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }

        room.bans = (room.bans || []).filter(b => b.userId.toString() !== req.params.userId);
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const io = req.app.get('io');
        if (io) emitLobbyUpdate(io, room, 'moderation_updated');

        res.json({ success: true, bans: room.bans });
    } catch (error) { next(error); }
};

exports.setAnnouncement = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canEditAnnouncement(room, req.userId)) { const e = new Error('Only the room owner can update the announcement'); e.status = 403; throw e; }

        room.announcement = {
            text: req.body?.announcement || req.body?.text || '',
            updatedAt: new Date(),
            updatedBy: req.userId
        };
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(room._id);
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'updated');
        }

        res.json(populatedRoom);
    } catch (error) { next(error); }
};

// Get bans list
exports.getBans = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id)
            .populate('bans.userId', 'username avatar');
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!isRoomAdmin(room, req.userId)) { const e = new Error('Not authorized'); e.status = 403; throw e; }
        res.json(room.bans || []);
    } catch (error) { next(error); }
};

exports.getReports = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id)
            .populate('reports.userId', 'username avatar');
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canViewReports(room, req.userId)) {
            const e = new Error('Only the room owner can view reports');
            e.status = 403;
            throw e;
        }

        res.json(room.reports || []);
    } catch (error) { next(error); }
};

exports.transferOwnership = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canTransferOwnership(room, req.userId)) {
            const e = new Error('Only the room owner can transfer ownership');
            e.status = 403;
            throw e;
        }

        const targetUserId = req.params.userId;
        if (idsEqual(targetUserId, req.userId)) {
            const e = new Error('Pick another participant to transfer ownership');
            e.status = 400;
            throw e;
        }

        const targetParticipant = getParticipant(room, targetUserId);
        if (!targetParticipant) {
            const e = new Error('Target participant must be inside the room');
            e.status = 404;
            throw e;
        }

        const oldOwnerParticipant = getParticipant(room, req.userId);

        room.hostId = targetUserId;
        if (!room.coHosts) room.coHosts = [];
        room.coHosts = (room.coHosts || []).filter(id => !idsEqual(id, targetUserId));
        room.moderators = (room.moderators || []).filter(id => !idsEqual(id, targetUserId));

        if (oldOwnerParticipant) {
            if (!(room.coHosts || []).some(id => idsEqual(id, req.userId))) {
                room.coHosts.push(req.userId);
            }
            oldOwnerParticipant.role = 'cohost';
            oldOwnerParticipant.raisedHand = false;
        }

        targetParticipant.role = 'host';
        targetParticipant.raisedHand = false;

        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:updated', populatedRoom);
            emitLobbyUpdate(io, populatedRoom, 'ownership_transferred');
        }

        res.json(populatedRoom);
    } catch (error) { next(error); }
};
