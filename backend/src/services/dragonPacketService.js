const crypto = require('node:crypto');
const mongoose = require('mongoose');

const AuditLog = require('../models/AuditLog');
const DragonClaimParticipant = require('../models/DragonClaimParticipant');
const DragonEventLedgerEntry = require('../models/DragonEventLedgerEntry');
const DragonEventRiskLog = require('../models/DragonEventRiskLog');
const DragonPacketInventory = require('../models/DragonPacketInventory');
const Message = require('../models/Message');
const Room = require('../models/Room');
const RoomDragonEvent = require('../models/RoomDragonEvent');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const {
    buildPublicDragonPacketConfig,
    getDragonPacketConfig,
    getDragonPacketProductBySku,
    getDragonPacketProducts
} = require('../config/dragonPacketConfig');
const {
    ROOM_ACTIONS,
    canPerformRoomAction
} = require('./roomPermissionService');

const ACCOUNT_STATUS_RESTRICTED = new Set(['suspended', 'banned', 'deleted']);
const LIVE_EVENT_STATUSES = new Set(['scheduled', 'live', 'settling']);
const DRAGON_SOCKET_EVENTS = Object.freeze({
    CREATED: 'room:dragon:created',
    TAP_ACK: 'dragon:tap_ack',
    LEADERBOARD: 'room:dragon:leaderboard',
    CLOSING: 'room:dragon:closing',
    RESULT: 'room:dragon:result',
    USER_UPDATE: 'dragon_packet:updated'
});

const runtimeState = {
    io: null,
    redis: null,
    reconcileTimer: null,
    eventTimers: new Map()
};

const withSession = (query, session) => (session ? query.session(session) : query);

const runWithOptionalTransaction = async (work) => {
    const session = await mongoose.startSession();
    try {
        session.startTransaction();
        const result = await work(session);
        await session.commitTransaction();
        return result;
    } catch (error) {
        await session.abortTransaction();
        if (error?.message?.includes('Transaction numbers are only allowed')) {
            return work(null);
        }
        throw error;
    } finally {
        await session.endSession();
    }
};

const normalizeObjectIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value?.toString === 'function') {
        const normalized = value.toString();
        if (normalized && normalized !== '[object Object]') {
            return normalized;
        }
    }
    return '';
};

const safeDate = (value) => {
    if (!value) return null;
    const parsed = value instanceof Date ? value : new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const nowIso = () => new Date().toISOString();

const isRedisReady = (redis) => !!redis && (redis.isReady ?? redis.isOpen);

const acquireRedisLock = async (redis, key, ttlSeconds = 30) => {
    if (!isRedisReady(redis) || !key) {
        return true;
    }
    const result = await redis.set(key, '1', { NX: true, EX: ttlSeconds });
    return result === 'OK' || result === true;
};

const releaseRedisLock = async (redis, key) => {
    if (!isRedisReady(redis) || !key) {
        return;
    }
    await redis.del(key).catch(() => { });
};

const createDragonPacketError = (code, message, status = 400, extra = {}) => {
    const error = new Error(message || code);
    error.code = code;
    error.status = status;
    Object.assign(error, extra);
    return error;
};

const extractRequestMetadata = (req) => ({
    ip: String(req?.ip || ''),
    forwardedFor: String(req?.get?.('x-forwarded-for') || ''),
    userAgent: String(req?.get?.('user-agent') || ''),
    deviceId: String(req?.get?.('x-device-id') || ''),
    sessionId: String(req?.get?.('x-session-id') || '')
});

const extractSocketMetadata = (socket) => ({
    ip: String(socket?.handshake?.address || ''),
    forwardedFor: String(socket?.handshake?.headers?.['x-forwarded-for'] || ''),
    userAgent: String(socket?.handshake?.headers?.['user-agent'] || ''),
    deviceId: String(socket?.handshake?.headers?.['x-device-id'] || ''),
    sessionId: String(socket?.handshake?.headers?.['x-session-id'] || '')
});

const computeAccountAgeDays = (user) => {
    const createdAt = safeDate(user?.createdAt);
    if (!createdAt) return 0;
    return Math.max(0, Math.floor((Date.now() - createdAt.getTime()) / (24 * 60 * 60 * 1000)));
};

const buildDragonTapScoreIncrement = (tapNumber, config = getDragonPacketConfig()) => {
    const safeTapNumber = Number.parseInt(tapNumber, 10);
    if (!Number.isInteger(safeTapNumber) || safeTapNumber <= 0) {
        return 0;
    }

    const band = (config.diminishingReturns || []).find(
        (entry) => safeTapNumber <= Number(entry.upToTap || 0)
    );
    if (!band) {
        return 0;
    }
    return Number(Number(band.scorePerTap || 0).toFixed(4));
};

const getDeterministicExcitementMultiplier = (eventId, userId) => {
    const hash = crypto
        .createHash('sha256')
        .update(`${eventId}:${userId}`)
        .digest('hex')
        .slice(0, 8);
    const numeric = Number.parseInt(hash, 16);
    const ratio = numeric / 0xFFFFFFFF;
    return Number((0.94 + (ratio * 0.12)).toFixed(6));
};

const compareParticipantsForTieBreak = (left, right) => {
    const leftScore = Number(left?.weightedScore || left?.computedScore || 0);
    const rightScore = Number(right?.weightedScore || right?.computedScore || 0);
    if (leftScore !== rightScore) {
        return rightScore - leftScore;
    }

    const leftAccepted = Number(left?.acceptedTapCount || 0);
    const rightAccepted = Number(right?.acceptedTapCount || 0);
    if (leftAccepted !== rightAccepted) {
        return rightAccepted - leftAccepted;
    }

    const leftFirstTap = safeDate(left?.firstTapAt)?.getTime() || Number.MAX_SAFE_INTEGER;
    const rightFirstTap = safeDate(right?.firstTapAt)?.getTime() || Number.MAX_SAFE_INTEGER;
    if (leftFirstTap !== rightFirstTap) {
        return leftFirstTap - rightFirstTap;
    }

    return normalizeObjectIdString(left?.userId).localeCompare(
        normalizeObjectIdString(right?.userId)
    );
};

const calculateDragonDistribution = ({
    eventId,
    packetTotalCoins,
    participants,
    config = getDragonPacketConfig()
}) => {
    const safePacketTotal = Math.max(0, Number(packetTotalCoins || 0));
    const rankedParticipants = (participants || [])
        .map((participant) => ({
            ...participant,
            weightedScore: Number(
                (
                    Number(participant.computedScore || 0) *
                    getDeterministicExcitementMultiplier(
                        normalizeObjectIdString(eventId),
                        normalizeObjectIdString(participant.userId)
                    )
                ).toFixed(6)
            )
        }))
        .sort(compareParticipantsForTieBreak);

    if (safePacketTotal <= 0 || rankedParticipants.length === 0) {
        return {
            allocations: new Map(),
            orderedParticipants: rankedParticipants,
            basePool: 0,
            bonusPool: 0,
            totalDistributed: 0
        };
    }

    const participantCount = rankedParticipants.length;
    const basePool = Math.max(
        0,
        Math.min(safePacketTotal, Math.floor((safePacketTotal * Number(config.basePoolPercentage || 0)) / 100))
    );
    const allocations = new Map(
        rankedParticipants.map((participant) => [normalizeObjectIdString(participant.userId), 0])
    );

    let remainingCoins = safePacketTotal;
    let baseRemaining = basePool;
    const basePerUser = participantCount > 0 ? Math.floor(basePool / participantCount) : 0;
    if (basePerUser > 0) {
        for (const participant of rankedParticipants) {
            const userId = normalizeObjectIdString(participant.userId);
            allocations.set(userId, basePerUser);
            remainingCoins -= basePerUser;
            baseRemaining -= basePerUser;
        }
    }

    for (const participant of rankedParticipants) {
        if (baseRemaining <= 0) break;
        const userId = normalizeObjectIdString(participant.userId);
        allocations.set(userId, Number(allocations.get(userId) || 0) + 1);
        baseRemaining -= 1;
        remainingCoins -= 1;
    }

    const bonusPool = Math.max(0, remainingCoins);
    const configuredPerUserCap = Math.max(
        1,
        Math.floor((safePacketTotal * Number(config.maxSharePercentagePerUser || 0)) / 100)
    );
    const perUserCap = Math.max(
        configuredPerUserCap,
        Math.ceil(safePacketTotal / participantCount)
    );

    let undistributed = bonusPool;
    while (undistributed > 0) {
        const eligible = rankedParticipants.filter((participant) => {
            const userId = normalizeObjectIdString(participant.userId);
            return Number(allocations.get(userId) || 0) < perUserCap;
        });

        if (eligible.length === 0) {
            break;
        }

        const totalWeight = eligible.reduce(
            (sum, participant) => sum + Math.max(Number(participant.weightedScore || 0), 0),
            0
        );

        let distributedThisPass = 0;
        if (totalWeight > 0) {
            for (const participant of eligible) {
                if (undistributed <= 0) break;
                const userId = normalizeObjectIdString(participant.userId);
                const currentAllocation = Number(allocations.get(userId) || 0);
                const headroom = perUserCap - currentAllocation;
                if (headroom <= 0) continue;

                const proposed = Math.floor(
                    (Math.max(Number(participant.weightedScore || 0), 0) / totalWeight) * undistributed
                );
                if (proposed <= 0) continue;

                const granted = Math.min(headroom, proposed);
                if (granted <= 0) continue;

                allocations.set(userId, currentAllocation + granted);
                undistributed -= granted;
                distributedThisPass += granted;
            }
        }

        if (undistributed <= 0) {
            break;
        }

        if (distributedThisPass === 0) {
            for (const participant of eligible) {
                if (undistributed <= 0) break;
                const userId = normalizeObjectIdString(participant.userId);
                const currentAllocation = Number(allocations.get(userId) || 0);
                if (currentAllocation >= perUserCap) continue;
                allocations.set(userId, currentAllocation + 1);
                undistributed -= 1;
            }
        }
    }

    if (undistributed > 0) {
        for (const participant of rankedParticipants) {
            if (undistributed <= 0) break;
            const userId = normalizeObjectIdString(participant.userId);
            allocations.set(userId, Number(allocations.get(userId) || 0) + 1);
            undistributed -= 1;
        }
    }

    return {
        allocations,
        orderedParticipants: rankedParticipants,
        basePool,
        bonusPool,
        totalDistributed: safePacketTotal - undistributed
    };
};

const resolveWalletSnapshot = (user) => ({
    coins: Number(user?.coins || 0),
    gems: Number(user?.gems || 0)
});

const serializeDragonPacketInventory = (entry, product = null) => ({
    id: normalizeObjectIdString(entry?._id),
    userId: normalizeObjectIdString(entry?.userId),
    productSku: String(entry?.productSku || ''),
    packageType: String(entry?.packageType || ''),
    packetCoinAmount: Number(entry?.packetCoinAmount || 0),
    purchasePriceInr: Number(entry?.purchasePriceInr || 0),
    currency: String(entry?.currency || 'INR'),
    purchaseSource: String(entry?.purchaseSource || ''),
    purchaseStatus: String(entry?.purchaseStatus || ''),
    inventoryStatus: String(entry?.inventoryStatus || ''),
    purchasedAt: safeDate(entry?.purchasedAt)?.toISOString() || null,
    reservedAt: safeDate(entry?.reservedAt)?.toISOString() || null,
    consumedAt: safeDate(entry?.consumedAt)?.toISOString() || null,
    refundedAt: safeDate(entry?.refundedAt)?.toISOString() || null,
    revokedAt: safeDate(entry?.revokedAt)?.toISOString() || null,
    linkedEventId: normalizeObjectIdString(entry?.linkedEventId),
    paymentReference: { ...(entry?.paymentReference || {}) },
    metadata: { ...(entry?.metadata || {}) },
    product: product || getDragonPacketProductBySku(entry?.productSku)
});

const serializeClaimParticipant = (participant, user = null) => ({
    participantId: normalizeObjectIdString(participant?._id),
    userId: normalizeObjectIdString(participant?.userId || user?._id),
    username: String(user?.username || participant?.metadata?.username || 'User'),
    avatar: String(user?.avatar || participant?.metadata?.avatar || ''),
    acceptedTapCount: Number(participant?.acceptedTapCount || 0),
    rawTapCount: Number(participant?.rawTapCount || 0),
    computedScore: Number(participant?.computedScore || 0),
    finalCoinReward: Number(participant?.finalCoinReward || 0),
    finalRank: Number(participant?.finalRank || 0),
    eligibilityStatus: String(participant?.eligibilityStatus || 'pending'),
    payoutStatus: String(participant?.payoutStatus || 'pending'),
    fraudFlags: [...(participant?.fraudFlags || [])],
    firstTapAt: safeDate(participant?.firstTapAt)?.toISOString() || null,
    lastTapAt: safeDate(participant?.lastTapAt)?.toISOString() || null
});

const serializeDragonEventBase = (event, { activator = null, room = null } = {}) => ({
    eventId: normalizeObjectIdString(event?._id),
    eventReferenceId: String(event?.eventReferenceId || ''),
    roomId: normalizeObjectIdString(event?.roomId || room?._id),
    roomName: String(room?.name || event?.metadata?.roomName || 'Voice Room'),
    activatorUserId: normalizeObjectIdString(event?.activatorUserId || activator?._id),
    activatorName: String(activator?.username || event?.metadata?.activatorName || 'Someone'),
    activatorAvatar: String(activator?.avatar || event?.metadata?.activatorAvatar || ''),
    productSku: String(event?.productSku || ''),
    packageType: String(event?.packageType || ''),
    packetTotalCoins: Number(event?.packetTotalCoins || 0),
    eventStatus: String(event?.eventStatus || ''),
    startAtServer: safeDate(event?.startsAt)?.toISOString() || null,
    endAtServer: safeDate(event?.endsAt)?.toISOString() || null,
    joinCutoffAtServer: safeDate(event?.joinCutoffAt)?.toISOString() || null,
    settledAt: safeDate(event?.settledAt)?.toISOString() || null,
    totalValidClaimants: Number(event?.totalValidClaimants || 0),
    totalDistributed: Number(event?.totalDistributed || 0),
    totalRefunded: Number(event?.totalRefunded || 0),
    eventDurationMs: Math.max(
        0,
        (safeDate(event?.endsAt)?.getTime() || 0) - (safeDate(event?.startsAt)?.getTime() || 0)
    ),
    dragonVisualType: String(
        event?.configSnapshot?.visualType ||
        event?.metadata?.visualType ||
        getDragonPacketConfig().visualType
    )
});

const serializeDragonEventResult = ({
    event,
    room,
    activator,
    participants,
    usersById,
    viewerUserId = null
}) => {
    const winners = (participants || [])
        .filter((participant) => Number(participant.finalCoinReward || 0) > 0)
        .sort((left, right) => {
            if (Number(right.finalCoinReward || 0) !== Number(left.finalCoinReward || 0)) {
                return Number(right.finalCoinReward || 0) - Number(left.finalCoinReward || 0);
            }
            return compareParticipantsForTieBreak(left, right);
        })
        .map((participant) => serializeClaimParticipant(
            participant,
            usersById.get(normalizeObjectIdString(participant.userId)) || null
        ));

    const normalizedViewerId = normalizeObjectIdString(viewerUserId);
    const myClaimSource = (participants || []).find(
        (participant) => normalizeObjectIdString(participant.userId) === normalizedViewerId
    );
    const myClaim = myClaimSource
        ? serializeClaimParticipant(
            myClaimSource,
            usersById.get(normalizeObjectIdString(myClaimSource.userId)) || null
        )
        : null;

    return {
        ...serializeDragonEventBase(event, { activator, room }),
        winners,
        myClaim,
        totalParticipants: Number(participants?.length || 0),
        packetExhausted: Number(event?.totalDistributed || 0) >= Number(event?.packetTotalCoins || 0),
        refundStatus: String(event?.eventStatus || '') === 'no_claim'
            ? String(event?.configSnapshot?.inventoryRefundMode || getDragonPacketConfig().inventoryRefundMode)
            : 'none',
        configSnapshot: {
            ...buildPublicDragonPacketConfig(),
            ...(event?.configSnapshot || {})
        }
    };
};

const buildDragonEventCreatedPayload = ({
    event,
    room,
    activator
}) => ({
    ...serializeDragonEventBase(event, { activator, room }),
    configSnapshot: {
        ...buildPublicDragonPacketConfig(),
        ...(event?.configSnapshot || {})
    }
});

const buildDragonTapAckPayload = ({
    eventId,
    accepted,
    tapCounted,
    currentCountedTaps,
    riskState = null
}) => ({
    eventId,
    accepted,
    tapCounted,
    currentCountedTaps,
    riskState
});

const getDragonInventorySummary = (items) => {
    const availableCounts = {};
    let availableTotal = 0;

    for (const item of items || []) {
        if (item.inventoryStatus !== 'available' || item.purchaseStatus !== 'completed') {
            continue;
        }
        availableCounts[item.productSku] = Number(availableCounts[item.productSku] || 0) + 1;
        availableTotal += 1;
    }

    return {
        availableTotal,
        availableCounts
    };
};

const emitDragonPacketUserUpdate = async ({
    io = runtimeState.io,
    userId,
    type = 'inventory_updated',
    inventory = null,
    extra = {}
}) => {
    if (!io || !userId) {
        return;
    }

    const items = inventory || await DragonPacketInventory.find({ userId })
        .sort({ purchasedAt: -1 })
        .limit(24)
        .lean();
    const serializedItems = items.map((entry) => serializeDragonPacketInventory(entry));

    io.to(`user:${normalizeObjectIdString(userId)}`).emit(
        DRAGON_SOCKET_EVENTS.USER_UPDATE,
        {
            type,
            inventory: serializedItems,
            summary: getDragonInventorySummary(serializedItems),
            products: getDragonPacketProducts(),
            updatedAt: nowIso(),
            ...extra
        }
    );
};

const emitBalanceUpdate = ({
    io = runtimeState.io,
    userId,
    coins,
    gems
}) => {
    if (!io || !userId) {
        return;
    }

    io.to(`user:${normalizeObjectIdString(userId)}`).emit('balance_update', {
        coins: Number(coins || 0),
        gems: Number(gems || 0)
    });
};

const emitRoomSystemMessage = async ({
    io = runtimeState.io,
    roomId,
    senderId,
    content,
    metadata = {},
    session = null
}) => {
    if (!io || !roomId || !senderId || !content) return null;

    const payload = {
        roomId,
        senderId,
        content,
        type: 'system',
        metadata
    };

    let message;
    if (session) {
        const [created] = await Message.create([payload], { session });
        message = created;
    } else {
        message = await Message.create(payload);
    }

    await message.populate([{ path: 'senderId', select: 'username avatar level' }]);
    io.to(`room:${normalizeObjectIdString(roomId)}`).emit('room:message', message.toObject({ virtuals: false }));
    return message;
};

const logDragonAudit = async ({
    entityType = 'dragon_event',
    entityId,
    roomId = null,
    userId = null,
    actorId = null,
    action,
    before = null,
    after = null,
    meta = null,
    session = null
}) => {
    const payload = {
        entityType,
        entityId,
        roomId,
        userId,
        actorType: actorId ? 'user' : 'system',
        actorId,
        action,
        before,
        after,
        meta
    };

    if (session) {
        await AuditLog.create([payload], { session });
        return;
    }
    await AuditLog.create(payload);
};

const recordDragonRiskLog = async ({
    eventId,
    roomId,
    userId = null,
    signalType,
    signalValue = null,
    actionTaken = 'logged',
    metadata = {},
    session = null
}) => {
    const payload = {
        eventId,
        roomId,
        userId,
        signalType,
        signalValue,
        actionTaken,
        metadata
    };

    if (session) {
        await DragonEventRiskLog.create([payload], { session });
        return;
    }
    await DragonEventRiskLog.create(payload);
};

const createDragonLedgerEntry = async (payload, session = null) => {
    if (session) {
        await DragonEventLedgerEntry.create([payload], { session });
        return;
    }
    await DragonEventLedgerEntry.create(payload);
};

const getDragonPacketProductsPayload = async (userId = null) => {
    const products = getDragonPacketProducts();
    if (!userId) {
        return {
            config: buildPublicDragonPacketConfig(),
            products
        };
    }

    const inventoryItems = await DragonPacketInventory.find({
        userId,
        inventoryStatus: 'available',
        purchaseStatus: 'completed'
    }).lean();
    const summary = getDragonInventorySummary(inventoryItems);

    return {
        config: buildPublicDragonPacketConfig(),
        products: products.map((product) => ({
            ...product,
            availableCount: Number(summary.availableCounts[product.sku] || 0)
        }))
    };
};

const getDragonPacketInventoryPayload = async (userId) => {
    const items = await DragonPacketInventory.find({ userId })
        .sort({ purchasedAt: -1 })
        .lean();

    const serializedItems = items.map((entry) => serializeDragonPacketInventory(entry));
    return {
        config: buildPublicDragonPacketConfig(),
        products: getDragonPacketProducts(),
        summary: getDragonInventorySummary(serializedItems),
        items: serializedItems.filter((entry) => entry.inventoryStatus === 'available'),
        allItems: serializedItems
    };
};

const grantDragonPacketInventory = async ({
    userId,
    product,
    purchaseSource = 'stripe',
    purchaseStatus = 'completed',
    inventoryStatus = 'available',
    paymentReference = {},
    metadata = {},
    session = null
}) => {
    const resolvedProduct = typeof product === 'string'
        ? getDragonPacketProductBySku(product)
        : product;
    if (!resolvedProduct) {
        throw createDragonPacketError('INVALID_PRODUCT', 'Dragon packet product not found.', 400);
    }

    const paymentIntentId = String(paymentReference.paymentIntentId || '').trim();
    const stripeSessionId = String(paymentReference.stripeSessionId || paymentReference.checkoutSessionId || '').trim();

    const dedupeQuery = {};
    if (paymentIntentId) {
        dedupeQuery['paymentReference.paymentIntentId'] = paymentIntentId;
    } else if (stripeSessionId) {
        dedupeQuery['paymentReference.stripeSessionId'] = stripeSessionId;
    }

    if (Object.keys(dedupeQuery).length > 0) {
        const existing = await withSession(
            DragonPacketInventory.findOne(dedupeQuery),
            session
        );
        if (existing) {
            return existing;
        }
    }

    const user = await withSession(
        User.findById(userId).select('coins gems'),
        session
    );
    if (!user) {
        throw createDragonPacketError('USER_NOT_FOUND', 'User not found.', 404);
    }

    const docPayload = {
        userId,
        productSku: resolvedProduct.sku,
        packageType: resolvedProduct.packageType,
        packetCoinAmount: resolvedProduct.packetCoinAmount,
        purchasePriceInr: resolvedProduct.priceInr,
        currency: resolvedProduct.currency || 'INR',
        purchaseSource,
        purchaseStatus,
        inventoryStatus,
        paymentReference: {
            stripeSessionId,
            paymentIntentId,
            chargeId: String(paymentReference.chargeId || ''),
            checkoutSessionId: String(paymentReference.checkoutSessionId || ''),
            externalReference: String(paymentReference.externalReference || '')
        },
        metadata
    };
    const inventoryItem = session
        ? (await DragonPacketInventory.create([docPayload], { session }))[0]
        : await DragonPacketInventory.create(docPayload);

    const transactionPayload = {
        userId,
        type: 'dragon_packet_purchase',
        amount: {
            realMoney: Number(resolvedProduct.priceInr || 0)
        },
        balanceBefore: resolveWalletSnapshot(user),
        balanceAfter: resolveWalletSnapshot(user),
        currencyType: 'real_money',
        description: `Purchased ${resolvedProduct.name}`,
        reference: {
            productId: resolvedProduct.sku,
            dragonPacketInventoryId: inventoryItem._id
        },
        metadata: {
            currency: resolvedProduct.currency || 'INR',
            packetCoinAmount: resolvedProduct.packetCoinAmount,
            packageType: resolvedProduct.packageType,
            purchaseSource
        },
        paymentMethod: purchaseSource === 'mock' ? 'mock' : 'stripe',
        status: 'completed',
        completedAt: new Date()
    };

    if (session) {
        await Transaction.create([transactionPayload], { session });
    } else {
        await Transaction.create(transactionPayload);
    }

    return inventoryItem;
};

const refundDragonPacketPurchaseByPaymentIntent = async ({
    paymentIntentId,
    chargeId = '',
    session = null
}) => {
    const normalizedPaymentIntentId = String(paymentIntentId || '').trim();
    if (!normalizedPaymentIntentId) {
        return [];
    }

    const items = await withSession(
        DragonPacketInventory.find({
            'paymentReference.paymentIntentId': normalizedPaymentIntentId,
            purchaseStatus: { $nin: ['refunded', 'revoked'] }
        }),
        session
    );

    const updatedItems = [];
    for (const item of items) {
        const previousStatus = item.inventoryStatus;
        item.purchaseStatus = 'refunded';
        if (previousStatus === 'available') {
            item.inventoryStatus = 'refunded';
            item.refundedAt = new Date();
        }
        item.paymentReference = {
            ...(item.paymentReference || {}),
            chargeId: String(chargeId || item.paymentReference?.chargeId || '')
        };
        await item.save(session ? { session } : undefined);
        updatedItems.push(item);
    }

    return updatedItems;
};

const loadDragonActivationRoom = async (roomId, userId) => {
    const room = await Room.findById(roomId)
        .select([
            '_id', 'name', 'type', 'roomActive', 'settings',
            'participants', 'hostId', 'ownerId', 'coHosts', 'moderators', 'bans'
        ].join(' '));
    if (!room) {
        throw createDragonPacketError('ROOM_NOT_FOUND', 'Voice room not found.', 404);
    }

    const config = getDragonPacketConfig();
    if (!config.featureEnabled) {
        throw createDragonPacketError('DRAGON_DISABLED', 'Golden Dragon is temporarily unavailable.', 403);
    }
    if (!config.allowedRoomTypes.includes(String(room.type || '').trim().toLowerCase())) {
        throw createDragonPacketError('ROOM_NOT_ELIGIBLE', 'Golden Dragon only works in live voice rooms.', 403);
    }
    if (room.roomActive === false) {
        throw createDragonPacketError('ROOM_NOT_LIVE', 'Golden Dragon can only start in an active room.', 403);
    }
    if (room.settings?.banRedPacket === true) {
        throw createDragonPacketError('ROOM_RED_PACKET_DISABLED', 'Golden Dragon is disabled in this room.', 403);
    }
    if (!canPerformRoomAction({
        room,
        actorUserId: userId,
        action: ROOM_ACTIONS.ACTIVATE_DRAGON_PACKET
    })) {
        throw createDragonPacketError(
            'DRAGON_ACTIVATION_FORBIDDEN',
            'Only the room host team can activate Golden Dragon.',
            403
        );
    }

    return room;
};

const findActiveRoomDragonEvent = async (roomId, session = null) => withSession(
    RoomDragonEvent.findOne({
        roomId,
        eventStatus: { $in: Array.from(LIVE_EVENT_STATUSES) }
    }).sort({ startsAt: -1 }),
    session
);

const buildEventConfigSnapshot = (product) => {
    const config = getDragonPacketConfig();
    return {
        ...buildPublicDragonPacketConfig(),
        visualType: config.visualType,
        productSku: product.sku,
        packageType: product.packageType,
        packetCoinAmount: product.packetCoinAmount,
        priceInr: product.priceInr
    };
};

const selectInventoryItemForActivation = async ({
    userId,
    purchaseInventoryId = '',
    productSku = '',
    session = null
}) => {
    const selectionQuery = {
        userId,
        inventoryStatus: 'available',
        purchaseStatus: 'completed'
    };
    if (purchaseInventoryId) {
        selectionQuery._id = purchaseInventoryId;
    } else if (productSku) {
        selectionQuery.productSku = productSku;
    }

    const inventoryItem = await withSession(
        DragonPacketInventory.findOne(selectionQuery).sort({ purchasedAt: 1 }),
        session
    );
    if (!inventoryItem) {
        throw createDragonPacketError(
            'DRAGON_PACKET_NOT_AVAILABLE',
            'You do not have an available Golden Dragon packet for this room.',
            400
        );
    }
    return inventoryItem;
};

const activateDragonPacketEvent = async ({
    roomId,
    activatorUserId,
    purchaseInventoryId = '',
    productSku = '',
    req = null,
    io = runtimeState.io,
    redis = runtimeState.redis
}) => {
    const activationLockKey = `dragon:activate:${roomId}`;
    const acquiredLock = await acquireRedisLock(redis, activationLockKey, 15);
    if (!acquiredLock) {
        throw createDragonPacketError(
            'DRAGON_ACTIVATION_IN_PROGRESS',
            'A Golden Dragon activation is already being processed.',
            409
        );
    }

    try {
        const room = await loadDragonActivationRoom(roomId, activatorUserId);
        const activator = await User.findById(activatorUserId).select(
            'username avatar accountState verification createdAt'
        );
        if (!activator || ACCOUNT_STATUS_RESTRICTED.has(String(activator.accountState?.status || 'active'))) {
            throw createDragonPacketError('ACCOUNT_RESTRICTED', 'This account cannot activate Golden Dragon right now.', 403);
        }

        const activeEvent = await findActiveRoomDragonEvent(roomId);
        if (activeEvent) {
            throw createDragonPacketError(
                'DRAGON_EVENT_ALREADY_ACTIVE',
                'A Golden Dragon event is already active in this room.',
                409
            );
        }

        const now = new Date();
        const config = getDragonPacketConfig();

        const result = await runWithOptionalTransaction(async (session) => {
            const inventoryItem = await selectInventoryItemForActivation({
                userId: activatorUserId,
                purchaseInventoryId,
                productSku,
                session
            });
            const product = getDragonPacketProductBySku(inventoryItem.productSku);
            if (!product) {
                throw createDragonPacketError('INVALID_PRODUCT', 'Golden Dragon packet product was not found.', 400);
            }

            const updatedInventory = await withSession(
                DragonPacketInventory.findOneAndUpdate(
                    {
                        _id: inventoryItem._id,
                        inventoryStatus: 'available',
                        purchaseStatus: 'completed'
                    },
                    {
                        $set: {
                            inventoryStatus: 'reserved',
                            reservedAt: now
                        }
                    },
                    {
                        new: true
                    }
                ),
                session
            );
            if (!updatedInventory) {
                throw createDragonPacketError(
                    'DRAGON_PACKET_NOT_AVAILABLE',
                    'That Golden Dragon packet is no longer available.',
                    409
                );
            }

            const startsAt = new Date(now.getTime() + 600);
            const endsAt = new Date(startsAt.getTime() + Number(config.eventDurationMs || 10000));
            const joinCutoffAt = new Date(
                endsAt.getTime() - Number(config.participantJoinCutoffRemainingMs || 5000)
            );

            const eventPayload = {
                roomId: room._id,
                activatorUserId,
                purchaseInventoryId: updatedInventory._id,
                productSku: product.sku,
                packageType: product.packageType,
                packetTotalCoins: product.packetCoinAmount,
                eventStatus: 'live',
                startsAt,
                endsAt,
                joinCutoffAt,
                requestMetadata: extractRequestMetadata(req),
                configSnapshot: buildEventConfigSnapshot(product),
                metadata: {
                    roomName: room.name || 'Voice Room',
                    activatorName: activator.username || 'Someone',
                    activatorAvatar: activator.avatar || '',
                    visualType: config.visualType
                }
            };
            const event = session
                ? (await RoomDragonEvent.create([eventPayload], { session }))[0]
                : await RoomDragonEvent.create(eventPayload);

            updatedInventory.linkedEventId = event._id;
            await updatedInventory.save(session ? { session } : undefined);

            await logDragonAudit({
                entityType: 'dragon_event',
                entityId: event._id,
                roomId: room._id,
                userId: activatorUserId,
                actorId: activatorUserId,
                action: 'dragon_event.activated',
                after: {
                    productSku: product.sku,
                    packetCoinAmount: product.packetCoinAmount,
                    startsAt,
                    endsAt
                },
                meta: {
                    purchaseInventoryId: updatedInventory._id,
                    requestMetadata: extractRequestMetadata(req)
                },
                session
            });

            return {
                room,
                activator,
                inventory: updatedInventory,
                product,
                event
            };
        });

        await emitRoomSystemMessage({
            io,
            roomId,
            senderId: activatorUserId,
            content: `${activator.username || 'Someone'} released a Golden Dragon packet!`,
            metadata: {
                dragonPacketEvent: {
                    eventId: normalizeObjectIdString(result.event._id),
                    productSku: result.product.sku,
                    packageType: result.product.packageType,
                    packetTotalCoins: result.product.packetCoinAmount,
                    activatorUserId: normalizeObjectIdString(activatorUserId)
                }
            }
        });

        const createdPayload = buildDragonEventCreatedPayload({
            event: result.event,
            room: result.room,
            activator: result.activator
        });
        io?.to(`room:${normalizeObjectIdString(roomId)}`).emit(
            DRAGON_SOCKET_EVENTS.CREATED,
            createdPayload
        );
        await emitDragonPacketUserUpdate({
            io,
            userId: activatorUserId,
            type: 'inventory_updated'
        });
        scheduleDragonEventLifecycle(result.event, { io, redis });

        return {
            success: true,
            event: createdPayload,
            inventory: serializeDragonPacketInventory(result.inventory, result.product)
        };
    } finally {
        await releaseRedisLock(redis, activationLockKey);
    }
};

const getRedisNumber = async (redis, key, fallback = 0) => {
    if (!isRedisReady(redis) || !key) {
        return fallback;
    }
    const raw = await redis.get(key);
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : fallback;
};

const getRedisString = async (redis, key, fallback = null) => {
    if (!isRedisReady(redis) || !key) {
        return fallback;
    }
    const raw = await redis.get(key);
    return raw == null ? fallback : String(raw);
};

const getRedisJson = async (redis, key, fallback = null) => {
    if (!isRedisReady(redis) || !key) {
        return fallback;
    }
    const raw = await redis.get(key);
    if (!raw) {
        return fallback;
    }
    try {
        return JSON.parse(raw);
    } catch (_) {
        return fallback;
    }
};

const setRedisJson = async (redis, key, value, ttlSeconds = 900) => {
    if (!isRedisReady(redis) || !key) {
        return;
    }
    await redis.set(key, JSON.stringify(value), { EX: ttlSeconds });
};

const buildTapRedisKeys = (eventId, userId, seq, nowMs, config) => {
    const normalizedEventId = normalizeObjectIdString(eventId);
    const normalizedUserId = normalizeObjectIdString(userId);
    const secondBucket = Math.floor(nowMs / 1000);
    const rollingBucket = Math.floor(nowMs / (Number(config.rollingWindowSeconds || 2) * 1000));

    return {
        sequence: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:seq:${seq}`,
        raw: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:raw`,
        accepted: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:accepted`,
        score: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:score`,
        secondBucket: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:sec:${secondBucket}`,
        rollingBucket: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:rolling:${rollingBucket}`,
        firstTapAt: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:firstTapAt`,
        lastTapAtMs: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:lastTapAtMs`,
        intervals: `dragon:event:${normalizedEventId}:user:${normalizedUserId}:intervals`
    };
};

const loadTapEventContext = async (eventId) => {
    const event = await RoomDragonEvent.findById(eventId).lean();
    if (!event) {
        throw createDragonPacketError('DRAGON_EVENT_NOT_FOUND', 'Golden Dragon event was not found.', 404);
    }

    const room = await Room.findById(event.roomId).select(
        '_id name type roomActive settings participants hostId ownerId coHosts moderators bans'
    );
    if (!room) {
        throw createDragonPacketError('ROOM_NOT_FOUND', 'Voice room not found.', 404);
    }

    return { event, room };
};

const resolveParticipantEntry = (room, userId) =>
    (room?.participants || []).find(
        (entry) => normalizeObjectIdString(entry?.userId) === normalizeObjectIdString(userId)
    ) || null;

const isUserBannedInRoom = (room, userId) =>
    (room?.bans || []).some((ban) =>
        normalizeObjectIdString(ban?.userId) === normalizeObjectIdString(userId) &&
        (!ban?.expiresAt || new Date(ban.expiresAt) > new Date())
    );

const validateDragonClaimEligibility = ({
    room,
    event,
    participant,
    user,
    claimantUserId,
    now = new Date()
}) => {
    const config = getDragonPacketConfig();

    if (room.type !== 'voice' || room.roomActive === false) {
        return createDragonPacketError('ROOM_NOT_ELIGIBLE', 'Golden Dragon is no longer available in this room.', 403);
    }
    if (room.settings?.banRedPacket === true) {
        return createDragonPacketError('ROOM_RED_PACKET_DISABLED', 'Golden Dragon is disabled in this room.', 403);
    }
    if (!participant || participant.isPresent === false) {
        return createDragonPacketError('CLAIMANT_NOT_PRESENT', 'Join the room to claim Golden Dragon.', 403);
    }
    if (isUserBannedInRoom(room, claimantUserId)) {
        return createDragonPacketError('CLAIMANT_BANNED', 'You cannot claim Golden Dragon in this room.', 403);
    }
    if (!user || ACCOUNT_STATUS_RESTRICTED.has(String(user.accountState?.status || 'active'))) {
        return createDragonPacketError('ACCOUNT_RESTRICTED', 'This account cannot claim Golden Dragon right now.', 403);
    }
    if (
        config.requireVerifiedAccountToClaim &&
        user.verification?.isVerifiedAccount !== true
    ) {
        return createDragonPacketError('VERIFICATION_REQUIRED', 'Verify your account to claim Golden Dragon.', 403);
    }
    if (computeAccountAgeDays(user) < Number(config.minimumAccountAgeDaysToClaim || 0)) {
        return createDragonPacketError('ACCOUNT_TOO_NEW', 'Your account is too new for Golden Dragon claims.', 403);
    }

    const eventStart = safeDate(event.startsAt);
    const eventEnd = safeDate(event.endsAt);
    const joinCutoffAt = safeDate(event.joinCutoffAt);
    if (!eventStart || !eventEnd || now < eventStart) {
        return createDragonPacketError('DRAGON_EVENT_NOT_STARTED', 'Golden Dragon has not started yet.', 403);
    }
    if (now > eventEnd) {
        return createDragonPacketError('DRAGON_EVENT_ENDED', 'Golden Dragon has already ended.', 403);
    }

    if (
        config.activatorCanClaim !== true &&
        normalizeObjectIdString(event.activatorUserId) === normalizeObjectIdString(claimantUserId)
    ) {
        return createDragonPacketError('ACTIVATOR_CANNOT_CLAIM', 'You cannot claim your own Golden Dragon packet.', 403);
    }

    const joinedAt = safeDate(participant.joinedAt || participant.lastActive || participant.createdAt);
    if (joinedAt) {
        if (joinedAt > new Date(now.getTime() - (Number(config.minimumRoomPresenceSeconds || 0) * 1000))) {
            return createDragonPacketError('ROOM_PRESENCE_TOO_SHORT', 'Stay in the room a bit longer before claiming.', 403);
        }
        if (joinedAt > eventStart && joinCutoffAt && joinedAt > joinCutoffAt) {
            return createDragonPacketError('JOINED_TOO_LATE', 'You joined too late for this Golden Dragon event.', 403);
        }
    }

    return null;
};

const getOrCreateClaimParticipant = async ({
    event,
    room,
    user,
    claimantUserId,
    socketMetadata,
    liveState,
    fraudFlags = []
}) => {
    const participant = resolveParticipantEntry(room, claimantUserId);
    const joinedRoomAtSnapshot = safeDate(participant?.joinedAt || participant?.lastActive);
    const payload = {
        eventId: event._id,
        roomId: room._id,
        userId: claimantUserId,
        firstTapAt: liveState.firstTapAt ? new Date(liveState.firstTapAt) : null,
        lastTapAt: new Date(liveState.lastTapAtMs),
        acceptedTapCount: Number(liveState.acceptedTapCount || 0),
        rawTapCount: Number(liveState.rawTapCount || 0),
        computedScore: Number(liveState.computedScore || 0),
        eligibilityStatus: liveState.eligibilityStatus || 'eligible',
        metadata: {
            username: user.username || '',
            avatar: user.avatar || '',
            ip: socketMetadata.ip,
            deviceId: socketMetadata.deviceId,
            sessionId: socketMetadata.sessionId
        }
    };

    return DragonClaimParticipant.findOneAndUpdate(
        {
            eventId: event._id,
            userId: claimantUserId
        },
        {
            $setOnInsert: {
                joinedRoomAtSnapshot
            },
            $set: payload,
            ...(fraudFlags.length > 0
                ? { $addToSet: { fraudFlags: { $each: fraudFlags } } }
                : {})
        },
        {
            upsert: true,
            new: true
        }
    );
};

const detectSuspiciousRegularity = async ({
    redis,
    intervalsKey,
    lastTapAtMs,
    nowMs,
    config
}) => {
    if (!lastTapAtMs || !isRedisReady(redis)) {
        return {
            suspicious: false,
            intervals: []
        };
    }

    const interval = nowMs - Number(lastTapAtMs);
    if (!Number.isFinite(interval) || interval <= 0) {
        return {
            suspicious: false,
            intervals: []
        };
    }

    const previousIntervals = await getRedisJson(redis, intervalsKey, []);
    const nextIntervals = [...previousIntervals, interval].slice(-8);
    await setRedisJson(redis, intervalsKey, nextIntervals, 900);

    if (nextIntervals.length < Number(config.suspiciousRegularityMinimumIntervals || 6)) {
        return {
            suspicious: false,
            intervals: nextIntervals
        };
    }

    const max = Math.max(...nextIntervals);
    const min = Math.min(...nextIntervals);
    return {
        suspicious: (max - min) <= Number(config.suspiciousRegularityToleranceMs || 8),
        intervals: nextIntervals
    };
};

const handleDragonTapSocket = async ({
    roomId,
    eventId,
    seq,
    socket,
    redis = runtimeState.redis
}) => {
    const normalizedEventId = normalizeObjectIdString(eventId);
    const normalizedRoomId = normalizeObjectIdString(roomId);
    const normalizedUserId = normalizeObjectIdString(socket?.userId);
    const safeSeq = Number.parseInt(seq, 10);
    if (!normalizedEventId || !normalizedRoomId || !normalizedUserId || !Number.isInteger(safeSeq)) {
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: false,
            tapCounted: false,
            currentCountedTaps: 0,
            riskState: 'invalid'
        });
    }

    const { event, room } = await loadTapEventContext(normalizedEventId);
    if (normalizeObjectIdString(event.roomId) !== normalizedRoomId) {
        throw createDragonPacketError('DRAGON_EVENT_ROOM_MISMATCH', 'Golden Dragon event does not belong to this room.', 400);
    }
    if (!LIVE_EVENT_STATUSES.has(String(event.eventStatus || ''))) {
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: false,
            tapCounted: false,
            currentCountedTaps: 0,
            riskState: 'closed'
        });
    }

    const user = await User.findById(normalizedUserId).select(
        'username avatar accountState verification createdAt'
    );
    const participant = resolveParticipantEntry(room, normalizedUserId);
    const eligibilityError = validateDragonClaimEligibility({
        room,
        event,
        participant,
        user,
        claimantUserId: normalizedUserId
    });
    if (eligibilityError) {
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: false,
            tapCounted: false,
            currentCountedTaps: 0,
            riskState: String(eligibilityError.code || 'ineligible').toLowerCase()
        });
    }

    const config = getDragonPacketConfig();
    const nowMs = Date.now();
    const socketMetadata = extractSocketMetadata(socket);
    const keys = buildTapRedisKeys(normalizedEventId, normalizedUserId, safeSeq, nowMs, config);

    const sequenceAccepted = isRedisReady(redis)
        ? await redis.set(keys.sequence, '1', { NX: true, EX: 900 })
        : 'OK';
    if (!(sequenceAccepted === 'OK' || sequenceAccepted === true)) {
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: true,
            tapCounted: false,
            currentCountedTaps: await getRedisNumber(redis, keys.accepted, 0),
            riskState: 'duplicate_sequence'
        });
    }

    const rawTapCount = isRedisReady(redis)
        ? Number(await redis.incr(keys.raw))
        : 1;
    if (isRedisReady(redis)) {
        await redis.expire(keys.raw, 900).catch(() => { });
    }

    const secondCount = isRedisReady(redis)
        ? Number(await redis.incr(keys.secondBucket))
        : 1;
    const rollingCount = isRedisReady(redis)
        ? Number(await redis.incr(keys.rollingBucket))
        : 1;
    if (isRedisReady(redis)) {
        await Promise.all([
            redis.expire(keys.secondBucket, 10).catch(() => { }),
            redis.expire(keys.rollingBucket, 10).catch(() => { })
        ]);
    }

    if (
        secondCount > Number(config.maxCountedTapsPerSecond || 8) ||
        rollingCount > Number(config.maxCountedTapsPerRollingWindow || 14)
    ) {
        await getOrCreateClaimParticipant({
            event,
            room,
            user,
            claimantUserId: normalizedUserId,
            socketMetadata,
            liveState: {
                firstTapAt: await getRedisString(redis, keys.firstTapAt, null),
                lastTapAtMs: nowMs,
                acceptedTapCount: await getRedisNumber(redis, keys.accepted, 0),
                rawTapCount,
                computedScore: await getRedisNumber(redis, keys.score, 0),
                eligibilityStatus: 'throttled'
            },
            fraudFlags: ['rate_limited']
        });
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: true,
            tapCounted: false,
            currentCountedTaps: await getRedisNumber(redis, keys.accepted, 0),
            riskState: 'rate_limited'
        });
    }

    const acceptedTapCount = isRedisReady(redis)
        ? Number(await redis.incr(keys.accepted))
        : 1;
    if (acceptedTapCount > Number(config.maxTotalCountedTaps || 50)) {
        if (isRedisReady(redis) && typeof redis.decr === 'function') {
            await redis.decr(keys.accepted).catch(() => { });
        }
        await getOrCreateClaimParticipant({
            event,
            room,
            user,
            claimantUserId: normalizedUserId,
            socketMetadata,
            liveState: {
                firstTapAt: await getRedisString(redis, keys.firstTapAt, null),
                lastTapAtMs: nowMs,
                acceptedTapCount: Number(config.maxTotalCountedTaps || 50),
                rawTapCount,
                computedScore: await getRedisNumber(redis, keys.score, 0),
                eligibilityStatus: 'eligible'
            },
            fraudFlags: ['max_tap_cap_reached']
        });
        return buildDragonTapAckPayload({
            eventId: normalizedEventId,
            accepted: true,
            tapCounted: false,
            currentCountedTaps: Number(config.maxTotalCountedTaps || 50),
            riskState: 'tap_cap'
        });
    }

    const scoreIncrement = buildDragonTapScoreIncrement(acceptedTapCount, config);
    if (isRedisReady(redis) && typeof redis.incrByFloat === 'function') {
        await redis.incrByFloat(keys.score, scoreIncrement);
        await redis.expire(keys.score, 900).catch(() => { });
    } else if (isRedisReady(redis)) {
        const currentScore = await getRedisNumber(redis, keys.score, 0);
        await redis.set(keys.score, String(currentScore + scoreIncrement), { EX: 900 });
    }

    const existingFirstTapAt = isRedisReady(redis)
        ? await redis.get(keys.firstTapAt)
        : null;
    if (!existingFirstTapAt && isRedisReady(redis)) {
        await redis.set(keys.firstTapAt, new Date(nowMs).toISOString(), { EX: 900, NX: true }).catch(() => { });
    }

    const lastTapAtMs = isRedisReady(redis)
        ? await redis.get(keys.lastTapAtMs)
        : null;
    if (isRedisReady(redis)) {
        await redis.set(keys.lastTapAtMs, String(nowMs), { EX: 900 }).catch(() => { });
    }

    const regularity = await detectSuspiciousRegularity({
        redis,
        intervalsKey: keys.intervals,
        lastTapAtMs,
        nowMs,
        config
    });

    const computedScore = isRedisReady(redis)
        ? await getRedisNumber(redis, keys.score, scoreIncrement)
        : scoreIncrement;
    const fraudFlags = [];
    if (regularity.suspicious) {
        fraudFlags.push('regular_interval_pattern');
        await recordDragonRiskLog({
            eventId: event._id,
            roomId: room._id,
            userId: normalizedUserId,
            signalType: 'regular_interval_pattern',
            signalValue: regularity.intervals,
            actionTaken: 'logged',
            metadata: {
                deviceId: socketMetadata.deviceId,
                ip: socketMetadata.ip
            }
        });
    }

    const participantDoc = await getOrCreateClaimParticipant({
        event,
        room,
        user,
        claimantUserId: normalizedUserId,
        socketMetadata,
        liveState: {
            firstTapAt: existingFirstTapAt || new Date(nowMs).toISOString(),
            lastTapAtMs: nowMs,
            acceptedTapCount,
            rawTapCount,
            computedScore,
            eligibilityStatus: 'eligible'
        },
        fraudFlags
    });

    return buildDragonTapAckPayload({
        eventId: normalizedEventId,
        accepted: true,
        tapCounted: true,
        currentCountedTaps: Number(participantDoc.acceptedTapCount || acceptedTapCount),
        riskState: fraudFlags.length > 0 ? 'flagged' : null
    });
};

const buildDragonLeaderboardSnapshot = async (eventId) => {
    const event = await RoomDragonEvent.findById(eventId).lean();
    if (!event) {
        return null;
    }

    const room = await Room.findById(event.roomId).select('name').lean();
    const topParticipants = await DragonClaimParticipant.find({
        eventId,
        acceptedTapCount: { $gte: 1 }
    })
        .sort({ computedScore: -1, acceptedTapCount: -1, firstTapAt: 1 })
        .limit(5)
        .lean();
    const userIds = topParticipants.map((participant) => participant.userId);
    const users = await User.find({ _id: { $in: userIds } })
        .select('username avatar')
        .lean();
    const usersById = new Map(users.map((user) => [normalizeObjectIdString(user._id), user]));

    const countdownMs = Math.max(0, (safeDate(event.endsAt)?.getTime() || 0) - Date.now());
    const totalParticipants = await DragonClaimParticipant.countDocuments({
        eventId,
        acceptedTapCount: { $gte: 1 }
    });

    const hypeState = countdownMs <= 2000
        ? 'finale'
        : totalParticipants >= 8
            ? 'frenzy'
            : totalParticipants >= 3
                ? 'ignited'
                : 'warming_up';

    return {
        eventId: normalizeObjectIdString(event._id),
        roomId: normalizeObjectIdString(event.roomId),
        roomName: String(room?.name || event.metadata?.roomName || 'Voice Room'),
        countdownMs,
        countdownSeconds: Math.ceil(countdownMs / 1000),
        totalParticipants,
        hypeState,
        topClaimants: topParticipants.map((participant, index) => ({
            rank: index + 1,
            ...serializeClaimParticipant(
                participant,
                usersById.get(normalizeObjectIdString(participant.userId)) || null
            )
        })),
        updatedAt: nowIso()
    };
};

const clearDragonEventLifecycle = (eventId) => {
    const normalizedEventId = normalizeObjectIdString(eventId);
    const timers = runtimeState.eventTimers.get(normalizedEventId);
    if (!timers) {
        return;
    }

    if (timers.startTimeout) clearTimeout(timers.startTimeout);
    if (timers.leaderboardInterval) clearInterval(timers.leaderboardInterval);
    if (timers.finishTimeout) clearTimeout(timers.finishTimeout);
    runtimeState.eventTimers.delete(normalizedEventId);
};

const emitDragonLeaderboard = async (eventId, { io = runtimeState.io } = {}) => {
    const snapshot = await buildDragonLeaderboardSnapshot(eventId);
    if (!snapshot || !io) {
        return;
    }
    io.to(`room:${snapshot.roomId}`).emit(DRAGON_SOCKET_EVENTS.LEADERBOARD, snapshot);
};

const scheduleDragonEventLifecycle = (event, { io = runtimeState.io, redis = runtimeState.redis } = {}) => {
    const normalizedEventId = normalizeObjectIdString(event?._id);
    const normalizedRoomId = normalizeObjectIdString(event?.roomId);
    const startsAt = safeDate(event?.startsAt);
    const endsAt = safeDate(event?.endsAt);
    if (!normalizedEventId || !normalizedRoomId || !startsAt || !endsAt || !io) {
        return;
    }

    clearDragonEventLifecycle(normalizedEventId);

    const config = getDragonPacketConfig();
    const timers = {};
    const beginLiveLoop = () => {
        emitDragonLeaderboard(normalizedEventId, { io }).catch(() => { });
        timers.leaderboardInterval = setInterval(() => {
            emitDragonLeaderboard(normalizedEventId, { io }).catch(() => { });
        }, Math.max(250, Number(config.leaderboardBroadcastIntervalMs || 1000)));
    };

    const startDelay = Math.max(0, startsAt.getTime() - Date.now());
    if (startDelay > 0) {
        timers.startTimeout = setTimeout(beginLiveLoop, startDelay);
    } else {
        beginLiveLoop();
    }

    const finishDelay = Math.max(0, endsAt.getTime() - Date.now());
    timers.finishTimeout = setTimeout(async () => {
        io.to(`room:${normalizedRoomId}`).emit(DRAGON_SOCKET_EVENTS.CLOSING, {
            roomId: normalizedRoomId,
            eventId: normalizedEventId,
            countdownMs: 0,
            endAtServer: endsAt.toISOString()
        });
        try {
            await settleDragonEvent({
                eventId: normalizedEventId,
                io,
                redis,
                reason: 'timer'
            });
        } catch (_) {
            // reconciliation loop will retry safely
        } finally {
            clearDragonEventLifecycle(normalizedEventId);
        }
    }, finishDelay);

    runtimeState.eventTimers.set(normalizedEventId, timers);
};

const settleDragonEvent = async ({
    eventId,
    io = runtimeState.io,
    redis = runtimeState.redis,
    reason = 'manual'
}) => {
    const normalizedEventId = normalizeObjectIdString(eventId);
    const lockKey = `dragon:settle:${normalizedEventId}`;
    const acquiredLock = await acquireRedisLock(redis, lockKey, 30);
    if (!acquiredLock) {
        return null;
    }

    try {
        const result = await runWithOptionalTransaction(async (session) => {
            const event = await withSession(
                RoomDragonEvent.findById(normalizedEventId),
                session
            );
            if (!event) {
                throw createDragonPacketError('DRAGON_EVENT_NOT_FOUND', 'Golden Dragon event was not found.', 404);
            }

            const room = await withSession(Room.findById(event.roomId).select('name'), session);
            const activator = await withSession(User.findById(event.activatorUserId).select('username avatar'), session);
            const participants = await withSession(
                DragonClaimParticipant.find({ eventId: event._id }),
                session
            );

            if (['settled', 'no_claim', 'refunded'].includes(String(event.eventStatus || ''))) {
                const users = await withSession(
                    User.find({
                        _id: { $in: participants.map((participant) => participant.userId) }
                    }).select('username avatar'),
                    session
                );
                const usersById = new Map(users.map((user) => [normalizeObjectIdString(user._id), user]));
                return serializeDragonEventResult({
                    event,
                    room,
                    activator,
                    participants,
                    usersById
                });
            }

            event.eventStatus = 'settling';
            event.settlementAttemptCount = Number(event.settlementAttemptCount || 0) + 1;
            await event.save(session ? { session } : undefined);

            const validParticipants = participants.filter((participant) =>
                Number(participant.acceptedTapCount || 0) >= Number(event.configSnapshot?.minValidTapsToParticipate || getDragonPacketConfig().minValidTapsToParticipate)
            );
            const inventory = await withSession(
                DragonPacketInventory.findById(event.purchaseInventoryId),
                session
            );

            if (validParticipants.length === 0) {
                if (inventory && String(event.configSnapshot?.inventoryRefundMode || getDragonPacketConfig().inventoryRefundMode) === 'restore_inventory') {
                    inventory.inventoryStatus = 'available';
                    inventory.reservedAt = null;
                    inventory.linkedEventId = null;
                    await inventory.save(session ? { session } : undefined);
                    await createDragonLedgerEntry({
                        eventId: event._id,
                        entryType: 'inventory_restored',
                        userId: event.activatorUserId,
                        walletOwnerId: event.activatorUserId,
                        amount: Number(event.packetTotalCoins || 0),
                        balanceBefore: null,
                        balanceAfter: null,
                        referenceType: 'dragon_packet_inventory',
                        referenceId: inventory._id,
                        notes: 'Golden Dragon restored because there were no valid claimants.',
                        metadata: {
                            inventoryStatus: inventory.inventoryStatus,
                            refundMode: event.configSnapshot?.inventoryRefundMode || getDragonPacketConfig().inventoryRefundMode
                        }
                    }, session);
                }

                event.eventStatus = 'no_claim';
                event.totalValidClaimants = 0;
                event.totalDistributed = 0;
                event.totalRefunded = Number(event.packetTotalCoins || 0);
                event.settledAt = new Date();
                event.resultSummary = {
                    refundMode: event.configSnapshot?.inventoryRefundMode || getDragonPacketConfig().inventoryRefundMode,
                    reason
                };
                await event.save(session ? { session } : undefined);

                await logDragonAudit({
                    entityType: 'dragon_event',
                    entityId: event._id,
                    roomId: event.roomId,
                    userId: event.activatorUserId,
                    actorId: event.activatorUserId,
                    action: 'dragon_event.no_claim',
                    after: {
                        totalRefunded: event.totalRefunded,
                        refundMode: event.resultSummary.refundMode
                    },
                    meta: {
                        reason
                    },
                    session
                });

                return serializeDragonEventResult({
                    event,
                    room,
                    activator,
                    participants: [],
                    usersById: new Map(),
                    viewerUserId: event.activatorUserId
                });
            }

            const distribution = calculateDragonDistribution({
                eventId: normalizedEventId,
                packetTotalCoins: Number(event.packetTotalCoins || 0),
                participants: validParticipants.map((participant) => participant.toObject({ virtuals: false })),
                config: {
                    basePoolPercentage: Number(event.configSnapshot?.basePoolPercentage || getDragonPacketConfig().basePoolPercentage),
                    maxSharePercentagePerUser: Number(event.configSnapshot?.maxSharePercentagePerUser || getDragonPacketConfig().maxSharePercentagePerUser)
                }
            });

            const allocationList = validParticipants.map((participant) => ({
                participant,
                reward: Number(distribution.allocations.get(normalizeObjectIdString(participant.userId)) || 0)
            }));
            allocationList.sort((left, right) => {
                if (right.reward !== left.reward) {
                    return right.reward - left.reward;
                }
                return compareParticipantsForTieBreak(left.participant, right.participant);
            });

            const rewardedUserIds = allocationList.map((entry) => entry.participant.userId);
            const winnerUsers = await withSession(
                User.find({ _id: { $in: rewardedUserIds } }).select('username avatar coins gems'),
                session
            );
            const winnerUserMap = new Map(
                winnerUsers.map((user) => [normalizeObjectIdString(user._id), user])
            );
            const winnerBalanceUpdates = [];

            let finalRank = 0;
            for (const entry of allocationList) {
                finalRank += 1;
                const participant = entry.participant;
                const userId = normalizeObjectIdString(participant.userId);
                const user = winnerUserMap.get(userId);
                const reward = Math.max(0, Number(entry.reward || 0));

                participant.finalCoinReward = reward;
                participant.finalRank = finalRank;
                participant.payoutStatus = reward > 0 ? 'paid' : 'skipped';
                await participant.save(session ? { session } : undefined);

                if (!user || reward <= 0) {
                    continue;
                }

                const balanceBefore = Number(user.coins || 0);
                user.coins = balanceBefore + reward;
                await user.save(session ? { session } : undefined);
                winnerBalanceUpdates.push({
                    userId: user._id,
                    coins: Number(user.coins || 0),
                    gems: Number(user.gems || 0)
                });

                const transactionPayload = {
                    userId: user._id,
                    type: 'dragon_packet_reward',
                    amount: {
                        coins: reward
                    },
                    balanceBefore: {
                        coins: balanceBefore,
                        gems: Number(user.gems || 0)
                    },
                    balanceAfter: {
                        coins: Number(user.coins || 0),
                        gems: Number(user.gems || 0)
                    },
                    currencyType: 'coins',
                    description: `Won ${reward} coins from Golden Dragon`,
                    reference: {
                        roomId: event.roomId,
                        dragonEventId: event._id,
                        dragonClaimParticipantId: participant._id
                    },
                    paymentMethod: 'system',
                    status: 'completed',
                    completedAt: new Date()
                };

                if (session) {
                    await Transaction.create([transactionPayload], { session });
                } else {
                    await Transaction.create(transactionPayload);
                }

                await createDragonLedgerEntry({
                    eventId: event._id,
                    entryType: 'winner_credit',
                    userId: user._id,
                    walletOwnerId: user._id,
                    amount: reward,
                    balanceBefore,
                    balanceAfter: Number(user.coins || 0),
                    referenceType: 'dragon_claim_participant',
                    referenceId: participant._id,
                    notes: `Golden Dragon reward credited to ${user.username || 'user'}.`,
                    metadata: {
                        finalRank,
                        acceptedTapCount: Number(participant.acceptedTapCount || 0),
                        computedScore: Number(participant.computedScore || 0)
                    }
                }, session);
            }

            if (inventory) {
                inventory.inventoryStatus = 'consumed';
                inventory.consumedAt = new Date();
                await inventory.save(session ? { session } : undefined);
                await createDragonLedgerEntry({
                    eventId: event._id,
                    entryType: 'inventory_consumed',
                    userId: event.activatorUserId,
                    walletOwnerId: event.activatorUserId,
                    amount: Number(event.packetTotalCoins || 0),
                    balanceBefore: null,
                    balanceAfter: null,
                    referenceType: 'dragon_packet_inventory',
                    referenceId: inventory._id,
                    notes: 'Golden Dragon inventory item consumed at settlement.',
                    metadata: {
                        inventoryStatus: inventory.inventoryStatus
                    }
                }, session);
            }

            event.eventStatus = 'settled';
            event.settledAt = new Date();
            event.totalValidClaimants = validParticipants.length;
            event.totalDistributed = allocationList.reduce((sum, entry) => sum + Number(entry.reward || 0), 0);
            event.totalRefunded = 0;
            event.resultSummary = {
                basePool: distribution.basePool,
                bonusPool: distribution.bonusPool,
                reason
            };
            await event.save(session ? { session } : undefined);

            await logDragonAudit({
                entityType: 'dragon_event',
                entityId: event._id,
                roomId: event.roomId,
                userId: event.activatorUserId,
                actorId: event.activatorUserId,
                action: 'dragon_event.settled',
                after: {
                    totalDistributed: event.totalDistributed,
                    totalValidClaimants: event.totalValidClaimants
                },
                meta: {
                    reason
                },
                session
            });

            const usersById = new Map(
                winnerUsers.map((user) => [normalizeObjectIdString(user._id), user])
            );
            return {
                ...serializeDragonEventResult({
                    event,
                    room,
                    activator,
                    participants: allocationList.map((entry) => entry.participant),
                    usersById
                }),
                winnerBalanceUpdates
            };
        });

        if (io && result?.roomId) {
            io.to(`room:${result.roomId}`).emit(DRAGON_SOCKET_EVENTS.RESULT, result);
        }
        if (result?.activatorUserId) {
            await emitDragonPacketUserUpdate({
                io,
                userId: result.activatorUserId,
                type: 'inventory_updated'
            });
        }
        if (Array.isArray(result?.winnerBalanceUpdates)) {
            for (const balanceUpdate of result.winnerBalanceUpdates) {
                emitBalanceUpdate({
                    io,
                    userId: balanceUpdate.userId,
                    coins: balanceUpdate.coins,
                    gems: balanceUpdate.gems
                });
            }
        }
        if (io && result?.roomId) {
            const resultMessage = result.eventStatus === 'no_claim'
                ? 'Golden Dragon ended with no valid claimants. The packet was restored.'
                : `Golden Dragon ended. ${result.winners[0]?.username || 'A player'} led the rush.`;
            await emitRoomSystemMessage({
                io,
                roomId: result.roomId,
                senderId: result.activatorUserId,
                content: resultMessage,
                metadata: {
                    dragonPacketEventResult: {
                        eventId: result.eventId,
                        eventStatus: result.eventStatus,
                        totalDistributed: result.totalDistributed
                    }
                }
            });
        }

        return result;
    } finally {
        await releaseRedisLock(redis, lockKey);
    }
};

const reconcileStaleDragonEvents = async ({
    io = runtimeState.io,
    redis = runtimeState.redis
} = {}) => {
    const staleEvents = await RoomDragonEvent.find({
        $or: [
            {
                eventStatus: { $in: ['scheduled', 'live'] },
                endsAt: { $lte: new Date() }
            },
            {
                eventStatus: 'settling',
                updatedAt: { $lte: new Date(Date.now() - 15000) }
            }
        ]
    })
        .sort({ endsAt: 1 })
        .limit(12)
        .lean();

    for (const event of staleEvents) {
        try {
            await settleDragonEvent({
                eventId: event._id,
                io,
                redis,
                reason: 'reconcile'
            });
        } catch (_) {
            // next reconcile pass will retry
        }
    }
};

const initializeDragonPacketRuntime = ({
    io,
    redis
}) => {
    runtimeState.io = io;
    runtimeState.redis = redis;
    if (runtimeState.reconcileTimer) {
        clearInterval(runtimeState.reconcileTimer);
    }

    const intervalMs = Math.max(
        1000,
        Number(getDragonPacketConfig().reconcileIntervalMs || 5000)
    );
    runtimeState.reconcileTimer = setInterval(() => {
        reconcileStaleDragonEvents({ io, redis }).catch(() => { });
    }, intervalMs);
};

const getDragonEventResult = async ({
    roomId,
    eventId,
    viewerUserId
}) => {
    const event = await RoomDragonEvent.findById(eventId).lean();
    if (!event || normalizeObjectIdString(event.roomId) !== normalizeObjectIdString(roomId)) {
        throw createDragonPacketError('DRAGON_EVENT_NOT_FOUND', 'Golden Dragon result was not found.', 404);
    }

    const [room, activator, participants, users] = await Promise.all([
        Room.findById(event.roomId).select('name').lean(),
        User.findById(event.activatorUserId).select('username avatar').lean(),
        DragonClaimParticipant.find({ eventId: event._id }).lean(),
        User.find({
            _id: {
                $in: await DragonClaimParticipant.find({ eventId: event._id }).distinct('userId')
            }
        }).select('username avatar').lean()
    ]);

    const usersById = new Map(users.map((user) => [normalizeObjectIdString(user._id), user]));
    return serializeDragonEventResult({
        event,
        room,
        activator,
        participants,
        usersById,
        viewerUserId
    });
};

const getActiveDragonEvent = async ({
    roomId,
    viewerUserId = null
}) => {
    const event = await RoomDragonEvent.findOne({
        roomId,
        eventStatus: { $in: ['scheduled', 'live', 'settling'] },
        endsAt: { $gte: new Date(Date.now() - 5000) }
    })
        .sort({ startsAt: -1 })
        .lean();

    if (!event) {
        return {
            active: false
        };
    }

    const [room, activator, myParticipant] = await Promise.all([
        Room.findById(roomId).select('name').lean(),
        User.findById(event.activatorUserId).select('username avatar').lean(),
        viewerUserId
            ? DragonClaimParticipant.findOne({ eventId: event._id, userId: viewerUserId }).lean()
            : null
    ]);

    return {
        active: true,
        event: buildDragonEventCreatedPayload({
            event,
            room,
            activator
        }),
        myClaim: myParticipant
            ? serializeClaimParticipant(myParticipant)
            : null
    };
};

const getDragonEventHistory = async ({
    userId,
    view = 'all',
    roomId = '',
    status = '',
    dateFrom = '',
    dateTo = '',
    page = 1,
    limit = 20
}) => {
    const normalizedUserId = normalizeObjectIdString(userId);
    const safePage = Math.max(1, Number.parseInt(page, 10) || 1);
    const safeLimit = Math.max(1, Math.min(50, Number.parseInt(limit, 10) || 20));

    const query = {};
    if (roomId) {
        query.roomId = roomId;
    }
    if (status) {
        query.eventStatus = status;
    }

    const createdAtQuery = {};
    if (dateFrom) {
        const parsed = safeDate(dateFrom);
        if (parsed) createdAtQuery.$gte = parsed;
    }
    if (dateTo) {
        const parsed = safeDate(dateTo);
        if (parsed) createdAtQuery.$lte = parsed;
    }
    if (Object.keys(createdAtQuery).length > 0) {
        query.createdAt = createdAtQuery;
    }

    if (view === 'activated_by_me') {
        query.activatorUserId = normalizedUserId;
    } else if (view === 'won_by_me') {
        const eventIds = await DragonClaimParticipant.find({
            userId: normalizedUserId,
            finalCoinReward: { $gt: 0 }
        }).distinct('eventId');
        query._id = { $in: eventIds };
    } else if (view === 'joined_by_me') {
        const eventIds = await DragonClaimParticipant.find({
            userId: normalizedUserId,
            acceptedTapCount: { $gte: 1 }
        }).distinct('eventId');
        query._id = { $in: eventIds };
    } else {
        const wonEventIds = await DragonClaimParticipant.find({
            userId: normalizedUserId
        }).distinct('eventId');
        query.$or = [
            { activatorUserId: normalizedUserId },
            { _id: { $in: wonEventIds } }
        ];
    }

    const [events, total] = await Promise.all([
        RoomDragonEvent.find(query)
            .sort({ createdAt: -1 })
            .skip((safePage - 1) * safeLimit)
            .limit(safeLimit)
            .lean(),
        RoomDragonEvent.countDocuments(query)
    ]);

    const roomIds = events.map((event) => event.roomId);
    const activatorIds = events.map((event) => event.activatorUserId);
    const eventIds = events.map((event) => event._id);

    const [rooms, activators, myClaims, allClaims] = await Promise.all([
        Room.find({ _id: { $in: roomIds } }).select('name').lean(),
        User.find({ _id: { $in: activatorIds } }).select('username avatar').lean(),
        DragonClaimParticipant.find({
            eventId: { $in: eventIds },
            userId: normalizedUserId
        }).lean(),
        DragonClaimParticipant.find({
            eventId: { $in: eventIds },
            finalCoinReward: { $gt: 0 }
        }).select('eventId finalCoinReward finalRank userId').lean()
    ]);

    const roomMap = new Map(rooms.map((room) => [normalizeObjectIdString(room._id), room]));
    const activatorMap = new Map(activators.map((user) => [normalizeObjectIdString(user._id), user]));
    const myClaimMap = new Map(myClaims.map((claim) => [normalizeObjectIdString(claim.eventId), claim]));
    const winsByEventId = new Map();
    for (const claim of allClaims) {
        const key = normalizeObjectIdString(claim.eventId);
        winsByEventId.set(key, Number(winsByEventId.get(key) || 0) + 1);
    }

    return {
        events: events.map((event) => {
            const normalizedEventId = normalizeObjectIdString(event._id);
            const myClaim = myClaimMap.get(normalizedEventId) || null;
            return {
                ...serializeDragonEventBase(event, {
                    room: roomMap.get(normalizeObjectIdString(event.roomId)) || null,
                    activator: activatorMap.get(normalizeObjectIdString(event.activatorUserId)) || null
                }),
                myClaim: myClaim ? serializeClaimParticipant(myClaim) : null,
                winnerCount: Number(winsByEventId.get(normalizedEventId) || 0)
            };
        }),
        pagination: {
            page: safePage,
            limit: safeLimit,
            total,
            pages: Math.max(1, Math.ceil(total / safeLimit))
        }
    };
};

module.exports = {
    DRAGON_SOCKET_EVENTS,
    activateDragonPacketEvent,
    buildDragonEventCreatedPayload,
    buildDragonTapScoreIncrement,
    calculateDragonDistribution,
    clearDragonEventLifecycle,
    emitDragonPacketUserUpdate,
    getActiveDragonEvent,
    getDragonEventHistory,
    getDragonEventResult,
    getDragonPacketInventoryPayload,
    getDragonPacketProductsPayload,
    grantDragonPacketInventory,
    handleDragonTapSocket,
    initializeDragonPacketRuntime,
    recordDragonRiskLog,
    refundDragonPacketPurchaseByPaymentIntent,
    reconcileStaleDragonEvents,
    scheduleDragonEventLifecycle,
    serializeDragonEventResult,
    serializeDragonPacketInventory,
    settleDragonEvent
};
