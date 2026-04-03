const mongoose = require('mongoose');

const dragonClaimParticipantSchema = new mongoose.Schema({
    eventId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'RoomDragonEvent',
        required: true,
        index: true
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true,
        index: true
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    joinedRoomAtSnapshot: {
        type: Date,
        default: null
    },
    firstTapAt: {
        type: Date,
        default: null
    },
    lastTapAt: {
        type: Date,
        default: null
    },
    acceptedTapCount: {
        type: Number,
        default: 0
    },
    rawTapCount: {
        type: Number,
        default: 0
    },
    computedScore: {
        type: Number,
        default: 0
    },
    eligibilityStatus: {
        type: String,
        enum: ['pending', 'eligible', 'rejected', 'flagged', 'throttled'],
        default: 'pending',
        index: true
    },
    fraudFlags: {
        type: [String],
        default: []
    },
    finalCoinReward: {
        type: Number,
        default: 0
    },
    finalRank: {
        type: Number,
        default: 0
    },
    payoutStatus: {
        type: String,
        enum: ['pending', 'paid', 'skipped', 'refunded'],
        default: 'pending'
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

dragonClaimParticipantSchema.index({ eventId: 1, userId: 1 }, { unique: true });
dragonClaimParticipantSchema.index({ eventId: 1, computedScore: -1, acceptedTapCount: -1 });
dragonClaimParticipantSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('DragonClaimParticipant', dragonClaimParticipantSchema);
