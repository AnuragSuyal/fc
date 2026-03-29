const {
    ROOM_ACTIONS,
    assertRoomPermission,
    getParticipant,
    idsEqual
} = require('./roomPermissionService');
const {
    demoteParticipantFromSeat,
    lockSeat,
    moveParticipantToSeat,
    unlockSeat
} = require('./roomSeatService');

const muteParticipant = ({ room, actorUserId, targetUserId, muted }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.MUTE_PARTICIPANT,
        targetUserId
    }, 'You cannot moderate that participant');

    const participant = getParticipant(room, targetUserId);
    if (!participant) {
        const error = new Error('User not in room');
        error.status = 404;
        throw error;
    }

    const shouldMute = Boolean(muted);
    participant.isMuted = shouldMute;
    if (shouldMute) {
        const exists = room.mutes?.some((entry) => idsEqual(entry.userId, targetUserId));
        if (!exists) {
            room.mutes.push({ userId: targetUserId });
        }
    } else {
        room.mutes = (room.mutes || []).filter((entry) => !idsEqual(entry.userId, targetUserId));
    }
    return participant;
};

const kickParticipant = ({ room, actorUserId, targetUserId }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.KICK_PARTICIPANT,
        targetUserId
    }, 'You cannot remove that participant');

    const beforeCount = room.participants.length;
    room.participants = room.participants.filter((participant) => !idsEqual(participant.userId, targetUserId));
    if (room.participants.length === beforeCount) {
        const error = new Error('User not in room');
        error.status = 404;
        throw error;
    }
};

const banParticipant = ({ room, actorUserId, targetUserId, reason, expiresAt = null }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.BAN_PARTICIPANT,
        targetUserId
    }, 'You cannot ban that participant');

    room.participants = room.participants.filter((participant) => !idsEqual(participant.userId, targetUserId));
    room.coHosts = (room.coHosts || []).filter((entry) => !idsEqual(entry, targetUserId));
    room.moderators = (room.moderators || []).filter((entry) => !idsEqual(entry, targetUserId));

    const existingBan = (room.bans || []).find((entry) => idsEqual(entry.userId, targetUserId));
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
};

const unbanParticipant = ({ room, actorUserId, targetUserId }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.UNBAN_PARTICIPANT
    }, 'Not authorized to unban members');

    room.bans = (room.bans || []).filter((entry) => !idsEqual(entry.userId, targetUserId));
    return room.bans;
};

module.exports = {
    banParticipant,
    demoteParticipantFromSeat,
    kickParticipant,
    lockSeat,
    moveParticipantToSeat,
    muteParticipant,
    unbanParticipant,
    unlockSeat
};
