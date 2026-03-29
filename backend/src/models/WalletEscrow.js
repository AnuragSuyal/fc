const mongoose = require('mongoose');

const walletEscrowSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true
    },
    matchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        required: true
    },
    seasonId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashSeason',
        default: null
    },
    currency: {
        type: String,
        enum: ['coins'],
        default: 'coins'
    },
    amount: {
        type: Number,
        required: true,
        min: 0
    },
    status: {
        type: String,
        enum: ['held', 'locked', 'settled', 'refunded', 'cancelled', 'expired'],
        default: 'held'
    },
    reason: {
        type: String,
        enum: ['stake_entry', 'ranked_entry', 'friend_stake', 'queue_stake'],
        default: 'stake_entry'
    },
    idempotencyKey: {
        type: String,
        required: true
    },
    holdTransactionId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Transaction',
        default: null
    },
    payoutTransactionIds: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Transaction'
    }],
    refundTransactionId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Transaction',
        default: null
    },
    settlementKey: {
        type: String,
        default: null
    },
    feeBreakdown: {
        houseFee: {
            type: Number,
            default: 0
        },
        sinkFee: {
            type: Number,
            default: 0
        },
        payout: {
            type: Number,
            default: 0
        }
    },
    balanceBefore: {
        type: Number,
        default: 0
    },
    balanceAfterHold: {
        type: Number,
        default: 0
    },
    heldAt: Date,
    lockedAt: Date,
    settledAt: Date,
    refundedAt: Date,
    expiresAt: Date
}, {
    timestamps: true
});

walletEscrowSchema.index(
    { matchId: 1, userId: 1 },
    { unique: true }
);
walletEscrowSchema.index(
    { userId: 1, idempotencyKey: 1 },
    { unique: true }
);
walletEscrowSchema.index({ status: 1, expiresAt: 1 });

module.exports = mongoose.model('WalletEscrow', walletEscrowSchema);
