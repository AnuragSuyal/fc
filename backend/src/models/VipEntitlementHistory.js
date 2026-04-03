const mongoose = require('mongoose');

const vipEntitlementHistorySchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    oldTier: {
        type: String,
        default: ''
    },
    newTier: {
        type: String,
        default: ''
    },
    oldStatus: {
        type: String,
        default: ''
    },
    newStatus: {
        type: String,
        default: ''
    },
    changedAt: {
        type: Date,
        default: Date.now
    },
    source: {
        type: String,
        default: 'system'
    },
    transactionReference: {
        type: String,
        default: ''
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
});

vipEntitlementHistorySchema.index({ userId: 1, changedAt: -1 });

module.exports = mongoose.model('VipEntitlementHistory', vipEntitlementHistorySchema);
