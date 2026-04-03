import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/mini_draw_model.dart';
import 'package:frontend/models/room_model.dart';

void main() {
  test('mini draw summary parses permissions and access policy', () {
    final summary = MiniDrawSessionSummary.fromJson({
      'sessionId': 'session-42',
      'roomId': 'room-1',
      'isUnlocked': true,
      'enabled': true,
      'accessPolicy': 'host_admin',
      'unlockCostCoins': 300,
      'version': 7,
      'strokeCount': 12,
      'permissions': {
        'canUnlock': false,
        'canManage': true,
        'canView': true,
        'canDraw': true,
        'canClear': true,
        'canUndoRedo': true,
      },
    });

    expect(summary.sessionId, 'session-42');
    expect(summary.accessPolicy, MiniDrawAccessPolicy.hostAdmin);
    expect(summary.unlockCostCoins, 300);
    expect(summary.version, 7);
    expect(summary.strokeCount, 12);
    expect(summary.permissions.canManage, isTrue);
    expect(summary.permissions.canDraw, isTrue);
  });

  test('room model falls back to room settings mini draw snapshot', () {
    final room = RoomModel.fromJson({
      '_id': 'room-1',
      'roomId': 'voice-room-1',
      'name': 'Canvas Room',
      'description': 'Realtime draw test',
      'type': 'voice',
      'category': 'voice',
      'tags': const [],
      'ownerId': 'host-1',
      'hostId': 'host-1',
      'hostName': 'Host',
      'hostAvatar': '',
      'hostLevel': 5,
      'settings': const {},
      'participantCount': 1,
      'onlineCount': 1,
      'participants': const [
        {
          'userId': 'host-1',
          'username': 'Host',
          'role': 'host',
          'isPresent': true,
        },
      ],
      'lockedSeats': const [],
      'followers': const [],
      'coHosts': const [],
      'moderators': const [],
      'level': 1,
      'exp': 0,
      'expToday': 0,
      'region': 'Global',
      'metrics': const {'followers': 0},
      'economy': const {'totalEarned': 0},
      'theme': const {'background': 'default'},
      'announcement': '',
      'createdAt': '2026-03-30T00:00:00.000Z',
      'roomSettings': {
        'miniDraw': {
          'sessionId': 'fallback-session',
          'roomId': 'room-1',
          'isUnlocked': true,
          'enabled': true,
          'accessPolicy': 'view_only',
          'version': 3,
          'strokeCount': 4,
        },
      },
    });

    expect(room.miniDraw.sessionId, 'fallback-session');
    expect(room.miniDraw.isUnlocked, isTrue);
    expect(room.miniDraw.accessPolicy, MiniDrawAccessPolicy.viewOnly);
    expect(room.miniDraw.version, 3);
    expect(room.miniDraw.strokeCount, 4);
  });
}
