const mongoose = require('mongoose');

const dragonEventRiskLogSchema = new mongoose.Schema({
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
        default: null,
        index: true
    },
    signalType: {
        type: String,
        required: true,
        index: true
    },
    signalValue: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    actionTaken: {
        type: String,
        default: 'logged'
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

dragonEventRiskLogSchema.index({ eventId: 1, signalType: 1, createdAt: -1 });

module.exports = mongoose.model('DragonEventRiskLog', dragonEventRiskLogSchema);
