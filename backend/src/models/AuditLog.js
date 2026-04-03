const mongoose = require('mongoose');

const auditLogSchema = new mongoose.Schema({
    entityType: {
        type: String,
        required: true,
        enum: ['room', 'match', 'round', 'move', 'escrow', 'season', 'rank_progress', 'fraud_flag', 'user', 'coin_transfer', 'dragon_event', 'dragon_packet']
    },
    entityId: {
        type: mongoose.Schema.Types.Mixed,
        required: true
    },
    action: {
        type: String,
        required: true
    },
    actorType: {
        type: String,
        enum: ['system', 'user', 'service'],
        default: 'system'
    },
    actorId: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    requestId: {
        type: String,
        default: null
    },
    idempotencyKey: {
        type: String,
        default: null
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        default: null
    },
    matchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        default: null
    },
    before: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    after: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    meta: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

auditLogSchema.index({ entityType: 1, entityId: 1, createdAt: -1 });
auditLogSchema.index({ matchId: 1, createdAt: -1 });
auditLogSchema.index({ userId: 1, createdAt: -1 });

module.exports = mongoose.model('AuditLog', auditLogSchema);
