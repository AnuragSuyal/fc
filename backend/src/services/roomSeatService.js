const {
    MAX_STAGE_SEATS,
    ROOM_ACTIONS,
    assertRoomPermission,
    countActiveSpeakers,
    findNextAvailableSeat,
    getMaxActiveSpeakers,
    getParticipant,
    idsEqual,
    canPerformRoomAction
} = require('./roomPermissionService');

const resolveSeatType = (room, seatIndex) =>
    room?.type === 'video' && seatIndex === 1 ? 'host_reserved' : 'speaker';

const syncSeatStates = (room) => {
    if (!room) return [];

    const existingSeatStates = Array.isArray(room.seatStates) ? room.seatStates : [];
    const lockedSeatSet = new Set(
        (Array.isArray(room.lockedSeats) ? room.lockedSeats : [])
            .map((entry) => Number(entry))
            .filter((entry) => Number.isInteger(entry) && entry >= 1 && entry <= MAX_STAGE_SEATS)
    );
    const participantBySeat = new Map();

    for (const participant of room.participants || []) {
        const seatIndex = Number(participant?.seatIndex);
        if (!Number.isInteger(seatIndex) || seatIndex < 1 || seatIndex > MAX_STAGE_SEATS) {
            continue;
        }
        participantBySeat.set(seatIndex, participant.userId || null);
    }

    const now = new Date();
    const nextSeatStates = [];

    for (let seatIndex = 1; seatIndex <= MAX_STAGE_SEATS; seatIndex += 1) {
        const existing = existingSeatStates.find((entry) => Number(entry?.seatIndex) === seatIndex) || {};
        const occupiedByUserId = participantBySeat.get(seatIndex) || null;
        const seatType = existing.seatType || resolveSeatType(room, seatIndex);
        const isLocked = existing.isLocked === true || lockedSeatSet.has(seatIndex);

        const nextState = {
            seatIndex,
            occupiedByUserId,
            isLocked,
            lockedByUserId: isLocked ? (existing.lockedByUserId || null) : null,
            lockedAt: isLocked ? (existing.lockedAt || now) : null,
            lockReason: isLocked ? String(existing.lockReason || '') : '',
            seatType,
            updatedAt: existing.updatedAt || now
        };

        const changed = (
            !idsEqual(existing.occupiedByUserId, nextState.occupiedByUserId) ||
            existing.isLocked !== nextState.isLocked ||
            !idsEqual(existing.lockedByUserId, nextState.lockedByUserId) ||
            String(existing.lockReason || '') !== nextState.lockReason ||
            String(existing.seatType || '') !== nextState.seatType
        );
        if (changed) {
            nextState.updatedAt = now;
        }

        nextSeatStates.push(nextState);
    }

    room.seatStates = nextSeatStates;
    room.lockedSeats = nextSeatStates
        .filter((seat) => seat.isLocked)
        .map((seat) => seat.seatIndex);

    return Array.isArray(room.seatStates) ? room.seatStates : nextSeatStates;
};

const getSeatState = (room, seatIndex) => {
    const nextSeatIndex = Number(seatIndex);
    if (!Number.isInteger(nextSeatIndex) || nextSeatIndex < 1 || nextSeatIndex > MAX_STAGE_SEATS) {
        return null;
    }

    syncSeatStates(room);
    return room.seatStates?.find((seat) => Number(seat?.seatIndex) === nextSeatIndex) || null;
};

const getLockedSeatCount = (room) =>
    syncSeatStates(room).filter((seat) => seat.isLocked === true).length;

const isSeatLocked = (room, seatIndex) => getSeatState(room, seatIndex)?.isLocked === true;

const serializeSeatState = (seatState) => {
    if (!seatState) return null;
    return {
        seatIndex: seatState.seatIndex,
        occupiedByUserId: seatState.occupiedByUserId?.toString() || null,
        isLocked: seatState.isLocked === true,
        lockedByUserId: seatState.lockedByUserId?.toString() || null,
        lockedAt: seatState.lockedAt ? new Date(seatState.lockedAt).toISOString() : null,
        lockReason: String(seatState.lockReason || ''),
        seatType: String(seatState.seatType || 'speaker'),
        updatedAt: seatState.updatedAt ? new Date(seatState.updatedAt).toISOString() : null
    };
};

const getSeatStateSnapshot = (room) =>
    syncSeatStates(room).map((seatState) => serializeSeatState(seatState));

const validateSeatIndexWithinStage = (room, seatIndex, {
    allowInactiveSeats = true
} = {}) => {
    const nextSeatIndex = Number(seatIndex);
    if (!Number.isInteger(nextSeatIndex) || nextSeatIndex < 1 || nextSeatIndex > MAX_STAGE_SEATS) {
        const error = new Error(`Seat number must be between 1 and ${MAX_STAGE_SEATS}`);
        error.status = 400;
        throw error;
    }
    if (!allowInactiveSeats && nextSeatIndex > getMaxActiveSpeakers(room)) {
        const error = new Error(`Only ${getMaxActiveSpeakers(room)} active speaker seats are open right now`);
        error.status = 403;
        throw error;
    }
    return nextSeatIndex;
};

const canLockSeat = ({ room, actorUserId, seatIndex }) =>
    Boolean(
        getSeatState(room, seatIndex) &&
        canPerformRoomAction({
            room,
            actorUserId,
            action: ROOM_ACTIONS.LOCK_SEAT
        })
    );

const canUnlockSeat = ({ room, actorUserId, seatIndex }) =>
    Boolean(
        getSeatState(room, seatIndex) &&
        canPerformRoomAction({
            room,
            actorUserId,
            action: ROOM_ACTIONS.UNLOCK_SEAT
        })
    );

const assertSeatJoinAllowed = ({
    room,
    userId,
    seatIndex,
    ignoreOccupantUserId = null
}) => {
    const nextSeatIndex = validateSeatIndexWithinStage(room, seatIndex, {
        allowInactiveSeats: false
    });
    const seatState = getSeatState(room, nextSeatIndex);

    if (seatState?.isLocked) {
        const error = new Error('This seat is locked by room management.');
        error.status = 403;
        throw error;
    }

    const occupied = room.participants?.find((participant) =>
        participant.seatIndex === nextSeatIndex &&
        !idsEqual(participant.userId, ignoreOccupantUserId || userId)
    );
    if (occupied) {
        const error = new Error('That seat is already occupied.');
        error.status = 409;
        throw error;
    }

    return seatState;
};

const moveParticipantToSeat = ({ room, actorUserId, targetUserId, seatIndex = null }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.MOVE_PARTICIPANT_TO_SEAT,
        targetUserId
    }, 'You cannot move that participant to the stage');

    const participant = getParticipant(room, targetUserId);
    if (!participant) {
        const error = new Error('Participant not found');
        error.status = 404;
        throw error;
    }

    const nextSeatIndex = seatIndex == null
        ? findNextAvailableSeat(room)
        : validateSeatIndexWithinStage(room, seatIndex, { allowInactiveSeats: false });
    if (!Number.isInteger(nextSeatIndex)) {
        const error = new Error('No unlocked stage seat is available right now');
        error.status = 409;
        throw error;
    }

    assertSeatJoinAllowed({
        room,
        userId: targetUserId,
        seatIndex: nextSeatIndex,
        ignoreOccupantUserId: targetUserId
    });

    if (participant.seatIndex < 1 && countActiveSpeakers(room) >= getMaxActiveSpeakers(room)) {
        const error = new Error('All active speaker seats are already full');
        error.status = 400;
        throw error;
    }

    participant.seatIndex = nextSeatIndex;
    participant.raisedHand = false;
    if (participant.role === 'listener') {
        participant.role = 'speaker';
    }

    syncSeatStates(room);
    return participant;
};

const demoteParticipantFromSeat = ({ room, actorUserId, targetUserId }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.DEMOTE_PARTICIPANT,
        targetUserId
    }, 'You cannot move that participant to the audience');

    const participant = getParticipant(room, targetUserId);
    if (!participant) {
        const error = new Error('Participant not found');
        error.status = 404;
        throw error;
    }

    participant.seatIndex = -1;
    participant.raisedHand = false;
    if (participant.role === 'speaker') {
        participant.role = 'listener';
    }

    syncSeatStates(room);
    return participant;
};

const lockSeat = ({ room, actorUserId, seatIndex, reason = '' }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.LOCK_SEAT
    }, 'You do not have permission to lock this seat.');

    const nextSeatIndex = validateSeatIndexWithinStage(room, seatIndex);
    const seatState = getSeatState(room, nextSeatIndex);

    if (seatState?.occupiedByUserId) {
        const error = new Error('Only empty seats can be locked.');
        error.status = 409;
        throw error;
    }

    seatState.isLocked = true;
    seatState.lockedByUserId = actorUserId;
    seatState.lockedAt = new Date();
    seatState.lockReason = String(reason || '').trim().slice(0, 160);
    seatState.updatedAt = new Date();
    room.lockedSeats = Array.from(
        new Set([...(room.lockedSeats || []).filter((entry) => entry !== nextSeatIndex), nextSeatIndex])
    );
    syncSeatStates(room);
    return seatState;
};

const unlockSeat = ({ room, actorUserId, seatIndex }) => {
    assertRoomPermission({
        room,
        actorUserId,
        action: ROOM_ACTIONS.UNLOCK_SEAT
    }, 'You do not have permission to unlock this seat.');

    const nextSeatIndex = validateSeatIndexWithinStage(room, seatIndex);
    const seatState = getSeatState(room, nextSeatIndex);
    if (!seatState) {
        const error = new Error('Seat not found');
        error.status = 404;
        throw error;
    }

    seatState.isLocked = false;
    seatState.lockedByUserId = null;
    seatState.lockedAt = null;
    seatState.lockReason = '';
    seatState.updatedAt = new Date();
    room.lockedSeats = (room.lockedSeats || []).filter((entry) => entry !== nextSeatIndex);
    syncSeatStates(room);
    return seatState;
};

module.exports = {
    assertSeatJoinAllowed,
    canLockSeat,
    canUnlockSeat,
    demoteParticipantFromSeat,
    getLockedSeatCount,
    getSeatState,
    getSeatStateSnapshot,
    isSeatLocked,
    lockSeat,
    moveParticipantToSeat,
    serializeSeatState,
    syncSeatStates,
    unlockSeat,
    validateSeatIndexWithinStage
};
