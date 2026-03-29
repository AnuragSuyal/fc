// Extra room admin actions – imported into roomController or used standalone
const Room = require('../models/Room');
const User = require('../models/User');
const {
    getNextAdminUnlockLevel,
    getRoomAdminLimit
} = require('../services/roomProgressionService');
const {
    ROOM_ACTIONS,
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
    isRoomAdmin,
    assertRoomPermission
} = require('../services/roomPermissionService');
const {
    ROOM_UPDATE_EVENTS,
    decorateRoomPayload,
    emitRoomUpdate,
    populateRoomById
} = require('../services/roomSettingsService');
const {
    banParticipant: applyBanParticipant,
    muteParticipant: applyMuteParticipant,
    unbanParticipant: applyUnbanParticipant,
} = require('../services/roomModerationService');
const {
    canLockSeat,
    canUnlockSeat,
    demoteParticipantFromSeat,
    getLockedSeatCount,
    getSeatStateSnapshot,
    lockSeat: applyLockSeat,
    moveParticipantToSeat,
    serializeSeatState,
    unlockSeat: applyUnlockSeat,
    validateSeatIndexWithinStage
} = require('../services/roomSeatService');
const { logRoomAuditEvent } = require('../services/roomAuditService');
const roomCacheKey = (roomId) => `cache:room:${roomId}`;

const invalidateRoomCache = async (redis, roomId) => {
    if (!redis || !redis.isReady) return;
    await redis.del(roomCacheKey(roomId));
};

// Lock/unlock a seat with centralized seat-state metadata
exports.lockSeat = async (req, res, next) => {
    try {
        const { seatIndex } = req.params;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        const idx = validateSeatIndexWithinStage(room, parseInt(seatIndex));
        if (!canLockSeat({ room, actorUserId: req.userId, seatIndex: idx })) {
            const error = new Error('You do not have permission to lock this seat.');
            error.status = 403;
            throw error;
        }
        const lockedSeat = applyLockSeat({
            room,
            actorUserId: req.userId,
            seatIndex: idx,
            reason: req.body?.reason
        });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const seatSnapshot = serializeSeatState(lockedSeat);
        const updatedSeats = getSeatStateSnapshot(populatedRoom || room);
        const lockedSeatCount = getLockedSeatCount(populatedRoom || room);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:seat_locked', {
                roomId: room._id.toString(),
                seatIndex: idx,
                isLocked: true,
                lockedByUserId: seatSnapshot?.lockedByUserId || req.userId,
                lockedAt: seatSnapshot?.lockedAt,
                lockedSeatCount,
                updatedSeat: seatSnapshot,
                updatedSeats
            });
            emitRoomUpdate(io, populatedRoom || room, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'seat_updated',
                extraPayload: {
                    seatIndex: idx,
                    isLocked: true,
                    lockedByUserId: seatSnapshot?.lockedByUserId || req.userId,
                    lockedAt: seatSnapshot?.lockedAt,
                    lockedSeatCount,
                    updatedSeat: seatSnapshot,
                    updatedSeats
                }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            action: 'room.lock_seat',
            after: {
                seat: seatSnapshot,
                lockedSeatCount
            },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({
            success: true,
            lockedSeats: populatedRoom?.lockedSeats || room.lockedSeats,
            seat: seatSnapshot,
            lockedSeatCount,
            room: decorateRoomPayload(populatedRoom || room, req.userId)
        });
    } catch (error) { next(error); }
};

exports.unlockSeat = async (req, res, next) => {
    try {
        const { seatIndex } = req.params;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        const idx = validateSeatIndexWithinStage(room, parseInt(seatIndex));
        if (!canUnlockSeat({ room, actorUserId: req.userId, seatIndex: idx })) {
            const error = new Error('You do not have permission to unlock this seat.');
            error.status = 403;
            throw error;
        }
        const unlockedSeat = applyUnlockSeat({ room, actorUserId: req.userId, seatIndex: idx });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const seatSnapshot = serializeSeatState(unlockedSeat);
        const updatedSeats = getSeatStateSnapshot(populatedRoom || room);
        const lockedSeatCount = getLockedSeatCount(populatedRoom || room);
        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:seat_unlocked', {
                roomId: room._id.toString(),
                seatIndex: idx,
                isLocked: false,
                lockedByUserId: null,
                lockedAt: null,
                lockedSeatCount,
                updatedSeat: seatSnapshot,
                updatedSeats
            });
            emitRoomUpdate(io, populatedRoom || room, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'seat_updated',
                extraPayload: {
                    seatIndex: idx,
                    isLocked: false,
                    lockedByUserId: null,
                    lockedAt: null,
                    lockedSeatCount,
                    updatedSeat: seatSnapshot,
                    updatedSeats
                }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            action: 'room.unlock_seat',
            after: {
                seat: seatSnapshot,
                lockedSeatCount
            },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({
            success: true,
            lockedSeats: populatedRoom?.lockedSeats || room.lockedSeats,
            seat: seatSnapshot,
            lockedSeatCount,
            room: decorateRoomPayload(populatedRoom || room, req.userId)
        });
    } catch (error) { next(error); }
};

// Promote to speaker
exports.promoteParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        const participant = moveParticipantToSeat({
            room,
            actorUserId: req.userId,
            targetUserId: req.params.userId,
            seatIndex: req.body?.seatIndex
        });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'roles_updated',
                extraPayload: {
                    userId: req.params.userId,
                    seatIndex: participant.seatIndex
                }
            });
            io.to(`user:${req.params.userId}`).emit('room:promoted', { roomId: room._id });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId: req.params.userId,
            action: 'room.promote_participant',
            after: { seatIndex: participant.seatIndex, role: participant.role },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, room: decorateRoomPayload(populatedRoom, req.userId) });
    } catch (error) { next(error); }
};

// Demote speaker to listener
exports.demoteParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        const participant = demoteParticipantFromSeat({
            room,
            actorUserId: req.userId,
            targetUserId: req.params.userId
        });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const populatedRoom = await populateRoomById(room._id);
        const io = req.app.get('io');
        if (io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SEATS,
                lobbyAction: 'roles_updated',
                extraPayload: {
                    userId: req.params.userId,
                    seatIndex: -1
                }
            });
            io.to(`user:${req.params.userId}`).emit('room:demoted', { roomId: room._id });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId: req.params.userId,
            action: 'room.demote_participant',
            after: { seatIndex: participant.seatIndex, role: participant.role },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, room: decorateRoomPayload(populatedRoom, req.userId) });
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'roles_updated',
                extraPayload: { userId: req.params.userId, role: 'cohost' }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            targetUserId: req.params.userId,
            action: 'room.assign_cohost',
            after: { role: 'cohost' },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, room: decorateRoomPayload(populatedRoom, req.userId) });
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'roles_updated',
                extraPayload: { userId: req.params.userId, role: p?.role || 'listener' }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            targetUserId: req.params.userId,
            action: 'room.remove_cohost',
            after: { role: p?.role || 'listener' },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, room: decorateRoomPayload(populatedRoom, req.userId) });
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
        const isAlreadyModerator =
            room.moderators.some(id => id.toString() === targetUserId);
        if (!isAlreadyModerator) {
            const adminLimit = getRoomAdminLimit(room.level);
            if (room.moderators.length >= adminLimit) {
                const nextUnlockLevel = getNextAdminUnlockLevel(room.level);
                const e = new Error(
                    nextUnlockLevel == null
                        ? `This room already has the max ${adminLimit} admins.`
                        : `Room level ${room.level} allows ${adminLimit} admins. Reach level ${nextUnlockLevel} to unlock 5 admins.`
                );
                e.status = 400;
                throw e;
            }
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'roles_updated',
                extraPayload: { userId: targetUserId, role: 'moderator' }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            targetUserId,
            action: 'room.assign_admin',
            after: { role: 'moderator' },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json(decorateRoomPayload(populatedRoom, req.userId));
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'roles_updated',
                extraPayload: { userId: targetUserId, role: participant?.role || 'listener' }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            targetUserId,
            action: 'room.remove_admin',
            after: { role: participant?.role || 'listener' },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) { next(error); }
};

// Report room
exports.reportRoom = async (req, res, next) => {
    try {
        const { reason = 'spam', targetUserId = null, type = targetUserId ? 'user' : 'room' } = req.body;
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!room.reports) room.reports = [];
        room.reports.push({ userId: req.userId, targetUserId, type, reason, createdAt: new Date() });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);
        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'member',
            targetUserId,
            action: 'room.report',
            after: { type, reason },
            source: 'rest',
            success: true,
            requestId: req.id
        });
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SETTINGS,
                lobbyAction: 'followers_updated'
            });
        }

        res.json({
            success: true,
            followers: populatedRoom.metrics?.followers ?? room.metrics.followers,
            room: decorateRoomPayload(populatedRoom, req.userId)
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SETTINGS,
                lobbyAction: 'followers_updated'
            });
        }

        res.json({
            success: true,
            followers: populatedRoom.metrics?.followers ?? room.metrics.followers,
            room: decorateRoomPayload(populatedRoom, req.userId)
        });
    } catch (error) { next(error); }
};

exports.banParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        const targetUserId = req.params.userId;
        const { reason = 'Violation of room rules', expiresAt } = req.body || {};
        applyBanParticipant({ room, actorUserId: req.userId, targetUserId, reason, expiresAt });

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
            io.to(`room:${room._id}`).emit('room:participant:left', {
                roomId: room._id.toString(),
                userId: targetUserId
            });
            io.to(`user:${targetUserId}`).emit('user:banned', { roomId: room._id, reason });
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'moderation_updated',
                extraPayload: { userId: targetUserId, banned: true }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId,
            action: 'room.ban_participant',
            after: { reason, expiresAt: expiresAt || null },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, bans: room.bans });
    } catch (error) { next(error); }
};

exports.unbanParticipant = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        applyUnbanParticipant({ room, actorUserId: req.userId, targetUserId: req.params.userId });
        await room.save();
        await invalidateRoomCache(req.app.get('redis'), room._id);

        const io = req.app.get('io');
        if (io) {
            emitRoomUpdate(io, room, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'moderation_updated',
                extraPayload: { userId: req.params.userId, banned: false }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'admin',
            targetUserId: req.params.userId,
            action: 'room.unban_participant',
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json({ success: true, bans: room.bans });
    } catch (error) { next(error); }
};

exports.setAnnouncement = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id);
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canEditAnnouncement(room, req.userId)) { const e = new Error('Only room hosts and admins can update the announcement'); e.status = 403; throw e; }

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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.IDENTITY,
                lobbyAction: 'updated'
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: isRoomAdmin(room, req.userId) ? 'admin' : 'member',
            action: 'room.update_announcement',
            after: { announcement: room.announcement.text },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) { next(error); }
};

// Get bans list
exports.getBans = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id)
            .populate('bans.userId', 'username avatar');
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        assertRoomPermission({
            room,
            actorUserId: req.userId,
            action: ROOM_ACTIONS.VIEW_BANS
        }, 'Not authorized');
        res.json(room.bans || []);
    } catch (error) { next(error); }
};

exports.getReports = async (req, res, next) => {
    try {
        const room = await Room.findById(req.params.id)
            .populate('reports.userId', 'username avatar')
            .populate('reports.targetUserId', 'username avatar');
        if (!room) { const e = new Error('Room not found'); e.status = 404; throw e; }
        if (!canViewReports(room, req.userId)) {
            const e = new Error('Only room hosts and admins can view reports');
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
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.ROLES,
                lobbyAction: 'ownership_transferred',
                extraPayload: { userId: targetUserId, transferred: true }
            });
        }

        await logRoomAuditEvent({
            roomId: room._id,
            actorId: req.userId,
            actorRole: 'host',
            targetUserId,
            action: 'room.transfer_ownership',
            after: { hostId: targetUserId },
            source: 'rest',
            success: true,
            requestId: req.id
        });

        res.json(decorateRoomPayload(populatedRoom, req.userId));
    } catch (error) { next(error); }
};
