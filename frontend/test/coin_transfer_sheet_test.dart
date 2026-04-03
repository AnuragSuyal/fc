import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/coin_transfer_model.dart';
import 'package:frontend/widgets/coin_transfer/coin_transfer_sheet.dart';

void main() {
  CoinTransferEligibility buildEligibility() {
    return CoinTransferEligibility(
      unlocked: true,
      entitlement: null,
      featureEnabled: true,
      canPurchaseUnlock: true,
      eligibleAfterUnlock: true,
      canSend: true,
      currentBalance: 1000,
      chatId: 'dm:alpha:beta',
      receiver: const CoinTransferPeer(
        id: 'receiver_1',
        uid: 'u200',
        username: 'Rahul',
        avatar: '',
      ),
      reasons: const <CoinTransferReason>[],
      limits: const CoinTransferLimits(
        featureEnabled: true,
        unlockPriceInr: 599,
        unlockCurrency: 'INR',
        minTransferAmount: 100,
        maxTransferPerTxn: 100000,
        dailySendLimitAmount: 50000,
        dailySendLimitCount: 20,
        monthlySendLimitAmount: 300000,
        monthlySendLimitCount: 200,
        cooldownSecondsBetweenTransfers: 30,
        maxUniqueReceiversPerDay: 10,
        maxReceivedFromSameSenderPerDay: 50000,
        accountAgeMinDaysForTransfer: 7,
        minFriendshipAgeHours: 24,
        minChatMessagesExchanged: 0,
        requireVerifiedAccount: false,
        feePercentages: CoinTransferFeePercentages(
          receiverPercentage: 70,
          platformPercentage: 30,
        ),
      ),
      usage: const CoinTransferUsage(
        daily: CoinTransferWindowUsage(
          amountUsed: 0,
          amountRemaining: 50000,
          countUsed: 0,
          countRemaining: 20,
        ),
        monthly: CoinTransferWindowUsage(
          amountUsed: 0,
          amountRemaining: 300000,
          countUsed: 0,
          countRemaining: 200,
        ),
        uniqueReceiversToday: 0,
        uniqueReceiversRemainingToday: 10,
        sameSenderToReceiverAmountToday: 0,
        sameSenderToReceiverAmountRemainingToday: 50000,
        cooldownSecondsRemaining: 0,
        friendshipConnectedAt: null,
        bilateralRecentCount: 0,
      ),
      preview: null,
    );
  }

  CoinTransferPreview buildPreview(int amount) {
    final breakdown = CoinTransferBreakdown.calculate(
      amount: amount,
      feePercentages: const CoinTransferFeePercentages(
        receiverPercentage: 70,
        platformPercentage: 30,
      ),
    );
    final reasons = amount < 100
        ? const <CoinTransferReason>[
            CoinTransferReason(
              code: 'MIN_AMOUNT_NOT_MET',
              message: 'Minimum transfer amount is 100 coins.',
            ),
          ]
        : const <CoinTransferReason>[];
    return CoinTransferPreview(
      eligibility: buildEligibility(),
      validation: CoinTransferValidation(
        canSend: amount >= 100,
        reasons: reasons,
      ),
      breakdown: breakdown,
    );
  }

  CoinTransferSendResult buildSendResult(int amount) {
    final breakdown = CoinTransferBreakdown.calculate(
      amount: amount,
      feePercentages: const CoinTransferFeePercentages(
        receiverPercentage: 70,
        platformPercentage: 30,
      ),
    );
    return CoinTransferSendResult(
      success: true,
      duplicate: false,
      transfer: CoinTransferRecord(
        id: 'transfer_1',
        transferReferenceId: 'CTR001',
        chatId: 'dm:alpha:beta',
        senderUserId: 'sender_1',
        receiverUserId: 'receiver_1',
        direction: 'sent',
        grossAmount: amount,
        receiverAmount: breakdown.receiverAmount,
        platformFee: breakdown.platformFee,
        status: 'completed',
        failureReason: '',
        createdAt: DateTime(2026, 1, 1, 12),
        completedAt: DateTime(2026, 1, 1, 12, 0, 1),
        feePercentages: breakdown.feePercentages,
        peer: const CoinTransferPeer(
          id: 'receiver_1',
          uid: 'u200',
          username: 'Rahul',
          avatar: '',
        ),
        message: 'You sent coins',
      ),
      transactionId: 'TXN001',
      newBalance: const CoinTransferBalanceSnapshot(
        coins: 750,
        gems: 0,
        vipLevel: 0,
      ),
      receiverBalance: const CoinTransferBalanceSnapshot(
        coins: 175,
        gems: 0,
        vipLevel: 0,
      ),
      messageJson: const <String, dynamic>{},
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('coin transfer sheet shows live preview updates', (tester) async {
    await tester.pumpWidget(
      wrap(
        CoinTransferComposerSheet(
          eligibility: buildEligibility(),
          receiverName: 'Rahul',
          onPreview: (amount) async => buildPreview(amount),
          onSubmit: (amount) async => buildSendResult(amount),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('Send Coins'), findsNWidgets(2));
    expect(find.text('70'), findsWidgets);
    expect(find.text('30'), findsWidgets);

    await tester.tap(find.text('250'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('175'), findsOneWidget);
    expect(find.text('75'), findsOneWidget);
  });

  testWidgets('coin transfer sheet blocks invalid amounts under minimum',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        CoinTransferComposerSheet(
          eligibility: buildEligibility(),
          receiverName: 'Rahul',
          onPreview: (amount) async => buildPreview(amount),
          onSubmit: (amount) async => buildSendResult(amount),
        ),
      ),
    );

    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Custom amount'),
      '99',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.text('Minimum transfer amount is 100 coins.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send Coins'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('coin transfer sheet submits the selected amount',
      (tester) async {
    var submittedAmount = 0;

    await tester.pumpWidget(
      wrap(
        CoinTransferComposerSheet(
          eligibility: buildEligibility(),
          receiverName: 'Rahul',
          onPreview: (amount) async => buildPreview(amount),
          onSubmit: (amount) async {
            submittedAmount = amount;
            return buildSendResult(amount);
          },
        ),
      ),
    );

    await tester.tap(find.text('250'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    final sendButton = find.widgetWithText(FilledButton, 'Send Coins');
    await tester.ensureVisible(sendButton);
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(submittedAmount, 250);
  });
}
