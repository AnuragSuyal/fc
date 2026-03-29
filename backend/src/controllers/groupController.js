const mongoose = require('mongoose');

const Group = require('../models/Group');
const Room = require('../models/Room');
const User = require('../models/User');

const GROUP_USER_SELECT =
    'username avatar level uid vipLevel status.isOnline status.lastActive';
const GROUP_ROOM_SELECT =
    'name roomId type onlineCount participantCount theme.coverImage settings.maxParticipants settings.allowGifts';

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'object' && value._id) return value._id.toString();
    return value.toString();
};

const uniqueIds = (values = []) => {
    const seen = new Set();
    const ids = [];

    for (const value of values) {
        const id = toIdString(value);
        if (!id || seen.has(id)) continue;
        seen.add(id);
        ids.push(id);
    }

    return ids;
};

const isValidObjectId = (value) => mongoose.Types.ObjectId.isValid(value);

const getMemberRecord = (group, userId) =>
    (group.members || []).find((member) => toIdString(member.userId) === userId);

const isGroupLeader = (group, userId) => toIdString(group.leaderId) === userId;

const isGroupAdmin = (group, userId) => {
    if (isGroupLeader(group, userId)) return true;
    const adminIds = new Set(
        (group.admins || []).map((adminId) => toIdString(adminId)).filter(Boolean)
    );
    const member = getMemberRecord(group, userId);
    return adminIds.has(userId) || member?.role === 'admin';
};

const syncAdminsFromMembers = (group) => {
    group.admins = (group.members || [])
        .filter((member) => member.role === 'admin')
        .map((member) => member.userId);
};

const normalizeUser = (user) => {
    if (!user) return null;

    if (typeof user === 'string') {
        return { _id: user };
    }

    const source = typeof user.toObject === 'function' ? user.toObject() : user;
    const status = source.status && typeof source.status === 'object'
        ? {
            isOnline: source.status.isOnline === true,
            lastActive: source.status.lastActive || null
        }
        : null;

    return {
        _id: source._id?.toString() || source.id?.toString() || '',
        id: source._id?.toString() || source.id?.toString() || '',
        username: source.username || 'Unknown',
        avatar: source.avatar || '',
        level: Number(source.level || 1),
        vipLevel: Number(source.vipLevel || 0),
        uid: source.uid || '',
        status
    };
};

const normalizeMember = (member) => {
    const user = normalizeUser(member?.userId);
    return {
        userId: user,
        role: member?.role || 'member',
        joinedAt: member?.joinedAt || null
    };
};

const normalizeInvite = (invite) => ({
    userId: normalizeUser(invite?.userId),
    invitedBy: normalizeUser(invite?.invitedBy),
    status: invite?.status || 'pending',
    invitedAt: invite?.invitedAt || null,
    respondedAt: invite?.respondedAt || null
});

const normalizeJoinRequest = (request) => ({
    userId: normalizeUser(request?.userId),
    message: request?.message || '',
    requestedAt: request?.requestedAt || null
});

const normalizeVoiceRoom = (room) => {
    if (!room) return null;
    const source = typeof room.toObject === 'function' ? room.toObject() : room;
    const id = source._id?.toString() || source.id?.toString();
    if (!id) return null;

    return {
        _id: id,
        id,
        roomId: source.roomId?.toString() || '',
        name: source.name || 'Voice Lounge',
        type: source.type || 'voice',
        participantCount: Number(source.participantCount || 0),
        onlineCount: Number(source.onlineCount || 0),
        coverImage: source.theme?.coverImage || source.coverImage || '',
        settings: source.settings || {}
    };
};

const buildGroupBroadcast = (group) => {
    const source = typeof group.toObject === 'function' ? group.toObject() : group;
    const members = (source.members || []).map(normalizeMember);
    const onlineMembers = members.filter(
        (member) => member.userId?.status?.isOnline === true
    ).length;

    return {
        _id: source._id?.toString() || '',
        id: source._id?.toString() || '',
        name: source.name || '',
        tag: source.tag || '',
        description: source.description || '',
        motto: source.motto || '',
        vibe: source.vibe || 'Orbit',
        announcement: source.announcement || '',
        avatar: source.avatar || '',
        coverImage: source.coverImage || '',
        leaderId: normalizeUser(source.leaderId),
        memberCount: Number(source.memberCount || members.length),
        maxMembers: Number(source.maxMembers || 50),
        type: source.type || 'small',
        isPublic: source.isPublic !== false,
        approvalRequired: source.approvalRequired === true,
        hasTreasure: source.treasureChest?.available === true,
        stats: source.stats || {},
        coins: Number(source.coins || 0),
        store: Array.isArray(source.store) ? source.store : [],
        onlineMembers,
        linkedVoiceRoom: normalizeVoiceRoom(source.linkedRoomId),
        createdAt: source.createdAt || null,
        lastActivityAt: source.lastActivityAt || source.updatedAt || source.createdAt,
        updatedAt: source.updatedAt || source.createdAt
    };
};

const buildGroupForViewer = (group, viewerId) => {
    const source = typeof group.toObject === 'function' ? group.toObject() : group;
    const normalizedLeader = normalizeUser(source.leaderId);
    const normalizedMembers = (source.members || []).map(normalizeMember);
    const normalizedAdmins = (source.admins || [])
        .map(normalizeUser)
        .filter(Boolean);

    const viewerMember = normalizedMembers.find(
        (member) => member.userId?._id === viewerId
    );
    const viewerInvite = (source.invitations || []).find(
        (invite) =>
            toIdString(invite.userId) === viewerId &&
            invite.status === 'pending'
    );
    const viewerJoinRequest = (source.joinRequests || []).find(
        (request) => toIdString(request.userId) === viewerId
    );

    const viewerRole = viewerMember?.role ||
        (normalizedLeader?._id === viewerId ? 'leader' : 'guest');
    const isLeader = viewerRole === 'leader';
    const isAdmin = isLeader || viewerRole === 'admin';
    const isMember = viewerRole !== 'guest';

    const visibleInvites = isAdmin
        ? (source.invitations || []).map(normalizeInvite)
        : viewerInvite
            ? [normalizeInvite(viewerInvite)]
            : [];

    const visibleJoinRequests = isAdmin
        ? (source.joinRequests || []).map(normalizeJoinRequest)
        : viewerJoinRequest
            ? [normalizeJoinRequest(viewerJoinRequest)]
            : [];

    return {
        ...buildGroupBroadcast(source),
        leaderId: normalizedLeader,
        admins: normalizedAdmins,
        members: normalizedMembers,
        invitations: visibleInvites,
        joinRequests: visibleJoinRequests,
        isMember,
        isInvited: !!viewerInvite,
        hasPendingJoinRequest: !!viewerJoinRequest,
        viewerRole,
        permissions: {
            isLeader,
            isAdmin,
            canInviteFriends: isAdmin,
            canApproveRequests: isAdmin,
            canManageMembers: isAdmin,
            canPromoteAdmins: isLeader,
            canKickMembers: isAdmin,
            canEditGroup: isAdmin,
            canDeleteGroup: isLeader,
            canClaimTreasure: isMember,
            canOpenVoice: isMember
        }
    };
};

const populateGroupQuery = (query) =>
    query
        .populate('leaderId', GROUP_USER_SELECT)
        .populate('admins', GROUP_USER_SELECT)
        .populate('members.userId', GROUP_USER_SELECT)
        .populate('invitations.userId', GROUP_USER_SELECT)
        .populate('invitations.invitedBy', 'username avatar uid')
        .populate('joinRequests.userId', GROUP_USER_SELECT)
        .populate('linkedRoomId', GROUP_ROOM_SELECT);

const loadGroup = async (groupId) => populateGroupQuery(Group.findById(groupId));

const createLinkedVoiceRoom = async ({
    group,
    ownerId,
    maxMembers
}) => {
    const room = new Room({
        name: `${group.name} Lounge`,
        description: group.description || `Voice lounge for ${group.name}`,
        type: 'voice',
        category: 'voice',
        tags: ['group', group.type || 'small'],
        hostId: ownerId,
        groupId: group._id,
        showInExplore: false,
        settings: {
            isPrivate: false,
            maxParticipants: Math.max(10, Math.min(Number(maxMembers || 20), 1000)),
            entryFee: 0,
            hdVoice: true,
            banTextChat: false,
            banPhotoChat: false,
            banRedPacket: false,
            allowGifts: true,
            allowScreenShare: false,
            allowVideo: false,
            stageJoinsLocked: false,
            maxActiveSpeakers: 8,
            requireApproval: false,
            slowMode: 0,
            ageRestricted: false
        },
        theme: {
            background: 'default'
        },
        participants: [{
            userId: ownerId,
            role: 'host',
            joinedAt: Date.now(),
            lastActive: Date.now()
        }]
    });

    await room.save();
    return room;
};

const emitGroupEvent = async (req, groupId, action, extra = {}) => {
    const io = req.app.get('io');
    if (!io) return;

    const group = await loadGroup(groupId);
    if (!group) return;

    const userIds = new Set([
        ...(group.members || []).map((member) => toIdString(member.userId)),
        ...(group.invitations || [])
            .filter((invite) => invite.status === 'pending')
            .map((invite) => toIdString(invite.userId)),
        ...(extra.targetUserIds || []).map((id) => toIdString(id))
    ]);

    userIds.delete('');

    const payload = {
        action,
        groupId: group._id.toString(),
        group: buildGroupBroadcast(group),
        actorId: extra.actorId ? toIdString(extra.actorId) : null,
        memberUserId: extra.memberUserId ? toIdString(extra.memberUserId) : null,
        role: extra.role || null,
        note: extra.note || null,
        updatedAt: new Date().toISOString()
    };

    io.to(`group:${group._id}`).emit('group:updated', payload);
    for (const userId of userIds) {
        io.to(`user:${userId}`).emit('group:updated', payload);
    }
};

const ensureManageAccess = (group, userId) => {
    if (!isGroupAdmin(group, userId)) {
        const error = new Error('Only the owner and group admins can do that');
        error.status = 403;
        throw error;
    }
};

const ensureOwnerAccess = (group, userId) => {
    if (!isGroupLeader(group, userId)) {
        const error = new Error('Only the group owner can do that');
        error.status = 403;
        throw error;
    }
};

const attachMember = (group, userId, role = 'member') => {
    group.members.push({
        userId,
        role,
        joinedAt: new Date()
    });
    syncAdminsFromMembers(group);
    group.lastActivityAt = new Date();
};

const removeMemberFromGroup = (group, userId) => {
    group.members = (group.members || []).filter(
        (member) => toIdString(member.userId) !== userId
    );
    group.admins = (group.admins || []).filter(
        (adminId) => toIdString(adminId) !== userId
    );
    group.lastActivityAt = new Date();
};

const removeUserFromLinkedRoom = async (group, userId) => {
    if (!group.linkedRoomId) return;

    const room = await Room.findById(group.linkedRoomId);
    if (!room) return;

    room.participants = (room.participants || []).filter(
        (participant) => toIdString(participant.userId) !== userId
    );
    await room.save();
};

async function createGroup(req, res, next) {
    try {
        const {
            name,
            description,
            motto,
            avatar,
            isPublic,
            maxMembers,
            approvalRequired,
            type,
            vibe,
            invitedFriendIds = []
        } = req.body;

        const owner = await User.findById(req.userId).select('friends username avatar');
        if (!owner) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const requestedInviteIds = uniqueIds(invitedFriendIds).filter(
            (id) => id !== req.userId && isValidObjectId(id)
        );
        const friendIdSet = new Set((owner.friends || []).map((id) => toIdString(id)));
        const inviteIds = requestedInviteIds.filter((id) => friendIdSet.has(id));

        const group = new Group({
            name,
            description: description || '',
            motto: motto || '',
            avatar: String(avatar || '').trim(),
            isPublic: isPublic !== false,
            approvalRequired: approvalRequired === true,
            maxMembers: Number(maxMembers || 20),
            type: type || 'small',
            vibe: vibe || 'Orbit',
            leaderId: req.userId,
            admins: [],
            treasureChest: {
                available: true
            },
            members: [{
                userId: req.userId,
                role: 'leader',
                joinedAt: Date.now()
            }],
            invitations: inviteIds.map((userId) => ({
                userId,
                invitedBy: req.userId,
                status: 'pending',
                invitedAt: Date.now()
            })),
            lastActivityAt: Date.now()
        });

        await group.save();

        const voiceRoom = await createLinkedVoiceRoom({
            group,
            ownerId: req.userId,
            maxMembers: group.maxMembers
        });

        group.linkedRoomId = voiceRoom._id;
        await group.save();

        const hydrated = await loadGroup(group._id);
        await emitGroupEvent(req, hydrated._id, 'created', {
            actorId: req.userId,
            targetUserIds: inviteIds
        });

        res.status(201).json(buildGroupForViewer(hydrated, req.userId));
    } catch (error) {
        next(error);
    }
}

async function getMyGroups(req, res, next) {
    try {
        const groups = await populateGroupQuery(
            Group.find({ 'members.userId': req.userId })
                .sort({ lastActivityAt: -1, updatedAt: -1 })
        );

        res.json(groups.map((group) => buildGroupForViewer(group, req.userId)));
    } catch (error) {
        next(error);
    }
}

async function getMyInvites(req, res, next) {
    try {
        const groups = await populateGroupQuery(
            Group.find({
                invitations: {
                    $elemMatch: {
                        userId: req.userId,
                        status: 'pending'
                    }
                }
            }).sort({ lastActivityAt: -1, updatedAt: -1 })
        );

        res.json(groups.map((group) => buildGroupForViewer(group, req.userId)));
    } catch (error) {
        next(error);
    }
}

async function getDiscoverGroups(req, res, next) {
    try {
        const groups = await populateGroupQuery(
            Group.find({
                isPublic: true,
                'members.userId': { $ne: req.userId },
                invitations: {
                    $not: {
                        $elemMatch: {
                            userId: req.userId,
                            status: 'pending'
                        }
                    }
                }
            })
                .limit(50)
                .sort({ memberCount: -1, lastActivityAt: -1 })
        );

        res.json(groups.map((group) => buildGroupForViewer(group, req.userId)));
    } catch (error) {
        next(error);
    }
}

async function getLeaderboard(req, res, next) {
    try {
        const groups = await populateGroupQuery(
            Group.find()
                .sort({ 'stats.totalXp': -1, memberCount: -1, lastActivityAt: -1 })
                .limit(100)
        );

        res.json(
            groups.map((group, index) => {
                const payload = buildGroupBroadcast(group);
                payload.stats = {
                    ...(payload.stats || {}),
                    rank: index + 1
                };
                return payload;
            })
        );
    } catch (error) {
        next(error);
    }
}

async function getGroupById(req, res, next) {
    try {
        const group = await loadGroup(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const viewerId = req.userId || '';
        const isMember = viewerId ? !!getMemberRecord(group, viewerId) : false;
        const hasInvite = viewerId
            ? (group.invitations || []).some(
                (invite) =>
                    toIdString(invite.userId) === viewerId &&
                    invite.status === 'pending'
            )
            : false;

        if (!group.isPublic && !isMember && !hasInvite) {
            const error = new Error('This group is private');
            error.status = 403;
            throw error;
        }

        res.json(buildGroupForViewer(group, viewerId));
    } catch (error) {
        next(error);
    }
}

async function joinGroup(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (getMemberRecord(group, req.userId)) {
            const error = new Error('Already a member');
            error.status = 400;
            throw error;
        }

        if ((group.members || []).length >= group.maxMembers) {
            const error = new Error('Group is full');
            error.status = 400;
            throw error;
        }

        const invite = (group.invitations || []).find(
            (entry) =>
                toIdString(entry.userId) === req.userId &&
                entry.status === 'pending'
        );

        if (!group.isPublic && !invite) {
            const error = new Error('This group is invite only');
            error.status = 403;
            throw error;
        }

        if (group.approvalRequired && !invite) {
            const existingRequest = (group.joinRequests || []).find(
                (request) => toIdString(request.userId) === req.userId
            );
            if (existingRequest) {
                const error = new Error('Join request already pending');
                error.status = 400;
                throw error;
            }

            group.joinRequests.push({
                userId: req.userId,
                message: typeof req.body?.message === 'string'
                    ? req.body.message.trim().slice(0, 120)
                    : '',
                requestedAt: Date.now()
            });
            group.lastActivityAt = Date.now();
            await group.save();

            await emitGroupEvent(req, group._id, 'join_requested', {
                actorId: req.userId,
                targetUserIds: [
                    toIdString(group.leaderId),
                    ...(group.admins || []).map((id) => toIdString(id))
                ]
            });

            return res.json({
                success: true,
                pendingApproval: true,
                message: 'Join request sent'
            });
        }

        attachMember(group, req.userId, 'member');
        if (invite) {
            invite.status = 'accepted';
            invite.respondedAt = Date.now();
        }

        await group.save();

        await emitGroupEvent(req, group._id, invite ? 'invite_accepted' : 'member_joined', {
            actorId: req.userId,
            memberUserId: req.userId
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            joined: true,
            group: buildGroupForViewer(hydrated, req.userId),
            message: invite ? 'Invitation accepted' : 'Joined group successfully'
        });
    } catch (error) {
        next(error);
    }
}

async function leaveGroup(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (isGroupLeader(group, req.userId)) {
            const error = new Error('Group owner cannot leave. Transfer ownership or delete the group.');
            error.status = 400;
            throw error;
        }

        if (!getMemberRecord(group, req.userId)) {
            const error = new Error('You are not in this group');
            error.status = 400;
            throw error;
        }

        removeMemberFromGroup(group, req.userId);
        await group.save();
        await removeUserFromLinkedRoom(group, req.userId);

        await emitGroupEvent(req, group._id, 'member_left', {
            actorId: req.userId,
            memberUserId: req.userId
        });

        res.json({ success: true, message: 'Left group successfully' });
    } catch (error) {
        next(error);
    }
}

async function claimTreasure(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (!getMemberRecord(group, req.userId)) {
            const error = new Error('Not a member of this group');
            error.status = 403;
            throw error;
        }

        const now = new Date();
        const lastClaimed = group.treasureChest?.lastClaimed;
        const cooldownMs = 24 * 60 * 60 * 1000;
        const isAvailable = group.treasureChest?.available === true ||
            !lastClaimed ||
            (now - lastClaimed) >= cooldownMs;
        if (!isAvailable) {
            const error = new Error('Treasure not available');
            error.status = 400;
            throw error;
        }

        const reward = 100 + ((group.members || []).length * 10);
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        user.coins = Number(user.coins || 0) + reward;
        await user.save();

        group.treasureChest.available = false;
        group.treasureChest.lastClaimed = now;
        group.lastActivityAt = now;
        await group.save();

        await emitGroupEvent(req, group._id, 'treasure_claimed', {
            actorId: req.userId
        });

        res.json({
            success: true,
            coins: reward,
            message: 'Treasure claimed!',
            newBalance: user.coins
        });
    } catch (error) {
        next(error);
    }
}

async function inviteFriends(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        ensureManageAccess(group, req.userId);

        const requestedUserIds = uniqueIds(req.body?.userIds || []).filter(isValidObjectId);
        if (requestedUserIds.length === 0) {
            const error = new Error('Choose at least one friend to invite');
            error.status = 400;
            throw error;
        }

        const actor = await User.findById(req.userId).select('friends');
        if (!actor) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const friendIdSet = new Set((actor.friends || []).map((id) => toIdString(id)));
        const memberIdSet = new Set((group.members || []).map((member) => toIdString(member.userId)));
        const invitedIds = [];

        for (const userId of requestedUserIds) {
            if (!friendIdSet.has(userId) || memberIdSet.has(userId)) {
                continue;
            }

            const existingInvite = (group.invitations || []).find(
                (invite) =>
                    toIdString(invite.userId) === userId &&
                    invite.status === 'pending'
            );
            if (existingInvite) {
                continue;
            }

            group.invitations.push({
                userId,
                invitedBy: req.userId,
                status: 'pending',
                invitedAt: Date.now()
            });
            invitedIds.push(userId);
        }

        if (invitedIds.length === 0) {
            const error = new Error('Those friends are already in the group or already invited');
            error.status = 400;
            throw error;
        }

        group.lastActivityAt = Date.now();
        await group.save();

        await emitGroupEvent(req, group._id, 'invited', {
            actorId: req.userId,
            targetUserIds: invitedIds
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            invited: invitedIds.length,
            group: buildGroupForViewer(hydrated, req.userId)
        });
    } catch (error) {
        next(error);
    }
}

async function acceptInvite(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (getMemberRecord(group, req.userId)) {
            const error = new Error('Already a member');
            error.status = 400;
            throw error;
        }

        if ((group.members || []).length >= group.maxMembers) {
            const error = new Error('Group is full');
            error.status = 400;
            throw error;
        }

        const invite = (group.invitations || []).find(
            (entry) =>
                toIdString(entry.userId) === req.userId &&
                entry.status === 'pending'
        );
        if (!invite) {
            const error = new Error('Invitation not found');
            error.status = 404;
            throw error;
        }

        invite.status = 'accepted';
        invite.respondedAt = Date.now();
        attachMember(group, req.userId, 'member');
        await group.save();

        await emitGroupEvent(req, group._id, 'invite_accepted', {
            actorId: req.userId,
            memberUserId: req.userId
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            group: buildGroupForViewer(hydrated, req.userId)
        });
    } catch (error) {
        next(error);
    }
}

async function rejectInvite(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const invite = (group.invitations || []).find(
            (entry) =>
                toIdString(entry.userId) === req.userId &&
                entry.status === 'pending'
        );
        if (!invite) {
            const error = new Error('Invitation not found');
            error.status = 404;
            throw error;
        }

        invite.status = 'rejected';
        invite.respondedAt = Date.now();
        group.lastActivityAt = Date.now();
        await group.save();

        await emitGroupEvent(req, group._id, 'invite_rejected', {
            actorId: req.userId,
            memberUserId: req.userId,
            targetUserIds: [
                toIdString(group.leaderId),
                ...(group.admins || []).map((id) => toIdString(id))
            ]
        });

        res.json({ success: true, message: 'Invitation declined' });
    } catch (error) {
        next(error);
    }
}

async function approveJoinRequest(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        ensureManageAccess(group, req.userId);

        if ((group.members || []).length >= group.maxMembers) {
            const error = new Error('Group is full');
            error.status = 400;
            throw error;
        }

        const targetUserId = req.params.userId;
        const requestIndex = (group.joinRequests || []).findIndex(
            (request) => toIdString(request.userId) === targetUserId
        );
        if (requestIndex === -1) {
            const error = new Error('Join request not found');
            error.status = 404;
            throw error;
        }

        group.joinRequests.splice(requestIndex, 1);
        if (!getMemberRecord(group, targetUserId)) {
            attachMember(group, targetUserId, 'member');
        }
        await group.save();

        await emitGroupEvent(req, group._id, 'join_request_approved', {
            actorId: req.userId,
            memberUserId: targetUserId,
            targetUserIds: [targetUserId]
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            group: buildGroupForViewer(hydrated, req.userId)
        });
    } catch (error) {
        next(error);
    }
}

async function rejectJoinRequest(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        ensureManageAccess(group, req.userId);

        const targetUserId = req.params.userId;
        const requestIndex = (group.joinRequests || []).findIndex(
            (request) => toIdString(request.userId) === targetUserId
        );
        if (requestIndex === -1) {
            const error = new Error('Join request not found');
            error.status = 404;
            throw error;
        }

        group.joinRequests.splice(requestIndex, 1);
        group.lastActivityAt = Date.now();
        await group.save();

        await emitGroupEvent(req, group._id, 'join_request_rejected', {
            actorId: req.userId,
            memberUserId: targetUserId,
            targetUserIds: [targetUserId]
        });

        res.json({ success: true, message: 'Join request declined' });
    } catch (error) {
        next(error);
    }
}

async function updateMemberRole(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        ensureOwnerAccess(group, req.userId);

        const targetUserId = req.params.userId;
        const nextRole = req.body?.role;
        if (!['admin', 'member'].includes(nextRole)) {
            const error = new Error('Role must be admin or member');
            error.status = 400;
            throw error;
        }

        if (targetUserId === req.userId) {
            const error = new Error('Owner role cannot be changed here');
            error.status = 400;
            throw error;
        }

        const member = getMemberRecord(group, targetUserId);
        if (!member) {
            const error = new Error('Member not found');
            error.status = 404;
            throw error;
        }

        member.role = nextRole;
        syncAdminsFromMembers(group);
        group.lastActivityAt = Date.now();
        await group.save();

        await emitGroupEvent(req, group._id, 'role_updated', {
            actorId: req.userId,
            memberUserId: targetUserId,
            role: nextRole,
            targetUserIds: [targetUserId]
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            group: buildGroupForViewer(hydrated, req.userId)
        });
    } catch (error) {
        next(error);
    }
}

async function removeMember(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const actorIsLeader = isGroupLeader(group, req.userId);
        const actorIsAdmin = isGroupAdmin(group, req.userId);
        if (!actorIsAdmin) {
            const error = new Error('Only the owner and admins can remove members');
            error.status = 403;
            throw error;
        }

        const targetUserId = req.params.userId;
        if (targetUserId === req.userId) {
            const error = new Error('Use leave group instead');
            error.status = 400;
            throw error;
        }

        const targetMember = getMemberRecord(group, targetUserId);
        if (!targetMember) {
            const error = new Error('Member not found');
            error.status = 404;
            throw error;
        }

        if (targetMember.role === 'leader') {
            const error = new Error('Owner cannot be removed');
            error.status = 400;
            throw error;
        }

        if (!actorIsLeader && targetMember.role === 'admin') {
            const error = new Error('Only the owner can remove another admin');
            error.status = 403;
            throw error;
        }

        removeMemberFromGroup(group, targetUserId);
        group.joinRequests = (group.joinRequests || []).filter(
            (request) => toIdString(request.userId) !== targetUserId
        );
        group.invitations = (group.invitations || []).filter(
            (invite) => toIdString(invite.userId) !== targetUserId
        );
        await group.save();
        await removeUserFromLinkedRoom(group, targetUserId);

        await emitGroupEvent(req, group._id, 'member_removed', {
            actorId: req.userId,
            memberUserId: targetUserId,
            targetUserIds: [targetUserId]
        });

        const hydrated = await loadGroup(group._id);
        res.json({
            success: true,
            group: buildGroupForViewer(hydrated, req.userId)
        });
    } catch (error) {
        next(error);
    }
}

async function updateGroup(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const actorIsLeader = isGroupLeader(group, req.userId);
        const actorIsAdmin = isGroupAdmin(group, req.userId);

        if (!actorIsAdmin) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        const sharedFields = ['name', 'description', 'motto', 'avatar', 'coverImage', 'announcement', 'vibe'];
        for (const field of sharedFields) {
            if (req.body[field] !== undefined) {
                group[field] = req.body[field];
            }
        }

        if (actorIsLeader) {
            const ownerFields = ['isPublic', 'approvalRequired', 'maxMembers', 'type'];
            for (const field of ownerFields) {
                if (req.body[field] !== undefined) {
                    if (
                        field === 'maxMembers' &&
                        Number(req.body.maxMembers) < (group.members || []).length
                    ) {
                        const error = new Error('Max members cannot be below the current member count');
                        error.status = 400;
                        throw error;
                    }
                    group[field] = req.body[field];
                }
            }
        }

        group.lastActivityAt = Date.now();
        await group.save();

        if (group.linkedRoomId) {
            const roomPatch = {};
            if (req.body.name !== undefined) roomPatch.name = `${group.name} Lounge`;
            if (req.body.description !== undefined) {
                roomPatch.description = group.description || `Voice lounge for ${group.name}`;
            }
            if (actorIsLeader && req.body.maxMembers !== undefined) {
                roomPatch['settings.maxParticipants'] = Math.max(
                    10,
                    Math.min(Number(group.maxMembers || 20), 1000)
                );
            }

            if (Object.keys(roomPatch).length > 0) {
                await Room.findByIdAndUpdate(group.linkedRoomId, roomPatch);
            }
        }

        await emitGroupEvent(req, group._id, 'group_updated', {
            actorId: req.userId
        });

        const hydrated = await loadGroup(group._id);
        res.json(buildGroupForViewer(hydrated, req.userId));
    } catch (error) {
        next(error);
    }
}

async function deleteGroup(req, res, next) {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        ensureOwnerAccess(group, req.userId);

        const targetUserIds = uniqueIds([
            ...(group.members || []).map((member) => toIdString(member.userId)),
            ...(group.invitations || []).map((invite) => toIdString(invite.userId))
        ]);

        if (group.linkedRoomId) {
            await Room.findByIdAndDelete(group.linkedRoomId);
        }

        await group.deleteOne();

        const io = req.app.get('io');
        if (io) {
            const payload = {
                action: 'deleted',
                groupId: req.params.id,
                actorId: req.userId,
                updatedAt: new Date().toISOString()
            };
            io.to(`group:${req.params.id}`).emit('group:updated', payload);
            for (const userId of targetUserIds) {
                io.to(`user:${userId}`).emit('group:updated', payload);
            }
        }

        res.json({ success: true, message: 'Group deleted' });
    } catch (error) {
        next(error);
    }
}

module.exports = {
    createGroup,
    getMyGroups,
    getMyInvites,
    getDiscoverGroups,
    getLeaderboard,
    getGroupById,
    joinGroup,
    leaveGroup,
    claimTreasure,
    inviteFriends,
    acceptInvite,
    rejectInvite,
    approveJoinRequest,
    rejectJoinRequest,
    updateMemberRole,
    removeMember,
    updateGroup,
    deleteGroup
};
