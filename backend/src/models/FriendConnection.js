const mongoose = require('mongoose');

const friendConnectionSchema = new mongoose.Schema({
    pairKey: {
        type: String,
        required: true,
        unique: true,
        index: true
    },
    userAId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    userBId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    connectedAt: {
        type: Date,
        default: Date.now,
        index: true
    },
    disconnectedAt: {
        type: Date,
        default: null
    },
    source: {
        type: String,
        default: 'friend_request_accept'
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

friendConnectionSchema.index({ userAId: 1, connectedAt: -1 });
friendConnectionSchema.index({ userBId: 1, connectedAt: -1 });

module.exports = mongoose.model('FriendConnection', friendConnectionSchema);
