const Room = require('../models/Room');
const {
    MAX_STAGE_SEATS,
    getUserMiniDrawCapabilities,
    ROOM_MODES,
    getEffectiveRoomPermissions,
    getParticipant,
    getRoomMode,
    getUserRoomCapabilities
} = require('./roomPermissionService');
const { buildMiniDrawSummary } = require('./miniDrawService');
const {
    getLockedSeatCount,
    getSeatStateSnapshot
} = require('./roomSeatService');

const ROOM_UPDATE_EVENTS = Object.freeze({
    IDENTITY: 'room:update_identity',
    PERMISSIONS: 'room:update_permissions',
    SETTINGS: 'room:update_settings',
    SEATS: 'room:update_seats',
    ROLES: 'room:update_roles',
    MODE: 'room:update_mode',
    THEME: 'room:update_theme'
});

const populateRoomById = async (roomId) => Room.findById(roomId)
    .populate('ownerId', 'username avatar level vipLevel shopProfile')
    .populate('hostId', 'username avatar level vipLevel shopProfile')
    .populate('coHosts', 'username avatar level vipLevel shopProfile')
    .populate('moderators', 'username avatar level vipLevel shopProfile')
    .populate('participants.userId', 'username avatar level vipLevel shopProfile status.isOnline')
    .populate('bans.userId', 'username avatar')
    .populate('reports.userId', 'username avatar');

const resolveAnnouncementText = (room) => {
    if (room?.announcement && typeof room.announcement === 'object') {
        return String(room.announcement.text || '').trim();
    }
    return String(room?.announcement || '').trim();
};

const buildSeatSnapshot = (room) => {
    const seatStates = getSeatStateSnapshot(room);
    const activeSpeakers = (room?.participants || [])
        .filter((participant) => participant.seatIndex >= 1)
        .map((participant) => ({
            userId: participant.userId?._id?.toString() || participant.userId?.toString() || '',
            username: participant.userId?.username || participant.username || 'User',
            avatar: participant.userId?.avatar || participant.avatar || '',
            role: participant.role || 'listener',
            seatIndex: participant.seatIndex
        }))
        .sort((left, right) => left.seatIndex - right.seatIndex);

    return {
        totalSeats: MAX_STAGE_SEATS,
        lockedSeats: seatStates.filter((seat) => seat.isLocked).map((seat) => seat.seatIndex),
        lockedSeatCount: getLockedSeatCount(room),
        items: seatStates,
        activeSpeakers
    };
};

const buildModerationSnapshot = (room, viewerUserId, capabilities) => ({
    bannedUsers: capabilities.canViewBans ? (room?.bans || []) : [],
    reports: capabilities.canViewReports ? (room?.reports || []) : [],
    viewerCanViewModeration: capabilities.canViewBans || capabilities.canViewReports
});

const buildRoomSettingsSnapshot = (room, viewerUserId = null) => {
    const effectivePermissions = getEffectiveRoomPermissions(room);
    const capabilities = getUserRoomCapabilities(room, viewerUserId);

    return {
        identity: {
            title: room?.name || '',
            announcement: resolveAnnouncementText(room),
            coverImage: room?.theme?.coverImage || '',
            topic: room?.topic || ''
        },
        permissions: {
            banTextChat: effectivePermissions.banTextChat,
            banPhotoChat: effectivePermissions.banPhotoChat,
            banRedPacket: effectivePermissions.banRedPacket,
            highQualityMode: effectivePermissions.highQualityMode,
            allowGifting: effectivePermissions.allowGifting,
            lockStageJoins: effectivePermissions.lockStageJoins,
            allowAdminSeatControl: effectivePermissions.allowAdminSeatControl,
            requireMicApproval: effectivePermissions.requireMicApproval
        },
        roomConfig: {
            isPrivate: effectivePermissions.isPrivate,
            category: room?.category || 'all',
            roomMode: getRoomMode(room),
            language: room?.language || 'en',
            region: room?.region || 'Global',
            roomRules: room?.roomRules || '',
            isPermanent: room?.isPermanent === true
        },
        moderation: buildModerationSnapshot(room, viewerUserId, capabilities),
        controllerState: {
            hostPresent: room?.hostPresent === true,
            adminCount: Number(room?.adminCount || 0),
            activeControllersCount: Number(room?.activeControllersCount || 0),
            roomActive: room?.roomActive !== false,
            inactiveSince: room?.inactiveSince
                ? new Date(room.inactiveSince).toISOString()
                : null
        },
        seats: buildSeatSnapshot(room),
        atmosphere: {
            backgroundTheme: room?.theme?.background || 'default'
        },
        miniDraw: {
            ...buildMiniDrawSummary(room, viewerUserId),
            permissions: getUserMiniDrawCapabilities(room, viewerUserId)
        }
    };
};

const decorateRoomPayload = (room, viewerUserId = null, options = {}) => {
    if (!room) return null;
    const {
        includeCapabilities = true,
        includeModeration = viewerUserId != null
    } = options;

    const source = typeof room.toObject === 'function'
        ? room.toObject({ virtuals: false })
        : { ...room };
    const capabilities = getUserRoomCapabilities(room, viewerUserId);
    const roomSettings = buildRoomSettingsSnapshot(room, viewerUserId);

    source.mode = getRoomMode(room);
    source.announcement = resolveAnnouncementText(room);
    source.ownerId = room?.ownerId?._id?.toString?.() || room?.ownerId?.toString?.() || source.ownerId;
    source.isPermanent = room?.isPermanent === true;
    source.hostPresent = room?.hostPresent === true;
    source.adminCount = Number(room?.adminCount || 0);
    source.activeControllersCount = Number(room?.activeControllersCount || 0);
    source.roomActive = room?.roomActive !== false;
    source.inactiveSince = room?.inactiveSince || null;
    source.theme = {
        ...(source.theme || {}),
        background: roomSettings.atmosphere.backgroundTheme,
        coverImage: roomSettings.identity.coverImage
    };
    source.settings = {
        ...(source.settings || {}),
        hdVoice: roomSettings.permissions.highQualityMode,
        banTextChat: roomSettings.permissions.banTextChat,
        banPhotoChat: roomSettings.permissions.banPhotoChat,
        banRedPacket: roomSettings.permissions.banRedPacket,
        allowGifts: roomSettings.permissions.allowGifting,
        stageJoinsLocked: roomSettings.permissions.lockStageJoins,
        allowAdminSeatControl: roomSettings.permissions.allowAdminSeatControl,
        requireApproval: roomSettings.permissions.requireMicApproval
    };
    source.participantCount = Array.isArray(source.participants)
        ? source.participants.length
        : Number(source.participantCount || 0);
    source.lockedSeats = roomSettings.seats.lockedSeats;
    source.seatStates = roomSettings.seats.items;
    source.roomSettings = roomSettings;
    source.miniDraw = roomSettings.miniDraw;

    if (includeCapabilities) {
        source.capabilities = capabilities;
    }

    if (!includeModeration || !roomSettings.moderation.viewerCanViewModeration) {
        delete source.bans;
        delete source.reports;
        source.roomSettings = {
            ...roomSettings,
            moderation: {
                bannedUsers: [],
                reports: [],
                viewerCanViewModeration: false
            }
        };
    }

    return source;
};

const emitRoomUpdate = (io, room, {
    updateEvent = ROOM_UPDATE_EVENTS.SETTINGS,
    lobbyAction = 'updated',
    extraPayload = null
} = {}) => {
    if (!io || !room) return;
    const publicPayload = decorateRoomPayload(room, null, {
        includeCapabilities: false,
        includeModeration: false
    });
    const roomId = publicPayload?._id?.toString() || publicPayload?.id?.toString();
    if (!roomId) return;

    io.to(`room:${roomId}`).emit('room:updated', publicPayload);
    io.to(`room:${roomId}`).emit(updateEvent, {
        roomId,
        room: publicPayload,
        roomSettings: publicPayload.roomSettings,
        mode: publicPayload.mode,
        ...(extraPayload || {}),
        updatedAt: new Date().toISOString()
    });
    if (updateEvent === ROOM_UPDATE_EVENTS.SEATS) {
        io.to(`room:${roomId}`).emit('room:seats_updated', {
            roomId,
            room: publicPayload,
            roomSettings: publicPayload.roomSettings,
            ...(extraPayload || {}),
            updatedAt: new Date().toISOString()
        });
    }
    io.emit('room:lobby:update', {
        roomId,
        action: lobbyAction,
        name: publicPayload.name,
        category: publicPayload.category,
        type: publicPayload.type,
        mode: publicPayload.mode,
        hostAvatar: publicPayload.hostId?.avatar || publicPayload.hostAvatar || '',
        coverImage: publicPayload.theme?.coverImage || publicPayload.coverImage || '',
        participantCount: publicPayload.participantCount ?? publicPayload.participants?.length ?? 0,
        onlineCount: publicPayload.onlineCount ?? 0,
        roomActive: publicPayload.roomActive !== false,
        activeControllersCount: publicPayload.activeControllersCount ?? 0,
        endedAt: publicPayload.endedAt || null,
        updatedAt: new Date().toISOString()
    });
};

const canonicalTypeForMode = (mode, currentType = 'voice') => {
    if (mode === ROOM_MODES.AUCTION) return 'auction';
    if (mode === ROOM_MODES.ACQUAINT) return 'chat';
    if (mode === ROOM_MODES.NORMAL) {
        return currentType === 'auction' || currentType === 'chat' ? 'voice' : currentType;
    }
    return currentType;
};

const applyRoomMode = (room, nextMode) => {
    if (!room || !nextMode) return;
    room.mode = nextMode;
    room.type = canonicalTypeForMode(nextMode, room.type);
};

module.exports = {
    ROOM_UPDATE_EVENTS,
    applyRoomMode,
    buildRoomSettingsSnapshot,
    canonicalTypeForMode,
    decorateRoomPayload,
    emitRoomUpdate,
    getParticipant,
    populateRoomById,
    resolveAnnouncementText
};
