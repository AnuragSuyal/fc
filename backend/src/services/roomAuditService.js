const AuditLog = require('../models/AuditLog');

const logRoomAuditEvent = async ({
    roomId,
    actorId = null,
    actorRole = null,
    targetUserId = null,
    action,
    before = null,
    after = null,
    reason = null,
    source = 'rest',
    success = true,
    requestId = null,
    idempotencyKey = null
}) => {
    if (!roomId || !action) return null;

    return AuditLog.create({
        entityType: 'room',
        entityId: roomId,
        action,
        actorType: actorId ? 'user' : 'system',
        actorId,
        requestId,
        idempotencyKey,
        roomId,
        userId: targetUserId,
        before,
        after,
        meta: {
            actorRole,
            targetUserId,
            reason,
            source,
            success
        }
    });
};

module.exports = {
    logRoomAuditEvent
};
