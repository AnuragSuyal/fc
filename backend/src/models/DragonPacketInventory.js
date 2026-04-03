const mongoose = require('mongoose');

const dragonPacketInventorySchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    productSku: {
        type: String,
        required: true,
        index: true
    },
    packageType: {
        type: String,
        default: 'custom'
    },
    packetCoinAmount: {
        type: Number,
        required: true,
        min: 1
    },
    purchasePriceInr: {
        type: Number,
        required: true,
        min: 0
    },
    currency: {
        type: String,
        default: 'INR'
    },
    purchaseSource: {
        type: String,
        enum: ['stripe', 'mock', 'apple', 'google', 'restored', 'system'],
        default: 'stripe'
    },
    purchaseStatus: {
        type: String,
        enum: ['pending', 'completed', 'failed', 'cancelled', 'refunded', 'revoked'],
        default: 'completed',
        index: true
    },
    inventoryStatus: {
        type: String,
        enum: ['available', 'reserved', 'consumed', 'refunded', 'revoked'],
        default: 'available',
        index: true
    },
    purchasedAt: {
        type: Date,
        default: Date.now
    },
    reservedAt: {
        type: Date,
        default: null
    },
    consumedAt: {
        type: Date,
        default: null
    },
    refundedAt: {
        type: Date,
        default: null
    },
    revokedAt: {
        type: Date,
        default: null
    },
    linkedEventId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'RoomDragonEvent',
        default: null,
        index: true
    },
    paymentReference: {
        stripeSessionId: {
            type: String,
            default: ''
        },
        paymentIntentId: {
            type: String,
            default: '',
            index: true
        },
        chargeId: {
            type: String,
            default: ''
        },
        checkoutSessionId: {
            type: String,
            default: ''
        },
        externalReference: {
            type: String,
            default: ''
        }
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

dragonPacketInventorySchema.index({ userId: 1, inventoryStatus: 1, productSku: 1, purchasedAt: -1 });
dragonPacketInventorySchema.index({ purchaseStatus: 1, inventoryStatus: 1, purchasedAt: -1 });

module.exports = mongoose.model('DragonPacketInventory', dragonPacketInventorySchema);
