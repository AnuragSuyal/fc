const MAX_STAGE_SEATS = 8;

const ADMIN_REALTIME_SETTING_KEYS = new Set([
    'hdVoice',
    'banTextChat',
    'banPhotoChat',
    'stageJoinsLocked'
]);

const idsEqual = (left, right) => {
    if (!left || !right) return false;
    return left.toString() === right.toString();
};

const getParticipant = (room, userId) => {
    if (!room || !userId) return null;
    return room.participants?.find(participant => idsEqual(participant.userId, userId)) || null;
};

const isRoomOwner = (room, userId) => idsEqual(room?.hostId, userId);

const isRoomAdmin = (room, userId) => {
    if (!room || !userId) return false;
    if (isRoomOwner(room, userId)) return true;
    if (room.coHosts?.some(id => idsEqual(id, userId))) return true;
    if (room.moderators?.some(id => idsEqual(id, userId))) return true;
    return false;
};

const isRoomSpeaker = (room, userId) => {
    const participant = getParticipant(room, userId);
    if (!participant) return false;
    return (
        participant.seatIndex >= 0 ||
        participant.role === 'speaker' ||
        participant.role === 'moderator' ||
        participant.role === 'cohost' ||
        participant.role === 'host'
    );
};

const getAuthorityLevel = (room, userId) => {
    if (!room || !userId) return 0;
    if (isRoomOwner(room, userId)) return 4;
    if (isRoomAdmin(room, userId)) return 3;
    if (isRoomSpeaker(room, userId)) return 2;
    return 1;
};

const canManageTarget = (room, actorUserId, targetUserId) => {
    if (!room || !actorUserId || !targetUserId) return false;
    if (idsEqual(actorUserId, targetUserId)) return false;
    return getAuthorityLevel(room, actorUserId) > getAuthorityLevel(room, targetUserId);
};

const canManageStage = (room, userId) => isRoomAdmin(room, userId);
const canManageRealtimeSafety = (room, userId) => isRoomAdmin(room, userId);
const canManageRoomIdentity = (room, userId) => isRoomOwner(room, userId);
const canManageRoomAccess = (room, userId) => isRoomOwner(room, userId);
const canManageGifting = (room, userId) => isRoomOwner(room, userId);
const canManageAdmins = (room, userId) => isRoomOwner(room, userId);
const canEditAnnouncement = (room, userId) => isRoomOwner(room, userId);
const canTransferOwnership = (room, userId) => isRoomOwner(room, userId);
const canViewReports = (room, userId) => isRoomOwner(room, userId);
const canEndRoom = (room, userId) => isRoomOwner(room, userId);

const getMaxActiveSpeakers = (room) => {
    const rawValue = Number(room?.settings?.maxActiveSpeakers);
    if (!Number.isFinite(rawValue)) return MAX_STAGE_SEATS;
    return Math.max(1, Math.min(MAX_STAGE_SEATS, Math.trunc(rawValue)));
};

const countActiveSpeakers = (room) =>
    room?.participants?.filter(participant => participant.seatIndex >= 1).length || 0;

const findNextAvailableSeat = (room) => {
    const maxSeats = getMaxActiveSpeakers(room);
    for (let seatIndex = 1; seatIndex <= maxSeats; seatIndex += 1) {
        const occupied = room.participants?.some(participant => participant.seatIndex === seatIndex);
        const locked = room.lockedSeats?.includes(seatIndex);
        if (!occupied && !locked) {
            return seatIndex;
        }
    }

    return null;
};

const canJoinStageDirectly = (room, userId) => {
    if (canManageStage(room, userId)) return true;
    return !room?.settings?.stageJoinsLocked && !room?.settings?.requireApproval;
};

const canUseRoomGifts = (room, userId) =>
    room?.settings?.allowGifts !== false || isRoomOwner(room, userId);

const sanitizeRoomUpdatePayload = (room, userId, payload = {}) => {
    if (!room || !userId) return null;
    if (canManageRoomIdentity(room, userId)) {
        return payload;
    }

    if (!isRoomAdmin(room, userId)) {
        return null;
    }

    const providedFields = Object.keys(payload).filter(field => payload[field] !== undefined);
    if (providedFields.length === 0 || providedFields.some(field => field !== 'settings')) {
        return null;
    }

    const incomingSettings = payload.settings && typeof payload.settings === 'object'
        ? payload.settings
        : {};
    const allowedSettings = Object.fromEntries(
        Object.entries(incomingSettings).filter(([key]) => ADMIN_REALTIME_SETTING_KEYS.has(key))
    );

    if (Object.keys(allowedSettings).length === 0) {
        return null;
    }

    return { settings: allowedSettings };
};

module.exports = {
    ADMIN_REALTIME_SETTING_KEYS,
    MAX_STAGE_SEATS,
    canEditAnnouncement,
    canEndRoom,
    canJoinStageDirectly,
    canManageAdmins,
    canManageGifting,
    canManageRealtimeSafety,
    canManageRoomAccess,
    canManageRoomIdentity,
    canManageStage,
    canManageTarget,
    canTransferOwnership,
    canUseRoomGifts,
    canViewReports,
    countActiveSpeakers,
    findNextAvailableSeat,
    getAuthorityLevel,
    getMaxActiveSpeakers,
    getParticipant,
    idsEqual,
    isRoomAdmin,
    isRoomOwner,
    isRoomSpeaker,
    sanitizeRoomUpdatePayload
};
