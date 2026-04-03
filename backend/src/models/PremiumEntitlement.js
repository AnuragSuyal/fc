const mongoose = require('mongoose');

const premiumEntitlementSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    entitlementKey: {
        type: String,
        required: true,
        index: true
    },
    purchaseSource: {
        type: String,
        default: 'system'
    },
    purchaseAmountInr: {
        type: Number,
        default: 0
    },
    currency: {
        type: String,
        default: 'INR'
    },
    status: {
        type: String,
        enum: ['active', 'refunded', 'revoked', 'expired'],
        default: 'active',
        index: true
    },
    purchasedAt: {
        type: Date,
        default: Date.now
    },
    revokedAt: {
        type: Date,
        default: null
    },
    expiresAt: {
        type: Date,
        default: null
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

premiumEntitlementSchema.index(
    { userId: 1, entitlementKey: 1 },
    { unique: true }
);
premiumEntitlementSchema.index({ entitlementKey: 1, status: 1, updatedAt: -1 });

module.exports = mongoose.model('PremiumEntitlement', premiumEntitlementSchema);
