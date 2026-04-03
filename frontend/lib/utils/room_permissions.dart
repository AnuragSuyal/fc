import '../models/room_model.dart';

class RoomPermissions {
  RoomPermissions({
    required this.room,
    required this.userId,
  });

  final RoomModel room;
  final String? userId;

  bool _capability(String key, bool fallback) {
    final value = room.capabilities[key];
    if (value == null) return fallback;
    return value;
  }

  Participant? get selfParticipant => _participantFor(userId);
  String? get selfRole => selfParticipant?.role.toLowerCase();
  String get _effectiveOwnerId =>
      room.ownerId.isNotEmpty ? room.ownerId : room.hostId;

  bool get isOwner => _capability(
        'isOwner',
        userId != null && userId == _effectiveOwnerId,
      );
  bool get isAdmin => _capability(
        'isAdmin',
        userId != null &&
            (isOwner ||
                userId == room.hostId ||
                room.coHostIds.contains(userId) ||
                room.moderatorIds.contains(userId) ||
                selfRole == 'cohost' ||
                selfRole == 'moderator'),
      );
  bool get isSpeaker {
    final capabilityValue = room.capabilities['isSpeaker'];
    if (capabilityValue != null) return capabilityValue;
    final participant = selfParticipant;
    if (participant == null) return false;
    return participant.seatIndex >= 0 ||
        participant.role == 'speaker' ||
        participant.role == 'moderator' ||
        participant.role == 'cohost' ||
        participant.role == 'host';
  }

  bool get canOpenRoomSettings => _capability('canOpenRoomSettings', isAdmin);
  bool get canManageRoom => _capability('canManageRoom', isAdmin);
  bool get canManageStage =>
      _capability('canManageStage', room.roomActive && isAdmin);
  bool get canManageSeatLocks => _capability(
        'canManageSeatLocks',
        room.roomActive && (isOwner || (isAdmin && room.allowAdminSeatControl)),
      );
  bool get canManageSafety =>
      _capability('canManageSafety', room.roomActive && isAdmin);
  bool get canManageRoomMedia =>
      _capability('canManageRoomMedia', room.roomActive && isAdmin);
  bool get canManageRoomIdentity =>
      _capability('canManageRoomIdentity', isOwner);
  bool get canManageRoomAccess => _capability('canManageRoomAccess', isOwner);
  bool get canManageAdmins => _capability('canManageAdmins', isOwner);
  bool get canManageGifting =>
      _capability('canManageGifting', isOwner || isAdmin);
  bool get canActivateDragonPacket =>
      _capability('canActivateDragonPacket', room.roomActive && isAdmin);
  bool get canEditAnnouncement => _capability('canEditAnnouncement', isOwner);
  bool get canEndRoom => _capability('canEndRoom', isOwner);
  bool get canTransferOwnership => _capability('canTransferOwnership', isOwner);
  bool get canViewReports => _capability('canViewReports', isOwner);
  bool get canViewBans => _capability('canViewBans', isAdmin);
  bool get canInviteUsers => _capability('canInviteUsers', isAdmin);
  bool get canRallyFans => _capability('canRallyFans', isAdmin);
  bool get canSendRoomMessages =>
      _capability('canSendRoomMessages', !room.banTextChat || isAdmin);
  bool get canSendRoomImages =>
      _capability('canSendRoomImages', !room.banPhotoChat || isAdmin);
  bool get canUseRoomGifts =>
      _capability('canSendRoomGifts', room.allowGifts || isOwner);
  bool get canUnlockMiniDraw =>
      _capability('canUnlockMiniDraw', room.miniDraw.permissions.canUnlock);
  bool get canManageMiniDraw =>
      _capability('canManageMiniDraw', room.miniDraw.permissions.canManage);
  bool get canViewMiniDraw =>
      _capability('canViewMiniDraw', room.miniDraw.permissions.canView);
  bool get canDrawOnMiniDraw =>
      _capability('canDrawOnMiniDraw', room.miniDraw.permissions.canDraw);
  bool get canClearMiniDraw =>
      _capability('canClearMiniDraw', room.miniDraw.permissions.canClear);
  bool get canUndoRedoMiniDraw => _capability(
        'canUndoRedoMiniDraw',
        room.miniDraw.permissions.canUndoRedo,
      );
  bool get canJoinStageDirectly => _capability(
        'canJoinStageDirectly',
        room.roomActive &&
            (isAdmin || (!room.stageJoinsLocked && !room.requireApproval)),
      );
  bool get canRequestMic => _capability(
        'canRequestMic',
        room.roomActive &&
            userId != null &&
            !isAdmin &&
            !isSpeaker &&
            !room.isLockedSeat(1),
      );

  int get authorityLevel {
    if (userId == null) return 0;
    if (isOwner) return 4;
    if (isAdmin) return 3;
    if (isSpeaker) return 2;
    return 1;
  }

  bool canModerateParticipant(Participant participant) {
    if (userId == null || participant.userId == userId) return false;
    return authorityLevel > _authorityLevelForParticipant(participant);
  }

  bool canManageSpeakerState(Participant participant) =>
      canManageStage && canModerateParticipant(participant);

  bool canManageAdminRole(Participant participant) =>
      canManageAdmins &&
      participant.userId != _effectiveOwnerId &&
      participant.userId != userId;

  bool canTransferOwnershipTo(Participant participant) =>
      canTransferOwnership &&
      participant.userId != _effectiveOwnerId &&
      participant.userId != userId;

  Participant? _participantFor(String? targetUserId) {
    if (targetUserId == null) return null;
    for (final participant in room.participants) {
      if (participant.userId == targetUserId) {
        return participant;
      }
    }
    return null;
  }

  int _authorityLevelForParticipant(Participant participant) {
    if (participant.userId == _effectiveOwnerId) {
      return 4;
    }
    if (participant.userId == room.hostId || participant.role == 'host') {
      return 3;
    }
    if (room.coHostIds.contains(participant.userId) ||
        room.moderatorIds.contains(participant.userId) ||
        participant.role == 'cohost' ||
        participant.role == 'moderator') {
      return 3;
    }
    if (participant.seatIndex >= 0 || participant.role == 'speaker') {
      return 2;
    }
    return 1;
  }
}
