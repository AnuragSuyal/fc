const mongoose = require('mongoose');

const xpLogSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    sourceType: {
        type: String,
        required: true,
        trim: true,
        index: true
    },
    amount: {
        type: Number,
        required: true,
        min: 0
    },
    sourceReferenceId: {
        type: String,
        default: ''
    },
    sourceReferenceType: {
        type: String,
        default: ''
    },
    dedupeKey: {
        type: String,
        trim: true,
        sparse: true
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    previousLevel: {
        type: Number,
        default: 1
    },
    newLevel: {
        type: Number,
        default: 1
    },
    awardedTier: {
        type: String,
        default: 'default'
    },
    leveledUp: {
        type: Boolean,
        default: false
    },
    tierChanged: {
        type: Boolean,
        default: false
    }
}, {
    timestamps: true
});

xpLogSchema.index(
    { userId: 1, sourceType: 1, dedupeKey: 1 },
    {
        unique: true,
        partialFilterExpression: {
            dedupeKey: { $exists: true, $type: 'string', $ne: '' }
        }
    }
);
xpLogSchema.index({ userId: 1, sourceType: 1, createdAt: -1 });

module.exports = mongoose.models.XpLog || mongoose.model('XpLog', xpLogSchema);
