const MAX_STAGE_SEATS = 8;

const ROOM_MODES = Object.freeze({
    NORMAL: 'normal',
    ACQUAINT: 'acquaint',
    AUCTION: 'auction'
});

const MODE_BY_ROOM_TYPE = Object.freeze({
    auction: ROOM_MODES.AUCTION,
    chat: ROOM_MODES.ACQUAINT,
    voice: ROOM_MODES.NORMAL,
    music: ROOM_MODES.NORMAL,
    video: ROOM_MODES.NORMAL,
    game: ROOM_MODES.NORMAL
});

const ROOM_ACTIONS = Object.freeze({
    UPDATE_ROOM_IDENTITY: 'update_room_identity',
    UPDATE_ROOM_ANNOUNCEMENT: 'update_room_announcement',
    UPDATE_ROOM_COVER: 'update_room_cover',
    UPDATE_ROOM_THEME: 'update_room_theme',
    UPDATE_ROOM_PERMISSIONS: 'update_room_permissions',
    UPDATE_ROOM_CONFIG: 'update_room_config',
    UPDATE_ROOM_MODE: 'update_room_mode',
    UPDATE_ROOM_SEATS: 'update_room_seats',
    LOCK_SEAT: 'lock_seat',
    UNLOCK_SEAT: 'unlock_seat',
    MOVE_PARTICIPANT_TO_SEAT: 'move_participant_to_seat',
    PROMOTE_PARTICIPANT: 'promote_participant',
    DEMOTE_PARTICIPANT: 'demote_participant',
    ASSIGN_ADMIN: 'assign_admin',
    REMOVE_ADMIN: 'remove_admin',
    ASSIGN_COHOST: 'assign_cohost',
    REMOVE_COHOST: 'remove_cohost',
    MUTE_PARTICIPANT: 'mute_participant',
    KICK_PARTICIPANT: 'kick_participant',
    BAN_PARTICIPANT: 'ban_participant',
    UNBAN_PARTICIPANT: 'unban_participant',
    VIEW_BANS: 'view_bans',
    VIEW_REPORTS: 'view_reports',
    INVITE_USER: 'invite_user',
    REPORT_ROOM: 'report_room',
    SEND_ROOM_MESSAGE: 'send_room_message',
    SEND_ROOM_IMAGE: 'send_room_image',
    SEND_ROOM_GIFT: 'send_room_gift',
    JOIN_STAGE_DIRECTLY: 'join_stage_directly',
    REQUEST_MIC: 'request_mic',
    RALLY_FANS: 'rally_fans',
    TRANSFER_OWNERSHIP: 'transfer_ownership',
    END_ROOM: 'end_room',
    GET_ROOM_TOKEN: 'get_room_token'
});

const ADMIN_REALTIME_SETTING_KEYS = new Set([
    'hdVoice',
    'banTextChat',
    'banPhotoChat',
    'allowGifts',
    'stageJoinsLocked',
    'requireApproval',
    'maxActiveSpeakers'
]);

const ADMIN_REALTIME_THEME_KEYS = new Set([
    'youtubeUrl',
    'youtubeTitle',
    'youtubeThumbnail',
    'youtubePositionMs',
    'youtubePlaybackState',
    'youtubeQueue'
]);

const idsEqual = (left, right) => {
    if (!left || !right) return false;
    return left.toString() === right.toString();
};

const getParticipant = (room, userId) => {
    if (!room || !userId) return null;
    return room.participants?.find((participant) => idsEqual(participant.userId, userId)) || null;
};

const isRoomParticipant = (room, userId) => Boolean(getParticipant(room, userId));

const isRoomOwner = (room, userId) => idsEqual(room?.hostId, userId);

const isRoomAdmin = (room, userId) => {
    if (!room || !userId) return false;
    if (isRoomOwner(room, userId)) return true;
    if (room.coHosts?.some((id) => idsEqual(id, userId))) return true;
    if (room.moderators?.some((id) => idsEqual(id, userId))) return true;
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
    if (isRoomParticipant(room, userId)) return 1;
    return 0;
};

const canManageTarget = (room, actorUserId, targetUserId) => {
    if (!room || !actorUserId || !targetUserId) return false;
    if (idsEqual(actorUserId, targetUserId)) return false;
    return getAuthorityLevel(room, actorUserId) > getAuthorityLevel(room, targetUserId);
};

const getRoomMode = (room) => {
    const rawMode = String(room?.mode || '').trim().toLowerCase();
    if (Object.values(ROOM_MODES).includes(rawMode)) {
        return rawMode;
    }
    return MODE_BY_ROOM_TYPE[String(room?.type || '').trim().toLowerCase()] || ROOM_MODES.NORMAL;
};

const getPersistedPermissionFlags = (room) => ({
    banTextChat: room?.settings?.banTextChat === true,
    banPhotoChat: room?.settings?.banPhotoChat === true,
    highQualityMode: room?.settings?.hdVoice === true,
    allowGifting: room?.settings?.allowGifts !== false,
    lockStageJoins: room?.settings?.stageJoinsLocked === true,
    allowAdminSeatControl: room?.settings?.allowAdminSeatControl !== false,
    requireMicApproval: room?.settings?.requireApproval === true,
    isPrivate: room?.settings?.isPrivate === true,
    maxActiveSpeakers: getMaxActiveSpeakers(room)
});

const getModePolicyOverrides = (room) => {
    const mode = getRoomMode(room);
    if (mode === ROOM_MODES.ACQUAINT) {
        return {
            banPhotoChat: true,
            requireMicApproval: true
        };
    }
    if (mode === ROOM_MODES.AUCTION) {
        return {
            lockStageJoins: true,
            requireMicApproval: true,
            banPhotoChat: true,
            allowGifting: false
        };
    }
    return {};
};

const getEffectiveRoomPermissions = (room) => ({
    ...getPersistedPermissionFlags(room),
    ...getModePolicyOverrides(room)
});

const getMaxActiveSpeakers = (room) => {
    const rawValue = Number(room?.settings?.maxActiveSpeakers);
    if (!Number.isFinite(rawValue)) return MAX_STAGE_SEATS;
    return Math.max(1, Math.min(MAX_STAGE_SEATS, Math.trunc(rawValue)));
};

const countActiveSpeakers = (room) =>
    room?.participants?.filter((participant) => participant.seatIndex >= 1).length || 0;

const isSeatLocked = (room, seatIndex) => {
    const nextSeatIndex = Number(seatIndex);
    if (!Number.isInteger(nextSeatIndex)) return false;

    const seatState = room?.seatStates?.find((entry) => Number(entry?.seatIndex) === nextSeatIndex);
    if (seatState) {
        return seatState.isLocked === true;
    }

    return room?.lockedSeats?.includes(nextSeatIndex) || false;
};

const findNextAvailableSeat = (room) => {
    const maxSeats = getMaxActiveSpeakers(room);
    for (let seatIndex = 1; seatIndex <= maxSeats; seatIndex += 1) {
        const occupied = room.participants?.some((participant) => participant.seatIndex === seatIndex);
        const locked = isSeatLocked(room, seatIndex);
        if (!occupied && !locked) {
            return seatIndex;
        }
    }

    return null;
};

const getUserRoomCapabilities = (room, userId) => {
    const effectivePermissions = getEffectiveRoomPermissions(room);
    const isOwner = isRoomOwner(room, userId);
    const isAdmin = isRoomAdmin(room, userId);
    const isSpeaker = isRoomSpeaker(room, userId);
    const isParticipant = isRoomParticipant(room, userId);

    return {
        canOpenRoomSettings: isAdmin,
        canManageRoom: isAdmin,
        canManageStage: isAdmin,
        canManageSeats: isAdmin,
        canManageSeatLocks: isOwner || (isAdmin && effectivePermissions.allowAdminSeatControl),
        canManageSafety: isAdmin,
        canManageRoomMedia: isAdmin,
        canManageRoomIdentity: isOwner,
        canManageRoomAccess: isOwner,
        canManageAdmins: isOwner,
        canManageGifting: isAdmin,
        canEditAnnouncement: isAdmin,
        canEndRoom: isOwner,
        canTransferOwnership: isOwner,
        canViewReports: isAdmin,
        canViewBans: isAdmin,
        canInviteUsers: isAdmin,
        canUseRoomGifts: isParticipant && effectivePermissions.allowGifting,
        canSendRoomMessages: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.SEND_ROOM_MESSAGE
        }),
        canSendRoomImages: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.SEND_ROOM_IMAGE
        }),
        canSendRoomGifts: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.SEND_ROOM_GIFT
        }),
        canJoinStageDirectly: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.JOIN_STAGE_DIRECTLY
        }),
        canRequestMic: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.REQUEST_MIC
        }),
        canRallyFans: canPerformRoomAction({
            room,
            actorUserId: userId,
            action: ROOM_ACTIONS.RALLY_FANS
        }),
        canChangeRoomMode: isOwner,
        isOwner,
        isAdmin,
        isSpeaker,
        isParticipant
    };
};

function canPerformRoomAction({
    room,
    actorUserId,
    action,
    targetUserId = null
}) {
    if (!room || !actorUserId || !action) return false;

    const effectivePermissions = getEffectiveRoomPermissions(room);
    const actorParticipant = getParticipant(room, actorUserId);
    const isOwner = isRoomOwner(room, actorUserId);
    const isAdmin = isRoomAdmin(room, actorUserId);
    const isSpeaker = isRoomSpeaker(room, actorUserId);
    const isParticipant = Boolean(actorParticipant);

    switch (action) {
        case ROOM_ACTIONS.UPDATE_ROOM_IDENTITY:
        case ROOM_ACTIONS.UPDATE_ROOM_COVER:
        case ROOM_ACTIONS.UPDATE_ROOM_THEME:
        case ROOM_ACTIONS.UPDATE_ROOM_CONFIG:
        case ROOM_ACTIONS.UPDATE_ROOM_MODE:
        case ROOM_ACTIONS.UPDATE_ROOM_SEATS:
        case ROOM_ACTIONS.TRANSFER_OWNERSHIP:
        case ROOM_ACTIONS.END_ROOM:
            return isOwner;
        case ROOM_ACTIONS.UPDATE_ROOM_ANNOUNCEMENT:
        case ROOM_ACTIONS.UPDATE_ROOM_PERMISSIONS:
            return isAdmin;
        case ROOM_ACTIONS.LOCK_SEAT:
        case ROOM_ACTIONS.UNLOCK_SEAT:
            if (isOwner) return true;
            if (!isAdmin) return false;
            return effectivePermissions.allowAdminSeatControl;
        case ROOM_ACTIONS.MOVE_PARTICIPANT_TO_SEAT:
        case ROOM_ACTIONS.PROMOTE_PARTICIPANT:
        case ROOM_ACTIONS.DEMOTE_PARTICIPANT:
        case ROOM_ACTIONS.MUTE_PARTICIPANT:
        case ROOM_ACTIONS.KICK_PARTICIPANT:
        case ROOM_ACTIONS.BAN_PARTICIPANT:
        case ROOM_ACTIONS.UNBAN_PARTICIPANT:
        case ROOM_ACTIONS.VIEW_BANS:
        case ROOM_ACTIONS.VIEW_REPORTS:
        case ROOM_ACTIONS.INVITE_USER:
        case ROOM_ACTIONS.RALLY_FANS:
            if (!isAdmin) return false;
            return targetUserId ? canManageTarget(room, actorUserId, targetUserId) || action === ROOM_ACTIONS.UNBAN_PARTICIPANT : true;
        case ROOM_ACTIONS.ASSIGN_ADMIN:
        case ROOM_ACTIONS.REMOVE_ADMIN:
        case ROOM_ACTIONS.ASSIGN_COHOST:
        case ROOM_ACTIONS.REMOVE_COHOST:
            return isOwner && (!targetUserId || canManageTarget(room, actorUserId, targetUserId));
        case ROOM_ACTIONS.REPORT_ROOM:
        case ROOM_ACTIONS.GET_ROOM_TOKEN:
            return isParticipant;
        case ROOM_ACTIONS.SEND_ROOM_MESSAGE:
            if (!isParticipant) return false;
            if (effectivePermissions.banTextChat && !isAdmin) return false;
            if (getRoomMode(room) === ROOM_MODES.AUCTION && !isAdmin && !isSpeaker) {
                return false;
            }
            return true;
        case ROOM_ACTIONS.SEND_ROOM_IMAGE:
            if (!isParticipant) return false;
            if (!canPerformRoomAction({
                room,
                actorUserId,
                action: ROOM_ACTIONS.SEND_ROOM_MESSAGE
            })) {
                return false;
            }
            return !effectivePermissions.banPhotoChat || isAdmin;
        case ROOM_ACTIONS.SEND_ROOM_GIFT:
            if (!isParticipant) return false;
            return effectivePermissions.allowGifting;
        case ROOM_ACTIONS.JOIN_STAGE_DIRECTLY:
            if (!isParticipant) return false;
            if (isAdmin) return true;
            return !effectivePermissions.lockStageJoins && !effectivePermissions.requireMicApproval;
        case ROOM_ACTIONS.REQUEST_MIC:
            if (!isParticipant) return false;
            return !isAdmin && !isSpeaker;
        default:
            return false;
    }
}

const assertRoomPermission = (params, message = 'Not authorized for this room action') => {
    if (!canPerformRoomAction(params)) {
        const error = new Error(message);
        error.status = 403;
        throw error;
    }
};

const canManageRoomIdentity = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.UPDATE_ROOM_IDENTITY });

const canManageRoomAccess = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.UPDATE_ROOM_CONFIG });

const canManageStage = (room, userId) => isRoomAdmin(room, userId);
const canManageSeatLocks = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.LOCK_SEAT });

const canManageRealtimeSafety = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.UPDATE_ROOM_PERMISSIONS });

const canManageRoomMedia = (room, userId) => isRoomAdmin(room, userId);
const canManageGifting = (room, userId) => isRoomAdmin(room, userId);
const canManageAdmins = (room, userId) => isRoomOwner(room, userId);
const canEditAnnouncement = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.UPDATE_ROOM_ANNOUNCEMENT });
const canTransferOwnership = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.TRANSFER_OWNERSHIP });
const canViewReports = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.VIEW_REPORTS });
const canEndRoom = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.END_ROOM });
const canJoinStageDirectly = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.JOIN_STAGE_DIRECTLY });
const canUseRoomGifts = (room, userId) =>
    canPerformRoomAction({ room, actorUserId: userId, action: ROOM_ACTIONS.SEND_ROOM_GIFT });

const sanitizeRoomUpdatePayload = (room, userId, payload = {}) => {
    if (!room || !userId || !payload || typeof payload !== 'object') return null;
    const providedFields = Object.keys(payload).filter((field) => payload[field] !== undefined);
    if (providedFields.length === 0) return null;

    if (canManageRoomIdentity(room, userId)) {
        return payload;
    }

    if (!isRoomAdmin(room, userId)) {
        return null;
    }

    const sanitized = {};
    for (const field of providedFields) {
        if (field === 'announcement') {
            sanitized.announcement = payload.announcement;
            continue;
        }
        if (field === 'settings' && payload.settings && typeof payload.settings === 'object') {
            const allowedSettings = Object.fromEntries(
                Object.entries(payload.settings).filter(([key]) => ADMIN_REALTIME_SETTING_KEYS.has(key))
            );
            if (Object.keys(allowedSettings).length > 0) {
                sanitized.settings = allowedSettings;
            }
            continue;
        }
        if (field === 'theme' && payload.theme && typeof payload.theme === 'object') {
            const allowedTheme = Object.fromEntries(
                Object.entries(payload.theme).filter(([key]) => ADMIN_REALTIME_THEME_KEYS.has(key))
            );
            if (Object.keys(allowedTheme).length > 0) {
                sanitized.theme = allowedTheme;
            }
            continue;
        }
    }

    return Object.keys(sanitized).length > 0 ? sanitized : null;
};

module.exports = {
    ADMIN_REALTIME_SETTING_KEYS,
    ADMIN_REALTIME_THEME_KEYS,
    MAX_STAGE_SEATS,
    ROOM_ACTIONS,
    ROOM_MODES,
    assertRoomPermission,
    canEditAnnouncement,
    canEndRoom,
    canJoinStageDirectly,
    canManageAdmins,
    canManageGifting,
    canManageRealtimeSafety,
    canManageRoomAccess,
    canManageRoomIdentity,
    canManageRoomMedia,
    canManageStage,
    canManageSeatLocks,
    canManageTarget,
    canPerformRoomAction,
    canTransferOwnership,
    canUseRoomGifts,
    canViewReports,
    countActiveSpeakers,
    findNextAvailableSeat,
    getAuthorityLevel,
    getEffectiveRoomPermissions,
    getMaxActiveSpeakers,
    getParticipant,
    getRoomMode,
    getUserRoomCapabilities,
    idsEqual,
    isSeatLocked,
    isRoomAdmin,
    isRoomOwner,
    isRoomParticipant,
    isRoomSpeaker,
    sanitizeRoomUpdatePayload
};
