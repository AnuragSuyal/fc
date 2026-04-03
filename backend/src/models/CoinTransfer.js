const mongoose = require('mongoose');

const snapshotSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    uid: {
        type: String,
        default: ''
    },
    username: {
        type: String,
        default: ''
    },
    avatar: {
        type: String,
        default: ''
    }
}, { _id: false });

const requestMetadataSchema = new mongoose.Schema({
    ip: {
        type: String,
        default: ''
    },
    forwardedFor: {
        type: String,
        default: ''
    },
    userAgent: {
        type: String,
        default: ''
    },
    deviceId: {
        type: String,
        default: ''
    },
    sessionId: {
        type: String,
        default: ''
    }
}, { _id: false });

const coinTransferSchema = new mongoose.Schema({
    transferReferenceId: {
        type: String,
        unique: true,
        index: true
    },
    idempotencyKey: {
        type: String,
        default: null
    },
    senderUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    receiverUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    senderSnapshot: {
        type: snapshotSchema,
        default: () => ({})
    },
    receiverSnapshot: {
        type: snapshotSchema,
        default: () => ({})
    },
    chatId: {
        type: String,
        required: true,
        index: true
    },
    grossAmount: {
        type: Number,
        required: true,
        min: 1
    },
    receiverAmount: {
        type: Number,
        required: true,
        min: 0
    },
    platformFee: {
        type: Number,
        required: true,
        min: 0
    },
    receiverPercentageSnapshot: {
        type: Number,
        required: true
    },
    platformPercentageSnapshot: {
        type: Number,
        required: true
    },
    status: {
        type: String,
        enum: ['pending', 'completed', 'failed', 'reversed', 'flagged'],
        default: 'pending',
        index: true
    },
    failureReason: {
        type: String,
        default: ''
    },
    requestMetadata: {
        type: requestMetadataSchema,
        default: () => ({})
    },
    riskFlags: {
        type: [String],
        default: []
    },
    adminNotes: {
        type: String,
        default: ''
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    completedAt: {
        type: Date,
        default: null
    },
    failedAt: {
        type: Date,
        default: null
    },
    reversedAt: {
        type: Date,
        default: null
    }
}, {
    timestamps: {
        createdAt: 'createdAt',
        updatedAt: 'updatedAt'
    }
});

coinTransferSchema.pre('save', function preSave() {
    if (!this.transferReferenceId) {
        this.transferReferenceId = `CTR${Date.now()}${Math.floor(Math.random() * 10000)}`;
    }
});

coinTransferSchema.index({ senderUserId: 1, createdAt: -1 });
coinTransferSchema.index({ receiverUserId: 1, createdAt: -1 });
coinTransferSchema.index({ chatId: 1, createdAt: -1 });
coinTransferSchema.index({ senderUserId: 1, receiverUserId: 1, createdAt: -1 });
coinTransferSchema.index(
    { senderUserId: 1, idempotencyKey: 1 },
    { unique: true, partialFilterExpression: { idempotencyKey: { $exists: true, $type: 'string' } } }
);

module.exports = mongoose.model('CoinTransfer', coinTransferSchema);
