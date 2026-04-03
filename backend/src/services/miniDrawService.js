const crypto = require('node:crypto');

const Room = require('../models/Room');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const {
    MINI_DRAW_ACCESS_POLICIES,
    getUserMiniDrawCapabilities,
    isRoomParticipant,
    normalizeMiniDrawAccessPolicy
} = require('./roomPermissionService');

const MINI_DRAW_UNLOCK_COST = 300;
const MINI_DRAW_MAX_STROKES = 240;
const MINI_DRAW_MAX_POINTS_PER_STROKE = 320;
const MINI_DRAW_MAX_POINTS_PER_EVENT = 24;
const MINI_DRAW_RATE_WINDOW_MS = 5000;
const MINI_DRAW_MAX_EVENTS_PER_WINDOW = 70;
const MINI_DRAW_MAX_POINTS_PER_WINDOW = 1400;

const pendingStrokesByRoom = new Map();
const drawRateWindowByUser = new Map();

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value === 'number') return String(value);
    if (typeof value?.toString === 'function') {
        const normalized = value.toString();
        if (normalized && normalized !== '[object Object]') {
            return normalized;
        }
    }
    return '';
};

const nowIso = () => new Date().toISOString();
const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

const buildSessionId = () => {
    if (typeof crypto.randomUUID === 'function') {
        return crypto.randomUUID();
    }
    return crypto.randomBytes(16).toString('hex');
};

const sanitizePointValue = (value) => {
    const number = Number(value);
    if (!Number.isFinite(number)) {
        return null;
    }
    return Number(clamp(number, 0, 1).toFixed(4));
};

const sanitizePoints = (points = [], limit = MINI_DRAW_MAX_POINTS_PER_STROKE) => {
    if (!Array.isArray(points)) return [];

    const sanitized = [];
    for (const point of points) {
        if (!point || typeof point !== 'object') continue;
        const x = sanitizePointValue(point.x);
        const y = sanitizePointValue(point.y);
        if (x == null || y == null) continue;
        sanitized.push({ x, y });
        if (sanitized.length >= limit) break;
    }

    return sanitized;
};

const sanitizeColorValue = (value) => {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return 0xFFFFFFFF;
    return clamp(Math.trunc(parsed), 0x00000000, 0xFFFFFFFF);
};

const sanitizeThickness = (value) => {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return 3;
    return Number(clamp(parsed, 1, 24).toFixed(2));
};

const sanitizeToolType = (value) => {
    const normalized = String(value || '').trim().toLowerCase();
    return normalized === 'eraser' ? 'eraser' : 'pen';
};

const getRoomPendingStrokes = (roomId) => {
    const normalizedRoomId = toIdString(roomId);
    if (!normalizedRoomId) return null;
    let roomPending = pendingStrokesByRoom.get(normalizedRoomId);
    if (!roomPending) {
        roomPending = new Map();
        pendingStrokesByRoom.set(normalizedRoomId, roomPending);
    }
    return roomPending;
};

const releaseRoomPendingMapIfEmpty = (roomId) => {
    const normalizedRoomId = toIdString(roomId);
    if (!normalizedRoomId) return;
    const roomPending = pendingStrokesByRoom.get(normalizedRoomId);
    if (roomPending && roomPending.size === 0) {
        pendingStrokesByRoom.delete(normalizedRoomId);
    }
};

const pruneRedoStackEntries = (session) => {
    session.redoStacks = (session.redoStacks || []).filter((entry) =>
        entry?.userId && Array.isArray(entry.strokeIds) && entry.strokeIds.length > 0
    );
};

const getRedoStackEntry = (session, userId, { create = false } = {}) => {
    const normalizedUserId = toIdString(userId);
    if (!normalizedUserId) return null;

    if (!Array.isArray(session.redoStacks)) {
        session.redoStacks = [];
    }

    let entry = session.redoStacks.find(
        (stackEntry) => toIdString(stackEntry?.userId) === normalizedUserId
    );
    if (!entry && create) {
        entry = {
            userId,
            strokeIds: [],
            updatedAt: new Date()
        };
        session.redoStacks.push(entry);
    }
    return entry || null;
};

const clearRedoStackForUser = (session, userId) => {
    const entry = getRedoStackEntry(session, userId);
    if (!entry) return;
    entry.strokeIds = [];
    entry.updatedAt = new Date();
    pruneRedoStackEntries(session);
};

const pushRedoStrokeId = (session, userId, strokeId) => {
    const entry = getRedoStackEntry(session, userId, { create: true });
    entry.strokeIds = (entry.strokeIds || []).filter((value) => value !== strokeId);
    entry.strokeIds.push(strokeId);
    if (entry.strokeIds.length > MINI_DRAW_MAX_STROKES) {
        entry.strokeIds = entry.strokeIds.slice(-MINI_DRAW_MAX_STROKES);
    }
    entry.updatedAt = new Date();
};

const popRedoStrokeId = (session, userId) => {
    const entry = getRedoStackEntry(session, userId);
    if (!entry || !Array.isArray(entry.strokeIds) || entry.strokeIds.length === 0) {
        return null;
    }
    const nextStrokeId = entry.strokeIds.pop() || null;
    entry.updatedAt = new Date();
    pruneRedoStackEntries(session);
    return nextStrokeId;
};

const ensureMiniDrawState = (room) => {
    if (!room.miniDraw || typeof room.miniDraw !== 'object') {
        room.miniDraw = {};
    }

    room.miniDraw.sessionId = toIdString(room.miniDraw.sessionId) || buildSessionId();
    room.miniDraw.isUnlocked = room.miniDraw.isUnlocked === true;
    room.miniDraw.unlockCostCoins = MINI_DRAW_UNLOCK_COST;
    room.miniDraw.enabled = room.miniDraw.enabled !== false;
    room.miniDraw.accessPolicy = normalizeMiniDrawAccessPolicy(room.miniDraw.accessPolicy);
    room.miniDraw.version = Number.isFinite(Number(room.miniDraw.version))
        ? Math.max(0, Math.trunc(Number(room.miniDraw.version)))
        : 0;
    room.miniDraw.updatedAt = room.miniDraw.updatedAt || new Date();
    room.miniDraw.strokes = Array.isArray(room.miniDraw.strokes) ? room.miniDraw.strokes : [];
    room.miniDraw.redoStacks = Array.isArray(room.miniDraw.redoStacks) ? room.miniDraw.redoStacks : [];

    for (const stroke of room.miniDraw.strokes) {
        stroke.strokeId = toIdString(stroke.strokeId) || buildSessionId();
        stroke.toolType = sanitizeToolType(stroke.toolType);
        stroke.colorValue = sanitizeColorValue(stroke.colorValue);
        stroke.thickness = sanitizeThickness(stroke.thickness);
        stroke.points = sanitizePoints(stroke.points);
        stroke.isVisible = stroke.isVisible !== false;
        stroke.createdAt = stroke.createdAt || new Date();
        stroke.updatedAt = stroke.updatedAt || stroke.createdAt;
        stroke.version = Number.isFinite(Number(stroke.version))
            ? Math.max(0, Math.trunc(Number(stroke.version)))
            : room.miniDraw.version;
    }

    pruneRedoStackEntries(room.miniDraw);
    return room.miniDraw;
};

const getVisibleStrokeCount = (room) =>
    ensureMiniDrawState(room).strokes.filter((stroke) => stroke.isVisible !== false).length;

const buildSummaryPermissions = (room, userId) => {
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    return {
        canUnlock: capabilities.canUnlock,
        canManage: capabilities.canManageMiniDraw,
        canView: capabilities.canViewMiniDraw,
        canDraw: capabilities.canDrawOnMiniDraw,
        canClear: capabilities.canClearMiniDraw,
        canUndoRedo: capabilities.canUndoRedoMiniDraw
    };
};

const buildMiniDrawSummary = (room, userId = null) => {
    const session = ensureMiniDrawState(room);
    return {
        sessionId: session.sessionId,
        roomId: toIdString(room._id),
        isUnlocked: session.isUnlocked === true,
        unlockCostCoins: MINI_DRAW_UNLOCK_COST,
        enabled: session.enabled !== false,
        accessPolicy: normalizeMiniDrawAccessPolicy(session.accessPolicy),
        unlockedBy: toIdString(session.unlockedByUserId),
        unlockedAt: session.unlockedAt ? new Date(session.unlockedAt).toISOString() : null,
        version: Math.max(0, Math.trunc(Number(session.version || 0))),
        strokeCount: getVisibleStrokeCount(room),
        lastClearedAt: session.lastClearedAt ? new Date(session.lastClearedAt).toISOString() : null,
        lastClearedBy: toIdString(session.lastClearedByUserId),
        updatedAt: session.updatedAt ? new Date(session.updatedAt).toISOString() : nowIso(),
        roomActive: room.roomActive !== false,
        permissions: buildSummaryPermissions(room, userId)
    };
};

const serializeStroke = (stroke) => ({
    strokeId: toIdString(stroke.strokeId),
    toolType: sanitizeToolType(stroke.toolType),
    colorValue: sanitizeColorValue(stroke.colorValue),
    thickness: sanitizeThickness(stroke.thickness),
    points: sanitizePoints(stroke.points),
    createdBy: toIdString(stroke.createdByUserId),
    createdAt: stroke.createdAt ? new Date(stroke.createdAt).toISOString() : nowIso(),
    updatedAt: stroke.updatedAt ? new Date(stroke.updatedAt).toISOString() : null,
    version: Number.isFinite(Number(stroke.version))
        ? Math.max(0, Math.trunc(Number(stroke.version)))
        : 0,
    isVisible: stroke.isVisible !== false
});

const buildMiniDrawSnapshot = (room, userId = null) => ({
    summary: buildMiniDrawSummary(room, userId),
    strokes: ensureMiniDrawState(room).strokes
        .filter((stroke) => stroke.isVisible !== false)
        .map(serializeStroke)
});

const touchSessionVersion = (session) => {
    session.version = Number.isFinite(Number(session.version))
        ? Math.max(0, Math.trunc(Number(session.version))) + 1
        : 1;
    session.updatedAt = new Date();
};

const trimStrokeHistory = (session) => {
    if (!Array.isArray(session.strokes) || session.strokes.length <= MINI_DRAW_MAX_STROKES) {
        return;
    }

    session.strokes = session.strokes.slice(-MINI_DRAW_MAX_STROKES);
    const preservedStrokeIds = new Set(session.strokes.map((stroke) => toIdString(stroke.strokeId)));
    for (const entry of session.redoStacks || []) {
        entry.strokeIds = (entry.strokeIds || []).filter((strokeId) => preservedStrokeIds.has(toIdString(strokeId)));
    }
    pruneRedoStackEntries(session);
};

const assertMiniDrawParticipant = (room, userId) => {
    if (!isRoomParticipant(room, userId)) {
        const error = new Error('Join the room before using Mini Draw');
        error.status = 403;
        throw error;
    }
};

const assertMiniDrawUnlocked = (room) => {
    const session = ensureMiniDrawState(room);
    if (!session.isUnlocked) {
        const error = new Error('Mini Draw is not unlocked for this room yet');
        error.status = 403;
        throw error;
    }
};

const assertCanUnlockMiniDraw = (room, userId) => {
    assertMiniDrawParticipant(room, userId);
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    if (capabilities.isUnlocked) return;
    if (!capabilities.canUnlock) {
        const error = new Error('Only the host can unlock Mini Draw for this room');
        error.status = 403;
        throw error;
    }
};

const assertCanManageMiniDraw = (room, userId) => {
    assertMiniDrawParticipant(room, userId);
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    if (!capabilities.canManageMiniDraw) {
        const error = new Error('Only the host can change Mini Draw access for this room');
        error.status = 403;
        throw error;
    }
};

const assertCanClearMiniDraw = (room, userId) => {
    assertMiniDrawParticipant(room, userId);
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    if (!capabilities.canClearMiniDraw) {
        const error = new Error('Only the host or an admin can clear the board');
        error.status = 403;
        throw error;
    }
};

const assertCanDrawMiniDraw = (room, userId) => {
    assertMiniDrawParticipant(room, userId);
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    if (!capabilities.canDrawOnMiniDraw) {
        const error = new Error('You do not have drawing access in this room right now');
        error.status = 403;
        throw error;
    }
};

const assertCanViewMiniDraw = (room, userId) => {
    assertMiniDrawParticipant(room, userId);
    const capabilities = getUserMiniDrawCapabilities(room, userId);
    if (!capabilities.canViewMiniDraw && !capabilities.canUnlock) {
        const error = new Error('Mini Draw is unavailable for you right now');
        error.status = 403;
        throw error;
    }
};

const consumeUserDrawQuota = ({ roomId, userId, pointCount = 0 }) => {
    const normalizedRoomId = toIdString(roomId);
    const normalizedUserId = toIdString(userId);
    if (!normalizedRoomId || !normalizedUserId) return false;

    const key = `${normalizedRoomId}:${normalizedUserId}`;
    const now = Date.now();
    const entry = drawRateWindowByUser.get(key) || {
        startedAt: now,
        events: 0,
        points: 0
    };

    if (now - entry.startedAt > MINI_DRAW_RATE_WINDOW_MS) {
        entry.startedAt = now;
        entry.events = 0;
        entry.points = 0;
    }

    entry.events += 1;
    entry.points += Math.max(0, Math.trunc(Number(pointCount) || 0));
    drawRateWindowByUser.set(key, entry);

    return (
        entry.events <= MINI_DRAW_MAX_EVENTS_PER_WINDOW &&
        entry.points <= MINI_DRAW_MAX_POINTS_PER_WINDOW
    );
};

const beginPendingStroke = ({
    room,
    socketId,
    userId,
    strokeId,
    toolType,
    colorValue,
    thickness,
    points
}) => {
    assertCanDrawMiniDraw(room, userId);
    assertMiniDrawUnlocked(room);

    const session = ensureMiniDrawState(room);
    const normalizedStrokeId = toIdString(strokeId);
    if (!normalizedStrokeId) {
        const error = new Error('Stroke id required');
        error.status = 400;
        throw error;
    }

    const sanitizedPoints = sanitizePoints(points, MINI_DRAW_MAX_POINTS_PER_EVENT);
    if (sanitizedPoints.length === 0) {
        const error = new Error('A stroke needs at least one valid point');
        error.status = 400;
        throw error;
    }

    if (!consumeUserDrawQuota({
        roomId: room._id,
        userId,
        pointCount: sanitizedPoints.length
    })) {
        const error = new Error('Mini Draw is receiving too many points from this user');
        error.status = 429;
        error.code = 'MINI_DRAW_RATE_LIMITED';
        throw error;
    }

    const roomPending = getRoomPendingStrokes(room?._id || roomId);
    const pendingStroke = {
        roomId: toIdString(room._id),
        sessionId: session.sessionId,
        strokeId: normalizedStrokeId,
        userId: toIdString(userId),
        socketId,
        toolType: sanitizeToolType(toolType),
        colorValue: sanitizeColorValue(colorValue),
        thickness: sanitizeThickness(thickness),
        points: sanitizedPoints,
        createdAt: new Date()
    };

    roomPending.set(normalizedStrokeId, pendingStroke);

    return {
        roomId: pendingStroke.roomId,
        sessionId: pendingStroke.sessionId,
        strokeId: pendingStroke.strokeId,
        userId: pendingStroke.userId,
        toolType: pendingStroke.toolType,
        colorValue: pendingStroke.colorValue,
        thickness: pendingStroke.thickness,
        points: pendingStroke.points,
        createdAt: pendingStroke.createdAt.toISOString(),
        isStart: true
    };
};

const appendPendingStroke = ({
    room = null,
    roomId = null,
    userId,
    strokeId,
    sessionId = null,
    points
}) => {
    if (room) {
        assertCanDrawMiniDraw(room, userId);
        assertMiniDrawUnlocked(room);
    }

    const sanitizedPoints = sanitizePoints(points, MINI_DRAW_MAX_POINTS_PER_EVENT);
    if (sanitizedPoints.length === 0) return null;

    if (!consumeUserDrawQuota({
        roomId: room?._id || roomId,
        userId,
        pointCount: sanitizedPoints.length
    })) {
        const error = new Error('Mini Draw is receiving too many points from this user');
        error.status = 429;
        error.code = 'MINI_DRAW_RATE_LIMITED';
        throw error;
    }

    const roomPending = getRoomPendingStrokes(room._id);
    const pendingStroke = roomPending?.get(toIdString(strokeId));
    if (!pendingStroke || pendingStroke.userId !== toIdString(userId)) {
        const error = new Error('Stroke is no longer active');
        error.status = 409;
        throw error;
    }
    if (sessionId && pendingStroke.sessionId !== sessionId) {
        const error = new Error('Mini Draw session changed. Please resync the board.');
        error.status = 409;
        error.code = 'MINI_DRAW_SESSION_STALE';
        throw error;
    }

    const remainingSlots = MINI_DRAW_MAX_POINTS_PER_STROKE - pendingStroke.points.length;
    if (remainingSlots <= 0) return null;

    const chunk = sanitizedPoints.slice(0, remainingSlots);
    pendingStroke.points.push(...chunk);

    return {
        roomId: pendingStroke.roomId,
        sessionId: pendingStroke.sessionId,
        strokeId: pendingStroke.strokeId,
        userId: pendingStroke.userId,
        points: chunk,
        isStart: false
    };
};

const commitPendingStroke = async ({
    room,
    userId,
    strokeId,
    points
}) => {
    assertCanDrawMiniDraw(room, userId);
    assertMiniDrawUnlocked(room);

    const roomPending = getRoomPendingStrokes(room._id);
    const pendingStroke = roomPending?.get(toIdString(strokeId));
    if (!pendingStroke || pendingStroke.userId !== toIdString(userId)) {
        const error = new Error('Stroke is no longer active');
        error.status = 409;
        throw error;
    }

    const finalChunk = sanitizePoints(points, MINI_DRAW_MAX_POINTS_PER_EVENT);
    if (finalChunk.length > 0) {
        if (!consumeUserDrawQuota({
            roomId: room._id,
            userId,
            pointCount: finalChunk.length
        })) {
            const error = new Error('Mini Draw is receiving too many points from this user');
            error.status = 429;
            error.code = 'MINI_DRAW_RATE_LIMITED';
            throw error;
        }
        const remainingSlots = MINI_DRAW_MAX_POINTS_PER_STROKE - pendingStroke.points.length;
        pendingStroke.points.push(...finalChunk.slice(0, remainingSlots));
    }

    const session = ensureMiniDrawState(room);
    clearRedoStackForUser(session, userId);
    touchSessionVersion(session);

    const committedStroke = {
        strokeId: pendingStroke.strokeId,
        toolType: pendingStroke.toolType,
        colorValue: pendingStroke.colorValue,
        thickness: pendingStroke.thickness,
        points: pendingStroke.points.slice(0, MINI_DRAW_MAX_POINTS_PER_STROKE),
        createdByUserId: userId,
        createdAt: pendingStroke.createdAt,
        updatedAt: new Date(),
        version: session.version,
        isVisible: true
    };

    session.strokes.push(committedStroke);
    trimStrokeHistory(session);

    await room.save();

    roomPending.delete(pendingStroke.strokeId);
    releaseRoomPendingMapIfEmpty(room._id);

    return {
        summary: buildMiniDrawSummary(room, userId),
        stroke: serializeStroke(committedStroke)
    };
};

const clearPendingStrokesForSocket = (socketId) => {
    if (!socketId) return;

    for (const [roomId, roomPending] of pendingStrokesByRoom.entries()) {
        for (const [strokeId, pendingStroke] of roomPending.entries()) {
            if (pendingStroke.socketId === socketId) {
                roomPending.delete(strokeId);
            }
        }
        releaseRoomPendingMapIfEmpty(roomId);
    }
};

const clearCanvas = async ({
    room,
    actorUserId,
    viewerUserId
}) => {
    assertMiniDrawUnlocked(room);
    assertCanClearMiniDraw(room, actorUserId);

    const session = ensureMiniDrawState(room);
    session.strokes = [];
    session.redoStacks = [];
    session.lastClearedByUserId = actorUserId;
    session.lastClearedAt = new Date();
    touchSessionVersion(session);

    await room.save();

    return {
        summary: buildMiniDrawSummary(room, viewerUserId || actorUserId)
    };
};

const undoLastStroke = async ({
    room,
    actorUserId,
    viewerUserId
}) => {
    assertMiniDrawUnlocked(room);
    assertCanDrawMiniDraw(room, actorUserId);

    const session = ensureMiniDrawState(room);
    const normalizedUserId = toIdString(actorUserId);
    const targetStroke = [...session.strokes]
        .reverse()
        .find((stroke) =>
            stroke.isVisible !== false &&
            toIdString(stroke.createdByUserId) === normalizedUserId
        );

    if (!targetStroke) {
        const error = new Error('There is nothing left to undo');
        error.status = 409;
        throw error;
    }

    targetStroke.isVisible = false;
    targetStroke.updatedAt = new Date();
    touchSessionVersion(session);
    pushRedoStrokeId(session, actorUserId, targetStroke.strokeId);

    await room.save();

    return {
        strokeId: toIdString(targetStroke.strokeId),
        summary: buildMiniDrawSummary(room, viewerUserId || actorUserId)
    };
};

const redoLastStroke = async ({
    room,
    actorUserId,
    viewerUserId
}) => {
    assertMiniDrawUnlocked(room);
    assertCanDrawMiniDraw(room, actorUserId);

    const session = ensureMiniDrawState(room);
    const nextStrokeId = popRedoStrokeId(session, actorUserId);
    if (!nextStrokeId) {
        const error = new Error('There is nothing left to redo');
        error.status = 409;
        throw error;
    }

    const targetStroke = session.strokes.find(
        (stroke) => toIdString(stroke.strokeId) === toIdString(nextStrokeId)
    );
    if (!targetStroke) {
        const error = new Error('The last undone stroke is no longer available');
        error.status = 409;
        throw error;
    }

    targetStroke.isVisible = true;
    targetStroke.updatedAt = new Date();
    touchSessionVersion(session);

    await room.save();

    return {
        strokeId: toIdString(targetStroke.strokeId),
        summary: buildMiniDrawSummary(room, viewerUserId || actorUserId)
    };
};

const updateMiniDrawSettings = async ({
    room,
    actorUserId,
    enabled,
    accessPolicy,
    viewerUserId
}) => {
    assertMiniDrawUnlocked(room);
    assertCanManageMiniDraw(room, actorUserId);

    const session = ensureMiniDrawState(room);
    let changed = false;

    if (typeof enabled === 'boolean' && session.enabled !== enabled) {
        session.enabled = enabled;
        changed = true;
    }
    if (accessPolicy !== undefined) {
        const normalizedAccessPolicy = normalizeMiniDrawAccessPolicy(accessPolicy);
        if (session.accessPolicy !== normalizedAccessPolicy) {
            session.accessPolicy = normalizedAccessPolicy;
            changed = true;
        }
    }

    if (!changed) {
        return {
            summary: buildMiniDrawSummary(room, viewerUserId || actorUserId)
        };
    }

    touchSessionVersion(session);
    await room.save();

    return {
        summary: buildMiniDrawSummary(room, viewerUserId || actorUserId)
    };
};

const findExistingUnlockTransaction = async ({
    userId,
    roomId,
    idempotencyKey
}) => {
    if (!idempotencyKey) return null;

    return Transaction.findOne({
        userId,
        idempotencyKey,
        type: 'room_feature_unlock',
        'reference.roomId': roomId,
        'reference.productId': 'mini_draw'
    });
};

const unlockMiniDraw = async ({
    roomId,
    userId,
    idempotencyKey
}) => {
    const room = await Room.findById(roomId);
    if (!room) {
        const error = new Error('Room not found');
        error.status = 404;
        throw error;
    }

    assertCanUnlockMiniDraw(room, userId);
    const summaryBefore = buildMiniDrawSummary(room, userId);
    if (summaryBefore.isUnlocked) {
        return {
            duplicate: true,
            chargedCoins: 0,
            summary: summaryBefore,
            newBalance: null,
            transactionId: null
        };
    }

    const existingTransaction = await findExistingUnlockTransaction({
        userId,
        roomId,
        idempotencyKey
    });
    if (existingTransaction) {
        const freshRoom = await Room.findById(roomId);
        return {
            duplicate: true,
            chargedCoins: 0,
            summary: buildMiniDrawSummary(freshRoom, userId),
            newBalance: existingTransaction.balanceAfter || null,
            transactionId: existingTransaction.transactionId || null
        };
    }

    const userBefore = await User.findById(userId).select('coins gems');
    if (!userBefore) {
        const error = new Error('User not found');
        error.status = 404;
        throw error;
    }
    if (Number(userBefore.coins || 0) < MINI_DRAW_UNLOCK_COST) {
        const error = new Error('Insufficient coins');
        error.status = 400;
        throw error;
    }

    const chargedUser = await User.findOneAndUpdate(
        {
            _id: userId,
            coins: { $gte: MINI_DRAW_UNLOCK_COST }
        },
        {
            $inc: { coins: -MINI_DRAW_UNLOCK_COST }
        },
        { new: true }
    );
    if (!chargedUser) {
        const error = new Error('Insufficient coins');
        error.status = 400;
        throw error;
    }

    const unlockedAt = new Date();
    const nextSessionId = buildSessionId();
    const updatedRoom = await Room.findOneAndUpdate(
        {
            _id: roomId,
            'miniDraw.isUnlocked': { $ne: true }
        },
        {
            $set: {
                'miniDraw.sessionId': nextSessionId,
                'miniDraw.isUnlocked': true,
                'miniDraw.unlockCostCoins': MINI_DRAW_UNLOCK_COST,
                'miniDraw.enabled': true,
                'miniDraw.accessPolicy': MINI_DRAW_ACCESS_POLICIES.ALL_PARTICIPANTS,
                'miniDraw.unlockedByUserId': userId,
                'miniDraw.unlockedAt': unlockedAt,
                'miniDraw.updatedAt': unlockedAt
            },
            $setOnInsert: {
                'miniDraw.version': 0,
                'miniDraw.strokes': [],
                'miniDraw.redoStacks': []
            }
        },
        { new: true }
    );

    if (!updatedRoom) {
        await User.findByIdAndUpdate(userId, {
            $inc: { coins: MINI_DRAW_UNLOCK_COST }
        });

        const freshRoom = await Room.findById(roomId);
        return {
            duplicate: true,
            chargedCoins: 0,
            summary: buildMiniDrawSummary(freshRoom, userId),
            newBalance: {
                coins: Number(userBefore.coins || 0),
                gems: Number(userBefore.gems || 0)
            },
            transactionId: null
        };
    }

    ensureMiniDrawState(updatedRoom);
    await updatedRoom.save();

    const transaction = new Transaction({
        userId,
        type: 'room_feature_unlock',
        amount: { coins: -MINI_DRAW_UNLOCK_COST },
        balanceBefore: {
            coins: Number(userBefore.coins || 0),
            gems: Number(userBefore.gems || 0)
        },
        balanceAfter: {
            coins: Number(chargedUser.coins || 0),
            gems: Number(chargedUser.gems || 0)
        },
        reference: {
            roomId,
            productId: 'mini_draw'
        },
        description: 'Unlocked Mini Draw for a room session',
        paymentMethod: 'system',
        idempotencyKey: idempotencyKey || undefined,
        status: 'completed',
        completedAt: unlockedAt
    });
    await transaction.save();

    return {
        duplicate: false,
        chargedCoins: MINI_DRAW_UNLOCK_COST,
        summary: buildMiniDrawSummary(updatedRoom, userId),
        newBalance: {
            coins: Number(chargedUser.coins || 0),
            gems: Number(chargedUser.gems || 0)
        },
        transactionId: transaction.transactionId || null
    };
};

const loadMiniDrawRoomForRestAction = async (roomId, userId) => {
    const room = await Room.findById(roomId);
    if (!room) {
        const error = new Error('Room not found');
        error.status = 404;
        throw error;
    }
    assertMiniDrawParticipant(room, userId);
    return room;
};

const emitMiniDrawMeta = (io, room, _userId, action) => {
    if (!io || !room) return;
    io.to(`room:${room._id}`).emit('room:draw:meta', {
        roomId: toIdString(room._id),
        action,
        summary: buildMiniDrawSummary(room, null)
    });
};

module.exports = {
    MINI_DRAW_MAX_POINTS_PER_EVENT,
    MINI_DRAW_MAX_POINTS_PER_STROKE,
    MINI_DRAW_UNLOCK_COST,
    appendPendingStroke,
    assertCanClearMiniDraw,
    assertCanDrawMiniDraw,
    assertCanManageMiniDraw,
    assertCanViewMiniDraw,
    beginPendingStroke,
    buildMiniDrawSnapshot,
    buildMiniDrawSummary,
    clearCanvas,
    clearPendingStrokesForSocket,
    commitPendingStroke,
    emitMiniDrawMeta,
    ensureMiniDrawState,
    getVisibleStrokeCount,
    loadMiniDrawRoomForRestAction,
    redoLastStroke,
    serializeStroke,
    undoLastStroke,
    unlockMiniDraw,
    updateMiniDrawSettings
};
