const mongoose = require('mongoose');

const colorClashMoveSchema = new mongoose.Schema({
    matchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        required: true,
        index: true
    },
    roundId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashRound',
        required: true,
        index: true
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true,
        index: true
    },
    sequence: {
        type: Number,
        required: true
    },
    versionBefore: {
        type: Number,
        required: true
    },
    versionAfter: {
        type: Number,
        required: true
    },
    actorUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    actorSeat: {
        type: Number,
        required: true
    },
    clientMoveId: {
        type: String,
        required: true
    },
    moveType: {
        type: String,
        required: true
    },
    status: {
        type: String,
        enum: ['accepted', 'rejected', 'auto_applied'],
        default: 'accepted'
    },
    payload: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    publicPatch: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    reasonCode: String,
    createdAt: {
        type: Date,
        default: Date.now
    }
});

colorClashMoveSchema.index({ matchId: 1, sequence: 1 }, { unique: true });
colorClashMoveSchema.index({ matchId: 1, actorUserId: 1, clientMoveId: 1 }, { unique: true });

module.exports = mongoose.model('ColorClashMove', colorClashMoveSchema);
