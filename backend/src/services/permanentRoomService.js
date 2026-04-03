const Room = require('../models/Room');
const User = require('../models/User');
const { recalculateRoomPresenceState } = require('./roomPresenceService');

const MAX_ARCHIVED_LEGACY_ROOMS = 32;
const STREAM_ROOM_TYPE = 'video';
const STREAM_HOST_SEAT_INDEX = 1;

const idsEqual = (left, right) => {
    if (!left || !right) return false;
    return left.toString() === right.toString();
};

const inferModeForType = (type = 'voice') => {
    if (type === 'auction') return 'auction';
    if (type === 'chat') return 'acquaint';
    return 'normal';
};

const inferBackgroundForType = (type = 'voice') => {
    if (type === 'video') return 'cinema';
    if (type === 'music') return 'pulse';
    if (type === 'game') return 'arcade';
    return 'midnight';
};

const buildAnnouncementState = (announcement, actorUserId, fallback = null) => {
    const text = String(announcement || '').trim();
    if (!text) {
        return fallback;
    }

    return {
        text,
        updatedAt: new Date(),
        updatedBy: actorUserId
    };
};

const getPrimaryLegacyRoomCandidates = async (userId) => Room.find({
    groupId: { $exists: false },
    hostId: userId
})
    .sort({ endedAt: 1, updatedAt: -1, createdAt: 1, participantCount: -1 })
    .limit(MAX_ARCHIVED_LEGACY_ROOMS);

const applyPermanentRoomDefaults = (room, user, payload = {}, { onlyIfBlank = false } = {}) => {
    const theme = payload.theme && typeof payload.theme === 'object' ? payload.theme : {};
    const settings = payload.settings && typeof payload.settings === 'object'
        ? payload.settings
        : {};

    const initialType = String(payload.type || room.type || 'voice').trim() || 'voice';
    const initialMode = String(payload.mode || room.mode || inferModeForType(initialType)).trim() || inferModeForType(initialType);
    const initialCategory = String(payload.category || room.category || 'all').trim() || 'all';
    const nextName = String(payload.name || room.name || 'New Room').trim();
    const nextDescription = String(
        payload.description !== undefined
            ? payload.description
            : room.description || `Welcome to ${user.username}'s room.`
    ).trim();
    const nextTopic = String(
        payload.topic !== undefined ? payload.topic : room.topic || ''
    ).trim();
    const nextLanguage = String(
        payload.language !== undefined
            ? payload.language
            : room.language || user.settings?.language || 'en'
    ).trim() || 'en';
    const nextRegion = String(
        payload.region !== undefined ? payload.region : room.region || user.region || 'Global'
    ).trim() || 'Global';
    const nextRules = String(
        payload.roomRules !== undefined ? payload.roomRules : room.roomRules || ''
    ).trim();
    const nextTags = Array.isArray(payload.tags) && payload.tags.length > 0
        ? payload.tags
        : Array.isArray(room.tags)
            ? room.tags
            : [];

    if (!onlyIfBlank || !room.name) {
        room.name = nextName || 'New Room';
    }
    if (!onlyIfBlank || !room.description) {
        room.description = nextDescription;
    }
    if (!onlyIfBlank || !room.topic) {
        room.topic = nextTopic;
    }
    if (!onlyIfBlank || !room.language) {
        room.language = nextLanguage;
    }
    if (!onlyIfBlank || !room.region) {
        room.region = nextRegion;
    }
    if (!onlyIfBlank || !room.roomRules) {
        room.roomRules = nextRules;
    }
    if (!onlyIfBlank || !Array.isArray(room.tags) || room.tags.length === 0) {
        room.tags = nextTags;
    }

    room.type = initialType;
    room.mode = initialMode;
    room.category = initialCategory;
    room.ownerId = user._id;
    room.isPermanent = true;
    room.archivedAt = null;
    room.endedAt = null;
    room.showInExplore = payload.showInExplore ?? room.showInExplore ?? true;

    room.settings = {
        ...(room.settings?.toObject?.() || room.settings || {}),
        isPrivate: settings.isPrivate ?? room.settings?.isPrivate ?? false,
        password: settings.password ?? room.settings?.password,
        maxParticipants: settings.maxParticipants ?? room.settings?.maxParticipants ?? 20,
        entryFee: settings.entryFee ?? room.settings?.entryFee ?? 0,
        hdVoice: settings.hdVoice ?? room.settings?.hdVoice ?? false,
        banTextChat: settings.banTextChat ?? room.settings?.banTextChat ?? false,
        banPhotoChat: settings.banPhotoChat ?? room.settings?.banPhotoChat ?? false,
        banRedPacket: settings.banRedPacket ?? room.settings?.banRedPacket ?? false,
        allowGifts: settings.allowGifts ?? room.settings?.allowGifts ?? true,
        allowScreenShare: settings.allowScreenShare ?? room.settings?.allowScreenShare ?? false,
        allowVideo: settings.allowVideo ?? room.settings?.allowVideo ?? (initialType === 'video'),
        stageJoinsLocked: settings.stageJoinsLocked ?? room.settings?.stageJoinsLocked ?? false,
        allowAdminSeatControl: settings.allowAdminSeatControl ?? room.settings?.allowAdminSeatControl ?? true,
        maxActiveSpeakers: settings.maxActiveSpeakers ?? room.settings?.maxActiveSpeakers ?? 8,
        requireApproval: settings.requireApproval ?? room.settings?.requireApproval ?? false,
        slowMode: settings.slowMode ?? room.settings?.slowMode ?? 0,
        ageRestricted: settings.ageRestricted ?? room.settings?.ageRestricted ?? false
    };

    room.theme = {
        ...(room.theme?.toObject?.() || room.theme || {}),
        background: theme.background || room.theme?.background || inferBackgroundForType(initialType),
        coverImage: theme.coverImage || room.theme?.coverImage || ''
    };

    const nextAnnouncement = buildAnnouncementState(
        payload.announcement,
        user._id,
        room.announcement
    );
    if (nextAnnouncement) {
        room.announcement = nextAnnouncement;
    }

    if (!Array.isArray(room.participants) || room.participants.length === 0) {
        room.participants = [{
            userId: user._id,
            role: 'host',
            seatIndex: initialType === STREAM_ROOM_TYPE ? STREAM_HOST_SEAT_INDEX : -1,
            joinedAt: new Date(),
            lastActive: new Date()
        }];
    }
};

const createPermanentRoomDocument = async ({ user, payload = {} }) => {
    const room = new Room({
        hostId: user._id,
        ownerId: user._id,
        isPermanent: true,
        participants: [{
            userId: user._id,
            role: 'host',
            seatIndex: payload.type === STREAM_ROOM_TYPE ? STREAM_HOST_SEAT_INDEX : -1,
            joinedAt: new Date(),
            lastActive: new Date()
        }]
    });

    applyPermanentRoomDefaults(room, user, payload);
    recalculateRoomPresenceState(room);
    await room.save();
    return room;
};

const linkUserToPermanentRoom = async (user, roomId) => {
    user.permanentRoomId = roomId;
    user.hasPermanentRoom = true;
    await user.save();
};

const archiveSecondaryLegacyRooms = async (userId, primaryRoomId) => {
    const archivedAt = new Date();
    const result = await Room.updateMany(
        {
            groupId: { $exists: false },
            hostId: userId,
            _id: { $ne: primaryRoomId },
            endedAt: null
        },
        {
            $set: {
                endedAt: archivedAt,
                archivedAt,
                showInExplore: false,
                isPermanent: false
            },
            $unset: {
                ownerId: 1
            }
        }
    );

    return result.modifiedCount || 0;
};

const resolveExistingPermanentRoom = async (user) => {
    if (user.permanentRoomId) {
        const linked = await Room.findById(user.permanentRoomId);
        if (linked) {
            recalculateRoomPresenceState(linked);
            if (!idsEqual(linked.ownerId, user._id)) {
                linked.ownerId = user._id;
                linked.isPermanent = true;
            }
            if (linked.endedAt) {
                linked.endedAt = null;
            }
            if (linked.isModified()) {
                await linked.save();
            }
            return { room: linked, migrated: false, archivedLegacyRoomCount: 0 };
        }
    }

    const explicitPermanent = await Room.findOne({
        ownerId: user._id,
        isPermanent: true
    }).sort({ updatedAt: -1, createdAt: 1 });

    if (explicitPermanent) {
        recalculateRoomPresenceState(explicitPermanent);
        if (explicitPermanent.endedAt) {
            explicitPermanent.endedAt = null;
            await explicitPermanent.save();
        }
        await linkUserToPermanentRoom(user, explicitPermanent._id);
        return { room: explicitPermanent, migrated: false, archivedLegacyRoomCount: 0 };
    }

    const legacyCandidates = await getPrimaryLegacyRoomCandidates(user._id);
    const primaryLegacyRoom = legacyCandidates[0];
    if (!primaryLegacyRoom) {
        return { room: null, migrated: false, archivedLegacyRoomCount: 0 };
    }

    primaryLegacyRoom.ownerId = user._id;
    primaryLegacyRoom.isPermanent = true;
    primaryLegacyRoom.archivedAt = null;
    primaryLegacyRoom.showInExplore = true;
    applyPermanentRoomDefaults(primaryLegacyRoom, user, {}, { onlyIfBlank: true });
    recalculateRoomPresenceState(primaryLegacyRoom);
    await primaryLegacyRoom.save();
    await linkUserToPermanentRoom(user, primaryLegacyRoom._id);
    const archivedLegacyRoomCount =
        await archiveSecondaryLegacyRooms(user._id, primaryLegacyRoom._id);

    return {
        room: primaryLegacyRoom,
        migrated: true,
        archivedLegacyRoomCount
    };
};

const ensureUserPermanentRoom = async (userId, payload = {}) => {
    const user = await User.findById(userId);
    if (!user) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }

    const existing = await resolveExistingPermanentRoom(user);
    if (existing.room) {
        return {
            room: existing.room,
            created: false,
            migrated: existing.migrated,
            archivedLegacyRoomCount: existing.archivedLegacyRoomCount
        };
    }

    try {
        const room = await createPermanentRoomDocument({ user, payload });
        await linkUserToPermanentRoom(user, room._id);
        return {
            room,
            created: true,
            migrated: false,
            archivedLegacyRoomCount: 0
        };
    } catch (error) {
        if (error?.code !== 11000) {
            throw error;
        }

        const duplicateRoom = await Room.findOne({
            ownerId: user._id,
            isPermanent: true
        }).sort({ updatedAt: -1 });
        if (!duplicateRoom) {
            throw error;
        }
        await linkUserToPermanentRoom(user, duplicateRoom._id);
        return {
            room: duplicateRoom,
            created: false,
            migrated: false,
            archivedLegacyRoomCount: 0
        };
    }
};

const getUserPermanentRoom = async (userId, { allocateIfMissing = false } = {}) => {
    const user = await User.findById(userId);
    if (!user) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }

    const existing = await resolveExistingPermanentRoom(user);
    if (existing.room) {
        return existing;
    }

    if (!allocateIfMissing) {
        return {
            room: null,
            created: false,
            migrated: false,
            archivedLegacyRoomCount: 0
        };
    }

    return ensureUserPermanentRoom(userId);
};

const transferPermanentRoomOwnership = async ({ room, nextOwnerId, previousOwnerId }) => {
    if (!room) return;

    if (room.isPermanent) {
        const conflictingPermanentRoom = await Room.findOne({
            ownerId: nextOwnerId,
            isPermanent: true,
            _id: { $ne: room._id }
        }).select('_id');
        if (conflictingPermanentRoom) {
            const error = new Error('That user already owns a permanent room');
            error.status = 409;
            throw error;
        }
        room.ownerId = nextOwnerId;
        room.endedAt = null;
    }

    await room.save();

    if (!room.isPermanent) {
        return;
    }

    await User.findByIdAndUpdate(previousOwnerId, {
        $unset: { permanentRoomId: 1 },
        $set: { hasPermanentRoom: false }
    });
    await User.findByIdAndUpdate(nextOwnerId, {
        $set: { permanentRoomId: room._id, hasPermanentRoom: true }
    });
};

module.exports = {
    applyPermanentRoomDefaults,
    ensureUserPermanentRoom,
    getUserPermanentRoom,
    transferPermanentRoomOwnership
};
