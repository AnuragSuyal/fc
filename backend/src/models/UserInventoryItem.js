const mongoose = require('mongoose');

const userInventoryItemSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    itemId: {
        type: String,
        required: true,
        index: true
    },
    quantity: {
        type: Number,
        default: 1,
        min: 0
    },
    acquiredAt: {
        type: Date,
        default: Date.now
    },
    expiryAt: {
        type: Date,
        default: null
    },
    isEquipped: {
        type: Boolean,
        default: false
    },
    isActive: {
        type: Boolean,
        default: false
    },
    favorited: {
        type: Boolean,
        default: false
    },
    sourceType: {
        type: String,
        default: 'shop_purchase'
    },
    sourceReferenceId: {
        type: String,
        default: ''
    },
    lastUsedAt: {
        type: Date,
        default: null
    },
    usageCount: {
        type: Number,
        default: 0
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

userInventoryItemSchema.index({ userId: 1, itemId: 1 }, { unique: true });
userInventoryItemSchema.index({ userId: 1, isEquipped: 1 });
userInventoryItemSchema.index({ userId: 1, isActive: 1 });
userInventoryItemSchema.index({ expiryAt: 1 });

userInventoryItemSchema.pre('save', function () {
    this.updatedAt = new Date();
});

module.exports = mongoose.model('UserInventoryItem', userInventoryItemSchema);
