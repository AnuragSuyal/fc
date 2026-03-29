import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/color_clash_home_model.dart';
import 'package:frontend/models/color_clash_lobby_model.dart';
import 'package:frontend/models/color_clash_match_snapshot.dart';
import 'package:frontend/models/color_clash_season_model.dart';
import 'package:frontend/models/color_clash_table_model.dart';

void main() {
  test('Color Clash home payload parses real backend-style shape', () {
    final home = ColorClashHomeModel.fromJson({
      'gameId': 'color_clash',
      'season': {
        'id': 'season-1',
        'key': '2026-03',
        'name': 'March Clash',
        'status': 'active',
        'startsAt': '2026-03-01T00:00:00.000Z',
        'endsAt': '2026-03-31T23:59:59.000Z',
        'finalizeAt': '2026-04-01T00:00:00.000Z',
        'placementMatches': 5,
        'rankedEnabled': true,
        'tiers': [
          {
            'id': 'spark',
            'name': 'Spark',
            'order': 1,
            'minRating': 0,
            'maxRating': 1099,
            'divisions': 3,
            'starsPerDivision': 4,
          }
        ],
        'ratingConfig': {
          'baseRating': 1000,
          'kFactor': 32,
          'streakBonus': 4,
          'placementMultiplier': 1.5,
          'inactivityDecay': 0,
        },
        'rewardPreview': const [],
        'themeRotation': ['forest_picnic'],
      },
      'userProgress': {
        'stats': {'rankedPlayed': 4},
        'activeQueueTicketId': 'ticket-1',
        'currentSeason': {
          'seasonId': 'season-1',
          'userId': 'user-1',
          'rating': 1044,
          'peakRating': 1044,
          'tierId': 'spark',
          'tierName': 'Spark',
          'division': 2,
          'stars': 3,
          'placementMatchesRemaining': 1,
          'wins': 3,
          'losses': 1,
          'currentStreak': 2,
          'bestStreak': 2,
          'timeoutLosses': 0,
          'forfeitLosses': 0,
          'opponentDiversityScore': 80,
          'smurfWatch': false,
          'leaderboardScore': 1044,
          'rewardStatus': 'pending',
        },
        'currentUserRank': {'rank': 7, 'score': 1044},
        'eligibility': {
          'rankedEligible': true,
          'stakeEligible': true,
          'rankedLockReason': '',
          'stakeLockReason': '',
          'riskState': const {},
        },
      },
      'queuePresets': [
        {
          'queueId': 'casual-global',
          'mode': 'casual_free',
          'stakeAmount': 0,
          'region': 'Global',
          'playerCount': 2,
          'enabled': true,
          'themePackId': 'forest_picnic',
        }
      ],
      'rooms': const [],
      'activeMatch': {
        'matchId': 'match-1',
        'roomId': 'room-1',
        'status': 'active',
        'tableMode': 'ranked',
        'version': 3,
        'players': [
          {
            'userId': 'user-1',
            'seatIndex': 0,
            'username': 'Asha',
            'avatar': '',
            'status': 'active',
          }
        ],
        'publicState': {
          'gameId': 'color_clash',
          'roundNumber': 1,
          'phase': 'active',
          'currentTurnSeat': 0,
          'direction': 1,
          'currentHue': 'ember',
          'discardTop': {
            'id': 'card-1',
            'kind': 'number',
            'hue': 'ember',
            'value': 4,
          },
          'drawPileCount': 85,
          'discardCount': 1,
          'players': [
            {
              'seatIndex': 0,
              'userId': 'user-1',
              'status': 'active',
              'handCount': 7,
              'timeoutStrikes': 0,
              'hasShield': false,
              'pendingLastCardCall': false,
              'declaredLastCard': false,
            }
          ],
        },
      },
      'themes': {
        'equippedThemePackId': 'forest_picnic',
        'ownedThemePackIds': ['forest_picnic', 'neon_orbit'],
      },
      'tutorial': {
        'completedVersions': ['v1']
      },
      'leaderboardPreview': const [],
      'rewardPreview': const [],
    });

    expect(home.gameId, 'color_clash');
    expect(home.userProgress.activeQueueTicketId, 'ticket-1');
    expect(home.hasActiveMatch, isTrue);
    expect(home.activeMatch?.publicState?.discardTop?.value, 4);
    expect(home.themes.ownedThemePackIds, contains('neon_orbit'));
    expect(home.tutorial.isV1Complete, isTrue);
  });

  test('Color Clash lobby and match snapshot parsing preserve privacy helpers',
      () {
    final lobby = ColorClashLobbyModel.fromJson({
      'roomId': 'room-1',
      'gameId': 'color_clash',
      'lobbyVersion': 5,
      'status': 'open',
      'minPlayersToStart': 2,
      'maxPlayers': 4,
      'countdownSec': 6,
      'allowSpectators': true,
      'seats': {'0': 'user-1'},
      'playersByUserId': {
        'user-1': {
          'userId': 'user-1',
          'username': 'Asha',
          'avatar': '',
          'seatIndex': 0,
          'ready': true,
          'role': 'player',
          'joinedAtMs': 1,
          'lastSeenAtMs': 2,
        },
        'user-2': {
          'userId': 'user-2',
          'username': 'Mira',
          'avatar': '',
          'ready': false,
          'role': 'spectator',
          'joinedAtMs': 3,
          'lastSeenAtMs': 4,
        },
      },
      'updatedAtMs': 100,
    });

    final snapshot = ColorClashMatchSnapshotModel.fromJson({
      'matchId': 'match-1',
      'roomId': 'room-1',
      'version': 2,
      'viewerRole': 'player',
      'publicState': {
        'gameId': 'color_clash',
        'roundNumber': 1,
        'phase': 'active',
        'currentTurnSeat': 0,
        'direction': 1,
        'currentHue': 'ember',
        'discardTop': {
          'id': 'card-1',
          'kind': 'number',
          'hue': 'ember',
          'value': 5,
        },
        'drawPileCount': 84,
        'discardCount': 2,
        'players': [
          {
            'seatIndex': 0,
            'userId': 'user-1',
            'status': 'active',
            'handCount': 6,
            'timeoutStrikes': 0,
            'hasShield': false,
            'pendingLastCardCall': true,
            'declaredLastCard': true,
          }
        ],
        'turnContext': {
          'phase': 'main',
          'turnEndsAt': 1711735200000,
          'graceEndsAt': 1711735205000,
        },
      },
      'privateState': {
        'seatIndex': 0,
        'currentTurnSeat': 0,
        'hand': [
          {
            'id': 'card-private',
            'kind': 'number',
            'hue': 'tidal',
            'value': 9,
          }
        ],
        'legalMoves': [
          {'type': 'play_card', 'cardId': 'card-private'}
        ],
      },
      'presence': {'players': 2, 'spectators': 1},
      'replayAvailable': true,
    });

    expect(lobby.readyPlayers.length, 1);
    expect(lobby.spectatorCount, 1);
    expect(snapshot.isPlayerView, isTrue);
    expect(snapshot.privateState?.hand.single.id, 'card-private');
    expect(snapshot.publicState.players.single.handCount, 6);
    expect(snapshot.publicState.turnContext?.turnEndsAt, 1711735200000);
  });
}
