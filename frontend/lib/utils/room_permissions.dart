import '../models/room_model.dart';

class RoomPermissions {
  RoomPermissions({
    required this.room,
    required this.userId,
  });

  final RoomModel room;
  final String? userId;

  Participant? get selfParticipant => _participantFor(userId);
  String? get selfRole => selfParticipant?.role.toLowerCase();

  bool get isOwner =>
      userId != null && (userId == room.hostId || selfRole == 'host');
  bool get isAdmin =>
      userId != null &&
      (isOwner ||
          room.coHostIds.contains(userId) ||
          room.moderatorIds.contains(userId) ||
          selfRole == 'cohost' ||
          selfRole == 'moderator');
  bool get isSpeaker {
    final participant = selfParticipant;
    if (participant == null) return false;
    return participant.seatIndex >= 0 ||
        participant.role == 'speaker' ||
        participant.role == 'moderator' ||
        participant.role == 'cohost' ||
        participant.role == 'host';
  }

  bool get canOpenRoomSettings => isAdmin;
  bool get canManageRoom => isAdmin;
  bool get canManageStage => isAdmin;
  bool get canManageSafety => isAdmin;
  bool get canManageRoomIdentity => isOwner;
  bool get canManageRoomAccess => isOwner;
  bool get canManageAdmins => isOwner;
  bool get canManageGifting => isOwner;
  bool get canEditAnnouncement => isOwner;
  bool get canEndRoom => isOwner;
  bool get canTransferOwnership => isOwner;
  bool get canViewReports => isOwner;
  bool get canUseRoomGifts => room.allowGifts || isOwner;
  bool get canJoinStageDirectly =>
      isAdmin || (!room.stageJoinsLocked && !room.requireApproval);
  bool get canRequestMic =>
      userId != null && !isAdmin && !isSpeaker && !room.isLockedSeat(1);

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
      participant.userId != room.hostId &&
      participant.userId != userId;

  bool canTransferOwnershipTo(Participant participant) =>
      canTransferOwnership &&
      participant.userId != room.hostId &&
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
    if (participant.userId == room.hostId || participant.role == 'host') {
      return 4;
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
