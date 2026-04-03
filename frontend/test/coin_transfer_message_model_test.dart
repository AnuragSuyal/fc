import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/message_model.dart';

void main() {
  test('message model parses coin transfer metadata for chat rendering', () {
    final message = MessageModel.fromJson({
      '_id': 'message_1',
      'senderId': {
        '_id': 'sender_1',
        'username': 'Anurag',
        'avatar': 'https://cdn.example.com/a.png',
      },
      'recipientId': 'receiver_1',
      'content': 'Anurag sent 500 coins to Rahul',
      'type': 'coin_transfer',
      'metadata': {
        'coinTransfer': {
          'transferId': 'transfer_1',
          'transferReferenceId': 'CTR001',
          'grossAmount': 500,
          'receiverAmount': 350,
          'platformFee': 150,
          'senderUserId': 'sender_1',
          'receiverUserId': 'receiver_1',
          'senderUsername': 'Anurag',
          'receiverUsername': 'Rahul',
          'status': 'completed',
        },
      },
      'createdAt': '2026-01-01T12:00:00.000Z',
      'updatedAt': '2026-01-01T12:00:00.000Z',
    });

    expect(message.isCoinTransfer, isTrue);
    expect(message.coinTransferGrossAmount, 500);
    expect(message.coinTransferReceiverAmount, 350);
    expect(message.coinTransferPlatformFee, 150);
    expect(message.coinTransferSenderUsername, 'Anurag');
    expect(message.coinTransferReceiverUsername, 'Rahul');
    expect(message.previewText, 'Coin transfer: 500 coins');
  });
}
