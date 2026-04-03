const CONTROLLER_ROLES = new Set(['host', 'cohost', 'moderator']);

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number') return String(value);
    if (typeof value === 'object') {
        const bsonType = value._bsontype || value.constructor?.name;
        if (bsonType === 'ObjectId' || bsonType === 'ObjectID') {
            return value.toString();
        }
        if ('_id' in value && value._id && value._id !== value) {
            return toIdString(value._id);
        }
        if ('id' in value && value.id && value.id !== value) {
            return toIdString(value.id);
        }
    }

    if (typeof value.toString === 'function') {
        const normalized = value.toString();
        if (normalized && normalized !== '[object Object]') {
            return normalized;
        }
    }

    return '';
};

const idsEqual = (left, right) => {
    const normalizedLeft = toIdString(left);
    const normalizedRight = toIdString(right);
    if (!normalizedLeft || !normalizedRight) return false;
    return normalizedLeft === normalizedRight;
};

const isParticipantPresent = (participant) =>
    Boolean(participant) && participant.isPresent !== false;

const isControllerParticipant = (room, participant) => {
    if (!room || !participant?.userId) return false;

    const participantUserId = participant.userId.toString();
    if (idsEqual(room.hostId, participantUserId)) {
        return true;
    }
    if ((room.coHosts || []).some((entry) => idsEqual(entry, participantUserId))) {
        return true;
    }
    if ((room.moderators || []).some((entry) => idsEqual(entry, participantUserId))) {
        return true;
    }

    return CONTROLLER_ROLES.has(String(participant.role || '').trim().toLowerCase());
};

const getPresentParticipants = (room) =>
    (room?.participants || []).filter((participant) => isParticipantPresent(participant));

const getPresentControllerParticipants = (room) =>
    getPresentParticipants(room).filter((participant) =>
        isControllerParticipant(room, participant)
    );

const forceAudienceMode = (room) => {
    if (!room) return false;

    let changed = false;
    for (const participant of room.participants || []) {
        const keepControllerSeat =
            isParticipantPresent(participant) && isControllerParticipant(room, participant);
        if (keepControllerSeat) {
            continue;
        }

        if ((participant.seatIndex || -1) >= 1) {
            participant.seatIndex = -1;
            changed = true;
        }
        if (participant.isSpeaking === true) {
            participant.isSpeaking = false;
            changed = true;
        }
        if (participant.raisedHand === true) {
            participant.raisedHand = false;
            changed = true;
        }
        if (!isControllerParticipant(room, participant) && participant.role === 'speaker') {
            participant.role = 'listener';
            changed = true;
        }
    }

    return changed;
};

const recalculateRoomPresenceState = (room, { resetSeatsWhenInactive = true } = {}) => {
    if (!room) {
        return {
            hostPresent: false,
            adminCount: 0,
            activeControllersCount: 0,
            roomActive: false,
            inactiveSince: null
        };
    }

    const presentControllers = getPresentControllerParticipants(room);
    const hostPresent = presentControllers.some((participant) =>
        idsEqual(participant.userId, room.hostId)
    );
    const adminCount = presentControllers.filter(
        (participant) => !idsEqual(participant.userId, room.hostId)
    ).length;
    const activeControllersCount = presentControllers.length;
    const roomActive = !room.endedAt && activeControllersCount > 0;
    const presentParticipants = getPresentParticipants(room);

    room.hostPresent = hostPresent;
    room.adminCount = adminCount;
    room.activeControllersCount = activeControllersCount;
    room.roomActive = roomActive;
    room.participantCount = Array.isArray(room.participants) ? room.participants.length : 0;
    room.onlineCount = presentParticipants.length;

    if (roomActive) {
        room.inactiveSince = null;
    } else {
        room.inactiveSince = room.inactiveSince || new Date();
        if (resetSeatsWhenInactive) {
            forceAudienceMode(room);
        }
    }

    return {
        hostPresent,
        adminCount,
        activeControllersCount,
        roomActive,
        inactiveSince: room.inactiveSince || null
    };
};

const markParticipantPresence = (
    room,
    userId,
    { present = true, touchedAt = new Date() } = {}
) => {
    if (!room || !userId) return null;

    const participant = (room.participants || []).find((entry) =>
        idsEqual(entry.userId, userId)
    );
    if (!participant) return null;

    participant.isPresent = present;
    participant.lastActive = present ? touchedAt : new Date(0);
    if (!present) {
        participant.isSpeaking = false;
        participant.raisedHand = false;
        if (!isControllerParticipant(room, participant) && participant.role === 'speaker') {
            participant.role = 'listener';
        }
        if ((participant.seatIndex || -1) >= 1) {
            participant.seatIndex = -1;
        }
    }

    return participant;
};

const trackRecentRoomVisit = (user, roomId) => {
    if (!user || !roomId) return;

    const nextEntries = Array.isArray(user.recentRooms)
        ? user.recentRooms.filter((entry) => !idsEqual(entry?.roomId, roomId))
        : [];

    nextEntries.unshift({
        roomId,
        lastVisitedAt: new Date()
    });

    user.recentRooms = nextEntries.slice(0, 10);
};

module.exports = {
    forceAudienceMode,
    getPresentControllerParticipants,
    getPresentParticipants,
    isControllerParticipant,
    isParticipantPresent,
    markParticipantPresence,
    recalculateRoomPresenceState,
    trackRecentRoomVisit
};
