const {
    ROOM_UPDATE_EVENTS,
    emitRoomUpdate,
    populateRoomById
} = require('../services/roomSettingsService');
const {
    assertCanClearMiniDraw,
    assertCanManageMiniDraw,
    assertCanViewMiniDraw,
    buildMiniDrawSummary,
    buildMiniDrawSnapshot,
    clearCanvas,
    emitMiniDrawMeta,
    loadMiniDrawRoomForRestAction,
    redoLastStroke,
    unlockMiniDraw,
    undoLastStroke,
    updateMiniDrawSettings
} = require('../services/miniDrawService');

const emitBalanceUpdate = (io, userId, newBalance) => {
    if (!io || !userId || !newBalance) return;
    io.to(`user:${userId}`).emit('balance_update', {
        coins: Number(newBalance.coins || 0),
        gems: Number(newBalance.gems || 0)
    });
};

exports.getSnapshot = async (req, res, next) => {
    try {
        const room = await loadMiniDrawRoomForRestAction(req.params.id, req.userId);
        assertCanViewMiniDraw(room, req.userId);

        res.json({
            success: true,
            ...buildMiniDrawSnapshot(room, req.userId)
        });
    } catch (error) {
        next(error);
    }
};

exports.unlock = async (req, res, next) => {
    try {
        const result = await unlockMiniDraw({
            roomId: req.params.id,
            userId: req.userId,
            idempotencyKey: req.idempotencyKey
        });

        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(req.params.id);
        if (populatedRoom && io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SETTINGS,
                lobbyAction: 'mini_draw_unlocked',
                extraPayload: { miniDraw: result.summary }
            });
            emitMiniDrawMeta(io, populatedRoom, req.userId, 'unlock');
        }
        emitBalanceUpdate(io, req.userId, result.newBalance);

        res.json({
            success: true,
            duplicate: result.duplicate,
            chargedCoins: result.chargedCoins,
            summary: result.summary,
            newBalance: result.newBalance,
            transactionId: result.transactionId
        });
    } catch (error) {
        next(error);
    }
};

exports.updateSettings = async (req, res, next) => {
    try {
        const room = await loadMiniDrawRoomForRestAction(req.params.id, req.userId);
        assertCanManageMiniDraw(room, req.userId);

        const result = await updateMiniDrawSettings({
            room,
            actorUserId: req.userId,
            viewerUserId: req.userId,
            enabled: req.body.enabled,
            accessPolicy: req.body.accessPolicy
        });

        const io = req.app.get('io');
        const populatedRoom = await populateRoomById(req.params.id);
        if (populatedRoom && io) {
            emitRoomUpdate(io, populatedRoom, {
                updateEvent: ROOM_UPDATE_EVENTS.SETTINGS,
                lobbyAction: 'mini_draw_updated',
                extraPayload: { miniDraw: result.summary }
            });
            emitMiniDrawMeta(io, populatedRoom, req.userId, 'settings');
        }

        res.json({
            success: true,
            summary: result.summary
        });
    } catch (error) {
        next(error);
    }
};

exports.clear = async (req, res, next) => {
    try {
        const room = await loadMiniDrawRoomForRestAction(req.params.id, req.userId);
        assertCanClearMiniDraw(room, req.userId);

        const result = await clearCanvas({
            room,
            actorUserId: req.userId,
            viewerUserId: req.userId
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:draw:clear', {
                roomId: room._id.toString(),
                sessionId: result.summary.sessionId,
                clearedByUserId: req.userId,
                summary: buildMiniDrawSummary(room, null)
            });
        }

        res.json({
            success: true,
            summary: result.summary
        });
    } catch (error) {
        next(error);
    }
};

exports.undo = async (req, res, next) => {
    try {
        const room = await loadMiniDrawRoomForRestAction(req.params.id, req.userId);
        const result = await undoLastStroke({
            room,
            actorUserId: req.userId,
            viewerUserId: req.userId
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:draw:undo', {
                roomId: room._id.toString(),
                sessionId: result.summary.sessionId,
                strokeId: result.strokeId,
                userId: req.userId,
                summary: buildMiniDrawSummary(room, null)
            });
        }

        res.json({
            success: true,
            strokeId: result.strokeId,
            summary: result.summary
        });
    } catch (error) {
        next(error);
    }
};

exports.redo = async (req, res, next) => {
    try {
        const room = await loadMiniDrawRoomForRestAction(req.params.id, req.userId);
        const result = await redoLastStroke({
            room,
            actorUserId: req.userId,
            viewerUserId: req.userId
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`room:${room._id}`).emit('room:draw:redo', {
                roomId: room._id.toString(),
                sessionId: result.summary.sessionId,
                strokeId: result.strokeId,
                userId: req.userId,
                summary: buildMiniDrawSummary(room, null)
            });
        }

        res.json({
            success: true,
            strokeId: result.strokeId,
            summary: result.summary
        });
    } catch (error) {
        next(error);
    }
};
