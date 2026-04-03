const mongoose = require('mongoose');

const roomDragonEventSchema = new mongoose.Schema({
    eventReferenceId: {
        type: String,
        unique: true,
        index: true
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true,
        index: true
    },
    activatorUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    purchaseInventoryId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'DragonPacketInventory',
        required: true,
        index: true
    },
    productSku: {
        type: String,
        required: true
    },
    packageType: {
        type: String,
        default: 'custom'
    },
    packetTotalCoins: {
        type: Number,
        required: true,
        min: 1
    },
    eventStatus: {
        type: String,
        enum: ['scheduled', 'live', 'settling', 'settled', 'cancelled', 'no_claim', 'refunded'],
        default: 'live',
        index: true
    },
    startsAt: {
        type: Date,
        required: true,
        index: true
    },
    endsAt: {
        type: Date,
        required: true,
        index: true
    },
    joinCutoffAt: {
        type: Date,
        default: null
    },
    settledAt: {
        type: Date,
        default: null
    },
    totalValidClaimants: {
        type: Number,
        default: 0
    },
    totalDistributed: {
        type: Number,
        default: 0
    },
    totalRefunded: {
        type: Number,
        default: 0
    },
    settlementAttemptCount: {
        type: Number,
        default: 0
    },
    requestMetadata: {
        ip: { type: String, default: '' },
        forwardedFor: { type: String, default: '' },
        userAgent: { type: String, default: '' },
        deviceId: { type: String, default: '' },
        sessionId: { type: String, default: '' }
    },
    configSnapshot: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    resultSummary: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

roomDragonEventSchema.pre('save', function generateReferenceId() {
    if (!this.eventReferenceId) {
        this.eventReferenceId = `DRE${Date.now()}${Math.floor(Math.random() * 10000)}`;
    }
});

roomDragonEventSchema.index({ roomId: 1, eventStatus: 1, startsAt: -1 });
roomDragonEventSchema.index({ activatorUserId: 1, createdAt: -1 });

module.exports = mongoose.model('RoomDragonEvent', roomDragonEventSchema);
