const mongoose = require('mongoose');

const coinTransferLedgerEntrySchema = new mongoose.Schema({
    transferId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'CoinTransfer',
        required: true,
        index: true
    },
    transferReferenceId: {
        type: String,
        required: true,
        index: true
    },
    ownerType: {
        type: String,
        enum: ['user', 'platform'],
        required: true,
        index: true
    },
    ownerUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null,
        index: true
    },
    ownerKey: {
        type: String,
        default: '',
        index: true
    },
    direction: {
        type: String,
        enum: ['debit', 'credit'],
        required: true
    },
    entryType: {
        type: String,
        enum: [
            'coin_transfer_sender_debit',
            'coin_transfer_receiver_credit',
            'coin_transfer_platform_fee',
            'coin_transfer_reverse_sender_credit',
            'coin_transfer_reverse_receiver_debit',
            'coin_transfer_reverse_platform_debit'
        ],
        required: true,
        index: true
    },
    amount: {
        type: Number,
        required: true,
        min: 0
    },
    balanceBefore: {
        type: Number,
        required: true
    },
    balanceAfter: {
        type: Number,
        required: true
    },
    currencyType: {
        type: String,
        enum: ['coins'],
        default: 'coins'
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    createdAt: {
        type: Date,
        default: Date.now,
        index: true
    }
});

coinTransferLedgerEntrySchema.index({ ownerUserId: 1, createdAt: -1 });
coinTransferLedgerEntrySchema.index({ ownerType: 1, ownerKey: 1, createdAt: -1 });

module.exports = mongoose.model('CoinTransferLedgerEntry', coinTransferLedgerEntrySchema);
