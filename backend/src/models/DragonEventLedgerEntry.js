const mongoose = require('mongoose');

const dragonEventLedgerEntrySchema = new mongoose.Schema({
    eventId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'RoomDragonEvent',
        required: true,
        index: true
    },
    entryType: {
        type: String,
        enum: ['winner_credit', 'inventory_consumed', 'inventory_restored', 'purchase_grant', 'manual_adjustment'],
        required: true,
        index: true
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null,
        index: true
    },
    walletOwnerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    amount: {
        type: Number,
        required: true
    },
    balanceBefore: {
        type: Number,
        default: null
    },
    balanceAfter: {
        type: Number,
        default: null
    },
    referenceType: {
        type: String,
        default: ''
    },
    referenceId: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    notes: {
        type: String,
        default: ''
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

dragonEventLedgerEntrySchema.index({ eventId: 1, createdAt: 1 });
dragonEventLedgerEntrySchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('DragonEventLedgerEntry', dragonEventLedgerEntrySchema);
