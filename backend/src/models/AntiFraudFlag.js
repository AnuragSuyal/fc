const mongoose = require('mongoose');

const antiFraudEvidenceSchema = new mongoose.Schema({
    key: {
        type: String,
        required: true,
        trim: true
    },
    value: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    }
}, { _id: false });

const antiFraudFlagSchema = new mongoose.Schema({
    subjectType: {
        type: String,
        enum: ['user', 'match', 'pair', 'ip', 'device', 'wallet'],
        required: true,
        index: true
    },
    subjectId: {
        type: String,
        required: true,
        index: true
    },
    matchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        default: null
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        default: null
    },
    seasonId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashSeason',
        default: null
    },
    userIds: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    ipHash: {
        type: String,
        default: null
    },
    deviceHash: {
        type: String,
        default: null
    },
    flagType: {
        type: String,
        enum: [
            'repeated_pairing',
            'same_ip_pairing',
            'timeout_abuse',
            'surrender_abuse',
            'refund_abuse',
            'low_opponent_diversity',
            'wallet_cycle_anomaly'
        ],
        required: true,
        index: true
    },
    severity: {
        type: String,
        enum: ['low', 'medium', 'high', 'critical'],
        default: 'medium',
        index: true
    },
    score: {
        type: Number,
        default: 0
    },
    evidence: {
        type: [antiFraudEvidenceSchema],
        default: []
    },
    status: {
        type: String,
        enum: ['open', 'reviewing', 'suppressed', 'actioned', 'resolved'],
        default: 'open',
        index: true
    },
    autoAction: {
        type: String,
        enum: ['none', 'ranked_lock', 'stake_lock', 'manual_review'],
        default: 'none'
    }
}, {
    timestamps: true
});

antiFraudFlagSchema.index({ status: 1, severity: 1, createdAt: -1 });
antiFraudFlagSchema.index({ matchId: 1, createdAt: -1 });
antiFraudFlagSchema.index({ userIds: 1, createdAt: -1 });
antiFraudFlagSchema.index({ subjectType: 1, subjectId: 1, flagType: 1, status: 1, createdAt: -1 });

module.exports = mongoose.model('AntiFraudFlag', antiFraudFlagSchema);
