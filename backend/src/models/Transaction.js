const mongoose = require('mongoose');

const transactionSchema = new mongoose.Schema({
    transactionId: {
        type: String,
        unique: true
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    type: {
        type: String,
        enum: [
            'purchase', 'purchase_coins', 'purchase_gems', 'gift_sent',
            'gift_received', 'entry_fee', 'tip', 'withdrawal',
            'refund', 'quest_reward', 'daily_bonus', 'vip_purchase',
            'treasure_claim', 'room_earnings', 'conversion', 'room_entry',
            'game_escrow_hold', 'game_escrow_refund', 'game_payout',
            'game_rank_reward', 'game_theme_purchase'
        ],
        required: true
    },
    amount: {
        coins: { type: Number, default: 0 },
        gems: { type: Number, default: 0 },
        realMoney: { type: Number, default: 0 }
    },
    balanceBefore: {
        coins: { type: Number, default: 0 },
        gems: { type: Number, default: 0 }
    },
    balanceAfter: {
        coins: { type: Number, default: 0 },
        gems: { type: Number, default: 0 }
    },
    reference: {
        giftId: { type: mongoose.Schema.Types.ObjectId, ref: 'Gift' },
        roomId: { type: mongoose.Schema.Types.ObjectId, ref: 'Room' },
        matchId: { type: mongoose.Schema.Types.ObjectId, ref: 'ColorClashMatch' },
        escrowId: { type: mongoose.Schema.Types.ObjectId, ref: 'WalletEscrow' },
        seasonId: { type: mongoose.Schema.Types.ObjectId, ref: 'ColorClashSeason' },
        recipientId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        senderId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        productId: String,
        stripeSessionId: String,
        gameId: String,
        tableMode: String
    },
    idempotencyKey: {
        type: String,
        index: true
    },
    paymentMethod: {
        type: String,
        enum: ['stripe', 'apple', 'google', 'paypal', 'gift', 'system', 'mock']
    },
    status: {
        type: String,
        enum: ['pending', 'completed', 'failed', 'refunded'],
        default: 'pending'
    },
    description: String,
    createdAt: {
        type: Date,
        default: Date.now
    },
    completedAt: Date
});

// Generate transactionId only when saving
transactionSchema.pre('save', async function () {
    if (!this.transactionId) {
        this.transactionId = 'TXN' + Date.now() + Math.floor(Math.random() * 10000);
    }
});

transactionSchema.index({ type: 1 });
transactionSchema.index({ 'reference.senderId': 1 });
transactionSchema.index({ 'reference.recipientId': 1 });
transactionSchema.index({ 'reference.roomId': 1 });
transactionSchema.index({ 'reference.matchId': 1 });
transactionSchema.index({ 'reference.escrowId': 1 });
transactionSchema.index({ 'reference.seasonId': 1 });
transactionSchema.index({ 'reference.gameId': 1, 'reference.tableMode': 1 });
transactionSchema.index({ createdAt: -1 });
transactionSchema.index(
    { userId: 1, idempotencyKey: 1 },
    { unique: true, partialFilterExpression: { idempotencyKey: { $exists: true } } }
);

module.exports = mongoose.model('Transaction', transactionSchema);





