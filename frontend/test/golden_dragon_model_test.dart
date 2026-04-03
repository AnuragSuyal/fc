import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/golden_dragon_model.dart';

void main() {
  test('golden dragon product and event result parse correctly', () {
    final products = DragonPacketProductsResponse.fromJson({
      'config': {
        'featureEnabled': true,
        'eventDurationMs': 10000,
        'participantJoinCutoffRemainingMs': 5000,
        'minimumRoomPresenceSeconds': 2,
        'minimumAccountAgeDaysToClaim': 0,
        'requireVerifiedAccountToClaim': false,
        'activatorCanClaim': false,
        'basePoolPercentage': 30,
        'maxSharePercentagePerUser': 20,
        'minValidTapsToParticipate': 1,
        'maxCountedTapsPerSecond': 8,
        'maxTotalCountedTaps': 50,
        'maxCountedTapsPerRollingWindow': 14,
        'rollingWindowSeconds': 2,
        'leaderboardBroadcastIntervalMs': 1000,
        'inventoryRefundMode': 'restore_inventory',
        'allowedRoomTypes': ['voice'],
        'products': [
          {
            'sku': 'dragon_packet_small_199_inr',
            'packageType': 'small',
            'name': 'Dragon Packet Small',
            'priceInr': 199,
            'currency': 'INR',
            'packetCoinAmount': 800,
            'artworkAssetKey': 'golden_dragon_packet_small',
            'badgeLabel': 'Starter Fire',
          },
        ],
      },
      'products': [
        {
          'sku': 'dragon_packet_small_199_inr',
          'packageType': 'small',
          'name': 'Dragon Packet Small',
          'priceInr': 199,
          'currency': 'INR',
          'packetCoinAmount': 800,
          'artworkAssetKey': 'golden_dragon_packet_small',
          'badgeLabel': 'Starter Fire',
          'availableCount': 2,
        },
      ],
    });

    expect(products.config.featureEnabled, isTrue);
    expect(products.products.single.availableCount, 2);
    expect(
      products.products.single.artworkAssetPath,
      'assets/images/golden_dragon_packet_small.png',
    );

    final result = GoldenDragonEventResult.fromJson({
      'eventId': 'dragon-event-1',
      'eventReferenceId': 'DRE001',
      'roomId': 'room-1',
      'roomName': 'Dragon Arena',
      'activatorUserId': 'host-1',
      'activatorName': 'Host',
      'activatorAvatar': '',
      'productSku': 'dragon_packet_small_199_inr',
      'packageType': 'small',
      'packetTotalCoins': 800,
      'eventStatus': 'settled',
      'startAtServer': '2026-03-31T10:00:00.000Z',
      'endAtServer': '2026-03-31T10:00:10.000Z',
      'eventDurationMs': 10000,
      'dragonVisualType': 'golden_dragon_default',
      'totalDistributed': 800,
      'totalParticipants': 2,
      'packetExhausted': true,
      'refundStatus': 'none',
      'winners': [
        {
          'participantId': 'claim-1',
          'userId': 'user-1',
          'username': 'Anurag',
          'acceptedTapCount': 12,
          'computedScore': 10.6,
          'finalCoinReward': 420,
          'finalRank': 1,
          'eligibilityStatus': 'eligible',
          'payoutStatus': 'paid',
        },
      ],
      'myClaim': {
        'participantId': 'claim-1',
        'userId': 'user-1',
        'username': 'Anurag',
        'acceptedTapCount': 12,
        'computedScore': 10.6,
        'finalCoinReward': 420,
        'finalRank': 1,
        'eligibilityStatus': 'eligible',
        'payoutStatus': 'paid',
      },
    });

    expect(result.packetExhausted, isTrue);
    expect(result.winners.single.finalCoinReward, 420);
    expect(result.myClaim?.username, 'Anurag');
    expect(result.roomName, 'Dragon Arena');
  });
}
