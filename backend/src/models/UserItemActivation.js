const mongoose = require('mongoose');

const userItemActivationSchema = new mongoose.Schema({
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
    inventoryEntryId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'UserInventoryItem',
        default: null
    },
    startedAt: {
        type: Date,
        default: Date.now
    },
    expiresAt: {
        type: Date,
        default: null
    },
    status: {
        type: String,
        enum: ['active', 'expired', 'cancelled', 'consumed'],
        default: 'active'
    },
    sourceType: {
        type: String,
        default: 'inventory_use'
    },
    sourceReferenceId: {
        type: String,
        default: ''
    },
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

userItemActivationSchema.index({ userId: 1, status: 1, expiresAt: 1 });
userItemActivationSchema.index({ userId: 1, itemId: 1, status: 1 });

userItemActivationSchema.pre('save', function () {
    this.updatedAt = new Date();
});

module.exports = mongoose.model('UserItemActivation', userItemActivationSchema);
