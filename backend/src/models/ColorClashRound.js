const mongoose = require('mongoose');

const colorClashRoundSchema = new mongoose.Schema({
    matchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        required: true,
        index: true
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true,
        index: true
    },
    roundNumber: {
        type: Number,
        required: true
    },
    status: {
        type: String,
        enum: ['preparing', 'active', 'ended', 'cancelled'],
        default: 'active'
    },
    publicStartState: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    publicEndState: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    startedAt: {
        type: Date,
        default: Date.now
    },
    endedAt: Date,
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

colorClashRoundSchema.pre('save', function preSave() {
    this.updatedAt = new Date();
});

colorClashRoundSchema.index({ matchId: 1, roundNumber: 1 }, { unique: true });

module.exports = mongoose.model('ColorClashRound', colorClashRoundSchema);
