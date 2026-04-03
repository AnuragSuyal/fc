const mongoose = require('mongoose');

const AuditLog = require('../models/AuditLog');
const CoinTransfer = require('../models/CoinTransfer');
const CoinTransferLedgerEntry = require('../models/CoinTransferLedgerEntry');
const Message = require('../models/Message');
const PlatformAccount = require('../models/PlatformAccount');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const {
    buildPublicCoinTransferConfig,
    getCoinTransferConfig
} = require('../config/coinTransferConfig');
const {
    buildProgressPayload
} = require('./levelProgressionService');
const {
    ensureFriendConnection
} = require('./friendConnectionService');
const {
    ENTITLEMENT_KEYS,
    getPremiumEntitlement,
    isPremiumEntitlementActive,
    serializePremiumEntitlement
} = require('./premiumEntitlementService');
const {
    buildDirectChatId,
    matchesDirectChatId
} = require('../utils/directChat');

const ACCOUNT_STATUS_RESTRICTED = new Set(['suspended', 'banned', 'deleted']);
const DAY_MS = 24 * 60 * 60 * 1000;

const withSession = (query, session) => (session ? query.session(session) : query);

const withAggregateSession = (aggregate, session) => {
    if (session) {
        aggregate.session(session);
    }
    return aggregate;
};

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

const createCoinTransferError = (code, message, status = 400, extra = {}) => {
    const error = new Error(message || code);
    error.code = code;
    error.status = status;
    Object.assign(error, extra);
    return error;
};

const normalizeObjectIdString = (value) => String(value || '').trim();

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

const startOfUtcDay = (value = new Date()) => new Date(Date.UTC(
    value.getUTCFullYear(),
    value.getUTCMonth(),
    value.getUTCDate(),
    0, 0, 0, 0
));

const startOfUtcMonth = (value = new Date()) => new Date(Date.UTC(
    value.getUTCFullYear(),
    value.getUTCMonth(),
    1,
    0, 0, 0, 0
));

const safeDate = (value) => {
    if (!value) return null;
    const parsed = value instanceof Date ? value : new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
};

const buildPublicReason = (code, fallbackMessage = 'Transfer unavailable right now') => {
    const messages = {
        FEATURE_DISABLED: 'Coin transfers are temporarily unavailable.',
        CHAT_TRANSFER_UNLOCK_REQUIRED: 'Unlock Coin Transfers to send coins in private chat.',
        INVALID_RECIPIENT: 'This user is not available for coin transfers.',
        SELF_TRANSFER_FORBIDDEN: 'You cannot send coins to yourself.',
        FRIENDSHIP_REQUIRED: 'You can only transfer coins to confirmed friends.',
        USER_BLOCKED: 'Coin transfers are unavailable in this chat.',
        CHAT_NOT_ELIGIBLE: 'Coin transfers only work in private friend chats.',
        ACCOUNT_RESTRICTED: 'One of these accounts cannot use coin transfers right now.',
        ACCOUNT_TOO_NEW: 'Your account needs to be older before you can send coins.',
        FRIENDSHIP_TOO_NEW: 'This friendship needs to age a little more before transfers unlock.',
        VERIFICATION_REQUIRED: 'Verify your account before sending coins.',
        MIN_CHAT_ACTIVITY_REQUIRED: 'Chat a little more before sending coins here.',
        INVALID_AMOUNT: 'Enter a valid whole number of coins.',
        MIN_AMOUNT_NOT_MET: 'Minimum transfer amount is 100 coins.',
        MAX_AMOUNT_EXCEEDED: 'That amount is above the per-transfer limit.',
        INSUFFICIENT_BALANCE: 'You do not have enough coins for this transfer.',
        DAILY_LIMIT_REACHED: 'You have reached today\'s coin transfer limit.',
        MONTHLY_LIMIT_REACHED: 'You have reached this month\'s coin transfer limit.',
        UNIQUE_RECEIVER_LIMIT_REACHED: 'You have reached today\'s receiver limit.',
        SAME_SENDER_RECEIVE_LIMIT_REACHED: 'This chat has reached today\'s transfer cap.',
        COOLDOWN_ACTIVE: 'Please wait a little before sending another transfer.',
        SUSPICIOUS_ACTIVITY_REVIEW: 'Transfer is temporarily restricted for safety review.',
        TRANSFER_IN_PROGRESS: 'A transfer is already being processed. Please retry.',
        UNLOCK_PAYMENT_NOT_CONFIGURED: 'Purchases are not configured yet.'
    };

    return {
        code,
        message: messages[code] || fallbackMessage
    };
};

const createUserSnapshot = (user) => ({
    userId: user?._id || null,
    uid: String(user?.uid || ''),
    username: String(user?.username || ''),
    avatar: String(user?.avatar || '')
});

const calculateCoinTransferBreakdown = (amount, config = getCoinTransferConfig()) => {
    const safeAmount = Number.parseInt(amount, 10);
    if (!Number.isInteger(safeAmount) || safeAmount <= 0) {
        throw createCoinTransferError('INVALID_AMOUNT', 'Enter a valid whole number of coins.', 400);
    }

    const receiverAmount = Math.floor((safeAmount * config.receiverPercentage) / 100);
    const platformFee = safeAmount - receiverAmount;

    return {
        grossAmount: safeAmount,
        senderSpend: safeAmount,
        receiverAmount,
        platformFee,
        receiverPercentage: config.receiverPercentage,
        platformPercentage: config.platformPercentage
    };
};

const extractRequestMetadata = (req) => ({
    ip: String(req?.ip || ''),
    forwardedFor: String(req?.get?.('x-forwarded-for') || ''),
    userAgent: String(req?.get?.('user-agent') || ''),
    deviceId: String(req?.get?.('x-device-id') || ''),
    sessionId: String(req?.get?.('x-session-id') || '')
});

const getAccountRestrictionCode = (user, { isSender = false } = {}) => {
    if (!user) {
        return 'INVALID_RECIPIENT';
    }

    if (user.isSystemAccount === true) {
        return 'ACCOUNT_RESTRICTED';
    }

    if (user.deletedAt || user.isDeleted === true || user.accountState?.status === 'deleted') {
        return 'ACCOUNT_RESTRICTED';
    }

    const accountStatus = String(user.accountState?.status || '').trim().toLowerCase();
    if (ACCOUNT_STATUS_RESTRICTED.has(accountStatus)) {
        return 'ACCOUNT_RESTRICTED';
    }

    if (isSender && user.isGuest === true) {
        return 'ACCOUNT_RESTRICTED';
    }

    return '';
};

const createUsageSnapshot = ({
    config,
    amount = 0,
    daily = {},
    monthly = {},
    uniqueReceivers = 0,
    sameReceiverAmount = 0,
    cooldownSecondsRemaining = 0,
    friendshipConnectedAt = null,
    bilateralRecentCount = 0
}) => ({
    daily: {
        amountUsed: Number(daily.amount || 0),
        amountRemaining: Math.max(0, Number(config.dailySendLimitAmount || 0) - Number(daily.amount || 0) - Number(amount || 0)),
        countUsed: Number(daily.count || 0),
        countRemaining: Math.max(0, Number(config.dailySendLimitCount || 0) - Number(daily.count || 0) - (amount > 0 ? 1 : 0))
    },
    monthly: {
        amountUsed: Number(monthly.amount || 0),
        amountRemaining: Math.max(0, Number(config.monthlySendLimitAmount || 0) - Number(monthly.amount || 0) - Number(amount || 0)),
        countUsed: Number(monthly.count || 0),
        countRemaining: Math.max(0, Number(config.monthlySendLimitCount || 0) - Number(monthly.count || 0) - (amount > 0 ? 1 : 0))
    },
    uniqueReceiversToday: Number(uniqueReceivers || 0),
    uniqueReceiversRemainingToday: Math.max(0, Number(config.maxUniqueReceiversPerDay || 0) - Number(uniqueReceivers || 0)),
    sameSenderToReceiverAmountToday: Number(sameReceiverAmount || 0),
    sameSenderToReceiverAmountRemainingToday: Math.max(
        0,
        Number(config.maxReceivedFromSameSenderPerDay || 0) - Number(sameReceiverAmount || 0) - Number(amount || 0)
    ),
    cooldownSecondsRemaining: Math.max(0, Number(cooldownSecondsRemaining || 0)),
    friendshipConnectedAt: friendshipConnectedAt ? new Date(friendshipConnectedAt).toISOString() : null,
    bilateralRecentCount: Number(bilateralRecentCount || 0)
});

const countChatMessagesExchanged = async ({
    leftUserId,
    rightUserId,
    session = null
} = {}) => {
    const query = Message.countDocuments({
        $or: [
            { senderId: leftUserId, recipientId: rightUserId },
            { senderId: rightUserId, recipientId: leftUserId }
        ],
        isDeleted: false
    });
    return session ? query.session(session) : query;
};

const aggregateSumAndCount = async (match, { session = null } = {}) => {
    const pipeline = [
        { $match: match },
        {
            $group: {
                _id: null,
                count: { $sum: 1 },
                amount: { $sum: '$grossAmount' }
            }
        }
    ];

    const results = await withAggregateSession(CoinTransfer.aggregate(pipeline), session);
    return results[0] || { count: 0, amount: 0 };
};

const aggregateDistinctReceivers = async (match, { session = null } = {}) => {
    const pipeline = [
        { $match: match },
        { $group: { _id: '$receiverUserId' } },
        { $group: { _id: null, count: { $sum: 1 } } }
    ];

    const results = await withAggregateSession(CoinTransfer.aggregate(pipeline), session);
    return Number(results[0]?.count || 0);
};

const fetchUsageContext = async ({
    senderUserId,
    receiverUserId = null,
    now = new Date(),
    config = getCoinTransferConfig(),
    session = null
} = {}) => {
    const senderId = new mongoose.Types.ObjectId(senderUserId);
    const receiverId = receiverUserId ? new mongoose.Types.ObjectId(receiverUserId) : null;
    const dayStart = startOfUtcDay(now);
    const monthStart = startOfUtcMonth(now);
    const velocityStart = new Date(now.getTime() - (Number(config.suspiciousVelocityThresholds.windowSeconds || 600) * 1000));
    const circularStart = new Date(now.getTime() - (Number(config.suspiciousVelocityThresholds.circularWindowHours || 24) * 60 * 60 * 1000));

    const completedSenderDayMatch = {
        senderUserId: senderId,
        status: 'completed',
        createdAt: { $gte: dayStart }
    };
    const completedSenderMonthMatch = {
        senderUserId: senderId,
        status: 'completed',
        createdAt: { $gte: monthStart }
    };

    const [daily, monthly, uniqueReceivers, latestTransfer, velocity, sameReceiver, bilateralRecent] = await Promise.all([
        aggregateSumAndCount(completedSenderDayMatch, { session }),
        aggregateSumAndCount(completedSenderMonthMatch, { session }),
        aggregateDistinctReceivers(completedSenderDayMatch, { session }),
        withSession(
            CoinTransfer.findOne({
                senderUserId: senderId,
                status: 'completed'
            })
                .sort({ createdAt: -1 })
                .select('createdAt receiverUserId'),
            session
        ),
        aggregateSumAndCount({
            senderUserId: senderId,
            status: 'completed',
            createdAt: { $gte: velocityStart }
        }, { session }),
        receiverId
            ? aggregateSumAndCount({
                senderUserId: senderId,
                receiverUserId: receiverId,
                status: 'completed',
                createdAt: { $gte: dayStart }
            }, { session })
            : { count: 0, amount: 0 },
        receiverId
            ? aggregateSumAndCount({
                status: 'completed',
                createdAt: { $gte: circularStart },
                $or: [
                    { senderUserId: senderId, receiverUserId: receiverId },
                    { senderUserId: receiverId, receiverUserId: senderId }
                ]
            }, { session })
            : { count: 0, amount: 0 }
    ]);

    const cooldownSecondsRemaining = latestTransfer?.createdAt
        ? Math.max(
            0,
            Math.ceil(
                (new Date(latestTransfer.createdAt).getTime() +
                    (Number(config.cooldownSecondsBetweenTransfers || 0) * 1000) -
                    now.getTime()) /
                    1000
            )
        )
        : 0;

    return {
        daily,
        monthly,
        uniqueReceivers,
        latestTransfer,
        velocity,
        sameReceiverAmount: Number(sameReceiver.amount || 0),
        sameReceiverCount: Number(sameReceiver.count || 0),
        cooldownSecondsRemaining,
        bilateralRecent
    };
};

const addReasonCode = (set, code) => {
    if (code) {
        set.add(code);
    }
};

const serializeTransferForViewer = (transfer, viewerUserId) => {
    const senderId = normalizeObjectIdString(transfer?.senderUserId?._id || transfer?.senderUserId);
    const receiverId = normalizeObjectIdString(transfer?.receiverUserId?._id || transfer?.receiverUserId);
    const viewerId = normalizeObjectIdString(viewerUserId);
    const isSender = senderId === viewerId;

    const senderUser = transfer?.senderUserId?._id ? transfer.senderUserId : transfer?.senderSnapshot;
    const receiverUser = transfer?.receiverUserId?._id ? transfer.receiverUserId : transfer?.receiverSnapshot;
    const peer = isSender ? receiverUser : senderUser;

    return {
        id: transfer?._id?.toString?.() || '',
        transferReferenceId: transfer?.transferReferenceId || '',
        chatId: transfer?.chatId || '',
        senderUserId: senderId,
        receiverUserId: receiverId,
        direction: isSender ? 'sent' : 'received',
        grossAmount: Number(transfer?.grossAmount || 0),
        receiverAmount: Number(transfer?.receiverAmount || 0),
        platformFee: Number(transfer?.platformFee || 0),
        status: transfer?.status || 'pending',
        failureReason: transfer?.failureReason || '',
        createdAt: transfer?.createdAt ? new Date(transfer.createdAt).toISOString() : null,
        completedAt: transfer?.completedAt ? new Date(transfer.completedAt).toISOString() : null,
        feePercentages: {
            receiverPercentage: Number(transfer?.receiverPercentageSnapshot || 0),
            platformPercentage: Number(transfer?.platformPercentageSnapshot || 0)
        },
        peer: {
            id: normalizeObjectIdString(peer?._id || peer?.userId),
            uid: String(peer?.uid || ''),
            username: String(peer?.username || ''),
            avatar: String(peer?.avatar || '')
        },
        message: isSender
            ? `You sent ${Number(transfer?.grossAmount || 0)} coins`
            : `You received ${Number(transfer?.receiverAmount || 0)} coins`
    };
};

const createAuditEntry = async ({
    action,
    transfer = null,
    actorUserId = null,
    requestId = null,
    idempotencyKey = null,
    meta = null,
    session = null
} = {}) => {
    if (!transfer?._id) {
        return null;
    }

    const payload = {
        entityType: 'coin_transfer',
        entityId: transfer._id,
        action,
        actorType: actorUserId ? 'user' : 'system',
        actorId: actorUserId,
        requestId,
        idempotencyKey,
        userId: transfer.senderUserId || null,
        before: null,
        after: {
            status: transfer.status,
            grossAmount: transfer.grossAmount,
            receiverAmount: transfer.receiverAmount,
            platformFee: transfer.platformFee
        },
        meta
    };

    if (session) {
        await AuditLog.create([payload], { session });
        return payload;
    }

    return AuditLog.create(payload);
};

const assessCoinTransferEligibility = async ({
    senderUserId,
    receiverUserId = null,
    chatId = '',
    amount = null,
    session = null,
    now = new Date()
} = {}) => {
    const config = getCoinTransferConfig();
    const publicReasonCodes = new Set();
    const internalRiskFlags = new Set();

    const sender = await withSession(
        User.findById(senderUserId)
            .select(
                'uid username avatar coins gems friends blockedUsers createdAt deletedAt isDeleted isGuest accountState isSystemAccount verification settings totalCoinsSpent stats level xp vipLevel vipTier vipStatus vipStartAt vipExpireAt vipAutoRenew vipPlanDuration vipPurchaseSource monthlyRewardLastClaimedAt vipLastUpdatedAt shopProfile lastLevelUpdatedAt levelMilestoneTier xpStats status'
            ),
        session
    );

    if (!sender) {
        throw createCoinTransferError('INVALID_RECIPIENT', 'Sender not found.', 404);
    }

    const entitlement = await getPremiumEntitlement({
        userId: sender._id,
        entitlementKey: ENTITLEMENT_KEYS.CHAT_COIN_TRANSFER_UNLOCK,
        session
    });
    const unlocked = isPremiumEntitlementActive(entitlement, { now });

    if (!config.featureEnabled) {
        addReasonCode(publicReasonCodes, 'FEATURE_DISABLED');
    }

    addReasonCode(publicReasonCodes, getAccountRestrictionCode(sender, { isSender: true }));

    const accountAgeDays = Math.floor((now.getTime() - new Date(sender.createdAt || now).getTime()) / DAY_MS);
    if (accountAgeDays < Number(config.accountAgeMinDaysForTransfer || 0)) {
        addReasonCode(publicReasonCodes, 'ACCOUNT_TOO_NEW');
    }

    if (config.requireVerifiedAccount && sender.verification?.isVerifiedAccount !== true) {
        addReasonCode(publicReasonCodes, 'VERIFICATION_REQUIRED');
    }

    let receiver = null;
    let resolvedChatId = '';
    let friendship = null;
    let usageContext = {
        daily: { count: 0, amount: 0 },
        monthly: { count: 0, amount: 0 },
        uniqueReceivers: 0,
        sameReceiverAmount: 0,
        sameReceiverCount: 0,
        cooldownSecondsRemaining: 0,
        velocity: { count: 0, amount: 0 },
        bilateralRecent: { count: 0, amount: 0 }
    };
    let chatMessagesExchanged = 0;

    if (receiverUserId) {
        receiver = await withSession(
            User.findByIdOrUid(receiverUserId)
                .select(
                    'uid username avatar coins gems friends blockedUsers createdAt deletedAt isDeleted isGuest accountState isSystemAccount verification settings level xp vipLevel vipTier vipStatus vipStartAt vipExpireAt vipAutoRenew vipPlanDuration vipPurchaseSource monthlyRewardLastClaimedAt vipLastUpdatedAt shopProfile lastLevelUpdatedAt levelMilestoneTier xpStats status'
                ),
            session
        );

        if (!receiver) {
            addReasonCode(publicReasonCodes, 'INVALID_RECIPIENT');
        } else {
            if (normalizeObjectIdString(receiver._id) === normalizeObjectIdString(sender._id)) {
                addReasonCode(publicReasonCodes, 'SELF_TRANSFER_FORBIDDEN');
            }

            addReasonCode(publicReasonCodes, getAccountRestrictionCode(receiver));

            resolvedChatId = buildDirectChatId(sender._id, receiver._id);
            if (!resolvedChatId) {
                addReasonCode(publicReasonCodes, 'CHAT_NOT_ELIGIBLE');
            }

            if (chatId && !matchesDirectChatId(chatId, sender._id, receiver._id)) {
                addReasonCode(publicReasonCodes, 'CHAT_NOT_ELIGIBLE');
            }

            const isFriend = (sender.friends || []).some(
                (friendId) => normalizeObjectIdString(friendId) === normalizeObjectIdString(receiver._id)
            );
            if (!isFriend) {
                addReasonCode(publicReasonCodes, 'FRIENDSHIP_REQUIRED');
            } else {
                friendship = await ensureFriendConnection({
                    leftUser: sender,
                    rightUser: receiver,
                    session
                });
            }

            const isBlocked = (sender.blockedUsers || []).some(
                (blockedId) => normalizeObjectIdString(blockedId) === normalizeObjectIdString(receiver._id)
            ) || (receiver.blockedUsers || []).some(
                (blockedId) => normalizeObjectIdString(blockedId) === normalizeObjectIdString(sender._id)
            );
            if (isBlocked) {
                addReasonCode(publicReasonCodes, 'USER_BLOCKED');
            }

            if (friendship?.connectedAt) {
                const friendshipAgeHours =
                    (now.getTime() - new Date(friendship.connectedAt).getTime()) / (60 * 60 * 1000);
                if (friendshipAgeHours < Number(config.minFriendshipAgeHours || 0)) {
                    addReasonCode(publicReasonCodes, 'FRIENDSHIP_TOO_NEW');
                }
            }

            if (Number(config.minChatMessagesExchanged || 0) > 0) {
                chatMessagesExchanged = await countChatMessagesExchanged({
                    leftUserId: sender._id,
                    rightUserId: receiver._id,
                    session
                });
                if (chatMessagesExchanged < Number(config.minChatMessagesExchanged || 0)) {
                    addReasonCode(publicReasonCodes, 'MIN_CHAT_ACTIVITY_REQUIRED');
                }
            }

            usageContext = await fetchUsageContext({
                senderUserId: sender._id,
                receiverUserId: receiver._id,
                now,
                config,
                session
            });

            if (usageContext.cooldownSecondsRemaining > 0) {
                addReasonCode(publicReasonCodes, 'COOLDOWN_ACTIVE');
            }
        }
    }

    const safeAmount = amount == null || amount === ''
        ? null
        : Number.parseInt(amount, 10);

    let breakdown = null;
    if (safeAmount != null) {
        if (!Number.isInteger(safeAmount) || safeAmount <= 0) {
            addReasonCode(publicReasonCodes, 'INVALID_AMOUNT');
        } else {
            if (safeAmount < Number(config.minTransferAmount || 0)) {
                addReasonCode(publicReasonCodes, 'MIN_AMOUNT_NOT_MET');
            }
            if (safeAmount > Number(config.maxTransferPerTxn || 0)) {
                addReasonCode(publicReasonCodes, 'MAX_AMOUNT_EXCEEDED');
            }
            if (Number(sender.coins || 0) < safeAmount) {
                addReasonCode(publicReasonCodes, 'INSUFFICIENT_BALANCE');
            }

            if ((Number(usageContext.daily.count || 0) + 1) > Number(config.dailySendLimitCount || 0) ||
                (Number(usageContext.daily.amount || 0) + safeAmount) > Number(config.dailySendLimitAmount || 0)) {
                addReasonCode(publicReasonCodes, 'DAILY_LIMIT_REACHED');
            }

            if ((Number(usageContext.monthly.count || 0) + 1) > Number(config.monthlySendLimitCount || 0) ||
                (Number(usageContext.monthly.amount || 0) + safeAmount) > Number(config.monthlySendLimitAmount || 0)) {
                addReasonCode(publicReasonCodes, 'MONTHLY_LIMIT_REACHED');
            }

            const uniqueReceiversReached = receiver &&
                Number(usageContext.sameReceiverCount || 0) === 0 &&
                Number(usageContext.uniqueReceivers || 0) >= Number(config.maxUniqueReceiversPerDay || 0);
            if (uniqueReceiversReached) {
                addReasonCode(publicReasonCodes, 'UNIQUE_RECEIVER_LIMIT_REACHED');
            }

            if ((Number(usageContext.sameReceiverAmount || 0) + safeAmount) > Number(config.maxReceivedFromSameSenderPerDay || 0)) {
                addReasonCode(publicReasonCodes, 'SAME_SENDER_RECEIVE_LIMIT_REACHED');
            }

            const velocityCount = Number(usageContext.velocity?.count || 0);
            const velocityAmount = Number(usageContext.velocity?.amount || 0);
            if (
                (velocityCount + 1) > Number(config.suspiciousVelocityThresholds.maxTransfers || 0) ||
                (velocityAmount + safeAmount) > Number(config.suspiciousVelocityThresholds.maxGrossAmount || 0)
            ) {
                internalRiskFlags.add('velocity_burst');
                addReasonCode(publicReasonCodes, 'SUSPICIOUS_ACTIVITY_REVIEW');
            }

            const bilateralRecentCount = Number(usageContext.bilateralRecent?.count || 0);
            const bilateralRecentAmount = Number(usageContext.bilateralRecent?.amount || 0);
            if (
                receiver &&
                bilateralRecentCount >= Number(config.suspiciousVelocityThresholds.circularTransferCount || 0) &&
                (bilateralRecentAmount + safeAmount) >= Number(config.suspiciousVelocityThresholds.circularGrossAmount || 0)
            ) {
                internalRiskFlags.add('circular_transfer_pattern');
                addReasonCode(publicReasonCodes, 'SUSPICIOUS_ACTIVITY_REVIEW');
            }
        }

        if (Number.isInteger(safeAmount) && safeAmount > 0) {
            breakdown = calculateCoinTransferBreakdown(safeAmount, config);
        }
    }

    if (!unlocked) {
        addReasonCode(publicReasonCodes, 'CHAT_TRANSFER_UNLOCK_REQUIRED');
    }

    const publicReasons = Array.from(publicReasonCodes).map((code) => buildPublicReason(code));
    const reasonCodesExcludingUnlock = Array.from(publicReasonCodes).filter(
        (code) => code !== 'CHAT_TRANSFER_UNLOCK_REQUIRED'
    );
    const eligibleAfterUnlock = reasonCodesExcludingUnlock.length === 0;
    const canPurchaseUnlock = config.featureEnabled &&
        !['ACCOUNT_RESTRICTED', 'ACCOUNT_TOO_NEW', 'VERIFICATION_REQUIRED'].some(
            (code) => publicReasonCodes.has(code)
        );

    return {
        config,
        sender,
        receiver,
        entitlement,
        unlocked,
        canPurchaseUnlock,
        eligibleAfterUnlock,
        canSend: publicReasonCodes.size === 0,
        publicReasons,
        publicReasonCodes: Array.from(publicReasonCodes),
        internalRiskFlags: Array.from(internalRiskFlags),
        breakdown,
        resolvedChatId: resolvedChatId || buildDirectChatId(sender._id, receiver?._id),
        usageSnapshot: createUsageSnapshot({
            config,
            amount: safeAmount || 0,
            daily: usageContext.daily,
            monthly: usageContext.monthly,
            uniqueReceivers: usageContext.uniqueReceivers,
            sameReceiverAmount: usageContext.sameReceiverAmount,
            cooldownSecondsRemaining: usageContext.cooldownSecondsRemaining,
            friendshipConnectedAt: friendship?.connectedAt || null,
            bilateralRecentCount: usageContext.bilateralRecent?.count || 0
        }),
        chatMessagesExchanged
    };
};

const buildEligibilityResponse = (result) => ({
    unlocked: result.unlocked,
    entitlement: result.entitlement ? serializePremiumEntitlement(result.entitlement) : null,
    featureEnabled: result.config.featureEnabled,
    canPurchaseUnlock: result.canPurchaseUnlock,
    eligibleAfterUnlock: result.eligibleAfterUnlock,
    canSend: result.canSend,
    currentBalance: Number(result.sender?.coins || 0),
    chatId: result.resolvedChatId || '',
    receiver: result.receiver
        ? {
            id: result.receiver._id.toString(),
            uid: result.receiver.uid || '',
            username: result.receiver.username || '',
            avatar: result.receiver.avatar || ''
        }
        : null,
    reasons: result.publicReasons,
    limits: buildPublicCoinTransferConfig(),
    usage: result.usageSnapshot,
    preview: result.breakdown
});

const getCoinTransferEligibility = async (params = {}) => {
    const result = await assessCoinTransferEligibility(params);
    return buildEligibilityResponse(result);
};

const previewCoinTransfer = async (params = {}) => {
    const result = await assessCoinTransferEligibility(params);
    return {
        ...buildEligibilityResponse(result),
        validation: {
            canSend: result.canSend,
            reasons: result.publicReasons
        },
        senderSpend: Number(result.breakdown?.senderSpend || 0),
        receiverAmount: Number(result.breakdown?.receiverAmount || 0),
        platformFee: Number(result.breakdown?.platformFee || 0)
    };
};

const createPendingTransferRecord = async ({
    eligibility,
    amount,
    chatId,
    requestMetadata,
    idempotencyKey,
    session = null
} = {}) => {
    const payload = {
        idempotencyKey: idempotencyKey || undefined,
        senderUserId: eligibility.sender._id,
        receiverUserId: eligibility.receiver._id,
        senderSnapshot: createUserSnapshot(eligibility.sender),
        receiverSnapshot: createUserSnapshot(eligibility.receiver),
        chatId,
        grossAmount: amount,
        receiverAmount: eligibility.breakdown.receiverAmount,
        platformFee: eligibility.breakdown.platformFee,
        receiverPercentageSnapshot: eligibility.breakdown.receiverPercentage,
        platformPercentageSnapshot: eligibility.breakdown.platformPercentage,
        status: 'pending',
        requestMetadata,
        riskFlags: eligibility.internalRiskFlags,
        metadata: {
            usageSnapshot: eligibility.usageSnapshot,
            entitlementKey: ENTITLEMENT_KEYS.CHAT_COIN_TRANSFER_UNLOCK
        }
    };

    if (session) {
        const [created] = await CoinTransfer.create([payload], { session });
        return created;
    }

    return CoinTransfer.create(payload);
};

const createFlaggedTransferRecord = async ({
    eligibility,
    amount,
    chatId,
    requestMetadata,
    idempotencyKey,
    failureReason,
    session = null
} = {}) => {
    if (!eligibility?.receiver?._id) {
        throw createCoinTransferError('INVALID_RECIPIENT', 'This user is not available for coin transfers.', 404);
    }

    const payload = {
        idempotencyKey: idempotencyKey || undefined,
        senderUserId: eligibility.sender._id,
        receiverUserId: eligibility.receiver._id,
        senderSnapshot: createUserSnapshot(eligibility.sender),
        receiverSnapshot: createUserSnapshot(eligibility.receiver),
        chatId,
        grossAmount: amount,
        receiverAmount: Number(eligibility.breakdown?.receiverAmount || 0),
        platformFee: Number(eligibility.breakdown?.platformFee || 0),
        receiverPercentageSnapshot: Number(eligibility.breakdown?.receiverPercentage || eligibility.config.receiverPercentage),
        platformPercentageSnapshot: Number(eligibility.breakdown?.platformPercentage || eligibility.config.platformPercentage),
        status: 'flagged',
        failureReason,
        requestMetadata,
        riskFlags: eligibility.internalRiskFlags,
        metadata: {
            usageSnapshot: eligibility.usageSnapshot,
            flaggedAt: new Date().toISOString()
        }
    };

    if (session) {
        const [created] = await CoinTransfer.create([payload], { session });
        return created;
    }

    return CoinTransfer.create(payload);
};

const createTransferLedgerEntries = async ({
    transfer,
    senderBefore,
    senderAfter,
    receiverBefore,
    receiverAfter,
    platformBefore,
    platformAfter,
    session = null
} = {}) => {
    const docs = [
        {
            transferId: transfer._id,
            transferReferenceId: transfer.transferReferenceId,
            ownerType: 'user',
            ownerUserId: transfer.senderUserId,
            ownerKey: '',
            direction: 'debit',
            entryType: 'coin_transfer_sender_debit',
            amount: Number(transfer.grossAmount || 0),
            balanceBefore: Number(senderBefore || 0),
            balanceAfter: Number(senderAfter || 0),
            metadata: {
                chatId: transfer.chatId
            }
        },
        {
            transferId: transfer._id,
            transferReferenceId: transfer.transferReferenceId,
            ownerType: 'user',
            ownerUserId: transfer.receiverUserId,
            ownerKey: '',
            direction: 'credit',
            entryType: 'coin_transfer_receiver_credit',
            amount: Number(transfer.receiverAmount || 0),
            balanceBefore: Number(receiverBefore || 0),
            balanceAfter: Number(receiverAfter || 0),
            metadata: {
                chatId: transfer.chatId
            }
        },
        {
            transferId: transfer._id,
            transferReferenceId: transfer.transferReferenceId,
            ownerType: 'platform',
            ownerUserId: null,
            ownerKey: getCoinTransferConfig().platformAccountKey,
            direction: 'credit',
            entryType: 'coin_transfer_platform_fee',
            amount: Number(transfer.platformFee || 0),
            balanceBefore: Number(platformBefore || 0),
            balanceAfter: Number(platformAfter || 0),
            metadata: {
                chatId: transfer.chatId
            }
        }
    ];

    if (session) {
        await CoinTransferLedgerEntry.create(docs, { session });
        return docs;
    }

    return CoinTransferLedgerEntry.create(docs);
};

const createTransferTransactions = async ({
    transfer,
    senderBefore,
    senderAfter,
    senderGems,
    receiverBefore,
    receiverAfter,
    receiverGems,
    idempotencyKey,
    session = null
} = {}) => {
    const senderTxnPayload = {
        userId: transfer.senderUserId,
        type: 'coin_transfer_sent',
        amount: { coins: -Number(transfer.grossAmount || 0), gems: 0 },
        balanceBefore: { coins: Number(senderBefore || 0), gems: Number(senderGems || 0) },
        balanceAfter: { coins: Number(senderAfter || 0), gems: Number(senderGems || 0) },
        currencyType: 'coins',
        reference: {
            recipientId: transfer.receiverUserId,
            chatId: transfer.chatId,
            coinTransferId: transfer._id
        },
        metadata: {
            transferReferenceId: transfer.transferReferenceId,
            grossAmount: Number(transfer.grossAmount || 0),
            receiverAmount: Number(transfer.receiverAmount || 0),
            platformFee: Number(transfer.platformFee || 0)
        },
        idempotencyKey: idempotencyKey || undefined,
        paymentMethod: 'system',
        status: 'completed',
        description: `Sent ${Number(transfer.grossAmount || 0)} coins in private chat`,
        completedAt: new Date()
    };

    const receiverTxnPayload = {
        userId: transfer.receiverUserId,
        type: 'coin_transfer_received',
        amount: { coins: Number(transfer.receiverAmount || 0), gems: 0 },
        balanceBefore: { coins: Number(receiverBefore || 0), gems: Number(receiverGems || 0) },
        balanceAfter: { coins: Number(receiverAfter || 0), gems: Number(receiverGems || 0) },
        currencyType: 'coins',
        reference: {
            senderId: transfer.senderUserId,
            chatId: transfer.chatId,
            coinTransferId: transfer._id
        },
        metadata: {
            transferReferenceId: transfer.transferReferenceId,
            grossAmount: Number(transfer.grossAmount || 0),
            receiverAmount: Number(transfer.receiverAmount || 0),
            platformFee: Number(transfer.platformFee || 0)
        },
        paymentMethod: 'system',
        status: 'completed',
        description: `Received ${Number(transfer.receiverAmount || 0)} coins from a friend`,
        completedAt: new Date()
    };

    if (session) {
        const [senderTxn] = await Transaction.create([senderTxnPayload], { session });
        const [receiverTxn] = await Transaction.create([receiverTxnPayload], { session });
        return { senderTxn, receiverTxn };
    }

    const senderTxn = await Transaction.create(senderTxnPayload);
    const receiverTxn = await Transaction.create(receiverTxnPayload);
    return { senderTxn, receiverTxn };
};

const createTransferChatMessage = async ({
    transfer,
    sender,
    receiver,
    session = null
} = {}) => {
    const payload = {
        senderId: sender._id,
        recipientId: receiver._id,
        content: `${sender.username} sent ${Number(transfer.grossAmount || 0)} coins to ${receiver.username}`,
        type: 'coin_transfer',
        metadata: {
            coinTransfer: {
                transferId: transfer._id.toString(),
                transferReferenceId: transfer.transferReferenceId,
                grossAmount: Number(transfer.grossAmount || 0),
                receiverAmount: Number(transfer.receiverAmount || 0),
                platformFee: Number(transfer.platformFee || 0),
                senderUserId: sender._id.toString(),
                receiverUserId: receiver._id.toString(),
                senderUsername: sender.username || '',
                receiverUsername: receiver.username || '',
                senderAvatar: sender.avatar || '',
                receiverAvatar: receiver.avatar || '',
                status: transfer.status,
                completedAt: transfer.completedAt ? new Date(transfer.completedAt).toISOString() : null
            }
        }
    };

    let message;
    if (session) {
        const [created] = await Message.create([payload], { session });
        message = created;
    } else {
        message = await Message.create(payload);
    }

    await message.populate([
        { path: 'senderId', select: 'username avatar level' }
    ]);
    return message;
};

const rollbackTransferMutation = async ({
    senderId,
    receiverId,
    grossAmount,
    receiverAmount,
    platformFee,
    platformAccountKey
} = {}) => {
    const rollbackOperations = [];
    if (senderId && grossAmount > 0) {
        rollbackOperations.push(
            User.findByIdAndUpdate(
                senderId,
                {
                    $inc: {
                        coins: grossAmount,
                        totalCoinsSpent: -grossAmount,
                        'stats.totalSpent': -grossAmount
                    }
                }
            )
        );
    }
    if (receiverId && receiverAmount > 0) {
        rollbackOperations.push(
            User.findByIdAndUpdate(
                receiverId,
                {
                    $inc: {
                        coins: -receiverAmount
                    }
                }
            )
        );
    }
    if (platformAccountKey && platformFee > 0) {
        rollbackOperations.push(
            PlatformAccount.findOneAndUpdate(
                { key: platformAccountKey, balanceCoins: { $gte: platformFee } },
                {
                    $inc: {
                        balanceCoins: -platformFee
                    }
                }
            )
        );
    }
    await Promise.allSettled(rollbackOperations);
};

const executeCoinTransfer = async ({
    senderUserId,
    receiverUserId,
    chatId = '',
    amount,
    idempotencyKey = '',
    req = null,
    io = null,
    redis = null
} = {}) => {
    const safeAmount = Number.parseInt(amount, 10);
    const requestMetadata = extractRequestMetadata(req);
    const config = getCoinTransferConfig();
    const normalizedSenderId = normalizeObjectIdString(senderUserId);
    const normalizedReceiverId = normalizeObjectIdString(receiverUserId);
    const resolvedChatId = buildDirectChatId(normalizedSenderId, normalizedReceiverId);

    if (!resolvedChatId || (chatId && chatId !== resolvedChatId)) {
        throw createCoinTransferError('CHAT_NOT_ELIGIBLE', 'Coin transfers only work in private friend chats.', 400);
    }

    if (idempotencyKey) {
        const existingTransfer = await CoinTransfer.findOne({
            senderUserId,
            idempotencyKey
        })
            .populate('senderUserId', 'username avatar uid coins gems level xp vipLevel vipTier vipStatus vipStartAt vipExpireAt vipAutoRenew vipPlanDuration vipPurchaseSource monthlyRewardLastClaimedAt vipLastUpdatedAt shopProfile lastLevelUpdatedAt levelMilestoneTier xpStats status')
            .populate('receiverUserId', 'username avatar uid coins gems level xp vipLevel vipTier vipStatus vipStartAt vipExpireAt vipAutoRenew vipPlanDuration vipPurchaseSource monthlyRewardLastClaimedAt vipLastUpdatedAt shopProfile lastLevelUpdatedAt levelMilestoneTier xpStats status');

        if (existingTransfer && existingTransfer.status === 'completed') {
            const sender = existingTransfer.senderUserId;
            return {
                success: true,
                duplicate: true,
                transfer: serializeTransferForViewer(existingTransfer, senderUserId),
                newBalance: buildProgressPayload(sender, {
                    source: 'coin_transfer_sent'
                })
            };
        }
        if (existingTransfer && existingTransfer.status === 'pending') {
            throw createCoinTransferError(
                'TRANSFER_IN_PROGRESS',
                'A transfer is already being processed. Please retry.',
                409
            );
        }
        if (existingTransfer && existingTransfer.status === 'flagged') {
            throw createCoinTransferError(
                'SUSPICIOUS_ACTIVITY_REVIEW',
                'Transfer is temporarily restricted for safety review.',
                403
            );
        }
    }

    const senderLockKey = `coin-transfer:sender:${normalizedSenderId}`;
    const pairLockKey = `coin-transfer:pair:${resolvedChatId}`;
    const senderLocked = await acquireRedisLock(redis, senderLockKey, 30);
    if (!senderLocked) {
        throw createCoinTransferError('TRANSFER_IN_PROGRESS', 'A transfer is already being processed. Please retry.', 409);
    }

    const pairLocked = await acquireRedisLock(redis, pairLockKey, 30);
    if (!pairLocked) {
        await releaseRedisLock(redis, senderLockKey);
        throw createCoinTransferError('TRANSFER_IN_PROGRESS', 'A transfer is already being processed. Please retry.', 409);
    }

    try {
        const result = await runWithOptionalTransaction(async (session) => {
            const eligibility = await assessCoinTransferEligibility({
                senderUserId,
                receiverUserId,
                chatId: resolvedChatId,
                amount: safeAmount,
                session
            });

            if (!eligibility.canSend) {
                if (eligibility.publicReasonCodes.includes('SUSPICIOUS_ACTIVITY_REVIEW')) {
                    const flaggedTransfer = await createFlaggedTransferRecord({
                        eligibility,
                        amount: safeAmount,
                        chatId: resolvedChatId,
                        requestMetadata,
                        idempotencyKey,
                        failureReason: 'suspicious_activity_review',
                        session
                    });
                    await createAuditEntry({
                        action: 'coin_transfer.flagged',
                        transfer: flaggedTransfer,
                        actorUserId: senderUserId,
                        requestId: req?.id || null,
                        idempotencyKey,
                        meta: {
                            riskFlags: eligibility.internalRiskFlags
                        },
                        session
                    });
                    throw createCoinTransferError(
                        'SUSPICIOUS_ACTIVITY_REVIEW',
                        'Transfer is temporarily restricted for safety review.',
                        403
                    );
                }

                const firstReason = eligibility.publicReasons[0] || buildPublicReason('CHAT_NOT_ELIGIBLE');
                throw createCoinTransferError(firstReason.code, firstReason.message, 400);
            }

            const pendingTransfer = await createPendingTransferRecord({
                eligibility,
                amount: safeAmount,
                chatId: resolvedChatId,
                requestMetadata,
                idempotencyKey,
                session
            });

            let senderBefore = Number(eligibility.sender.coins || 0);
            let receiverBefore = Number(eligibility.receiver.coins || 0);
            let platformBefore = 0;
            let senderAfter = senderBefore;
            let receiverAfter = receiverBefore;
            let platformAfter = platformBefore;
            let sender = eligibility.sender;
            let receiver = eligibility.receiver;
            let platformAccount = null;

            try {
                if (session) {
                    sender.coins = senderBefore - safeAmount;
                    sender.totalCoinsSpent = Number(sender.totalCoinsSpent || 0) + safeAmount;
                    sender.stats = {
                        ...(sender.stats || {}),
                        totalSpent: Number(sender.stats?.totalSpent || 0) + safeAmount
                    };
                    receiver.coins = receiverBefore + eligibility.breakdown.receiverAmount;

                    platformAccount = await withSession(
                        PlatformAccount.findOne({ key: config.platformAccountKey }),
                        session
                    );
                    if (!platformAccount) {
                        platformAccount = new PlatformAccount({
                            key: config.platformAccountKey,
                            label: 'Chat Coin Transfer Margin',
                            balanceCoins: 0
                        });
                    }
                    platformBefore = Number(platformAccount.balanceCoins || 0);
                    platformAccount.balanceCoins = platformBefore + eligibility.breakdown.platformFee;

                    senderAfter = Number(sender.coins || 0);
                    receiverAfter = Number(receiver.coins || 0);
                    platformAfter = Number(platformAccount.balanceCoins || 0);

                    await sender.save({ session });
                    await receiver.save({ session });
                    await platformAccount.save({ session });
                } else {
                    const updatedSender = await User.findOneAndUpdate(
                        {
                            _id: sender._id,
                            coins: { $gte: safeAmount }
                        },
                        {
                            $inc: {
                                coins: -safeAmount,
                                totalCoinsSpent: safeAmount,
                                'stats.totalSpent': safeAmount
                            }
                        },
                        {
                            returnDocument: 'after'
                        }
                    );

                    if (!updatedSender) {
                        throw createCoinTransferError('INSUFFICIENT_BALANCE', 'You do not have enough coins for this transfer.', 409);
                    }

                    sender = updatedSender;
                    senderAfter = Number(sender.coins || 0);

                    const updatedReceiver = await User.findByIdAndUpdate(
                        receiver._id,
                        {
                            $inc: {
                                coins: eligibility.breakdown.receiverAmount
                            }
                        },
                        {
                            returnDocument: 'after'
                        }
                    );

                    if (!updatedReceiver) {
                        throw createCoinTransferError('INVALID_RECIPIENT', 'This user is not available for coin transfers.', 404);
                    }

                    receiver = updatedReceiver;
                    receiverAfter = Number(receiver.coins || 0);

                    platformAccount = await PlatformAccount.findOne({ key: config.platformAccountKey });
                    if (!platformAccount) {
                        platformAccount = await PlatformAccount.create({
                            key: config.platformAccountKey,
                            label: 'Chat Coin Transfer Margin',
                            balanceCoins: 0
                        });
                    }
                    platformBefore = Number(platformAccount.balanceCoins || 0);
                    platformAccount.balanceCoins = platformBefore + eligibility.breakdown.platformFee;
                    platformAfter = Number(platformAccount.balanceCoins || 0);
                    await platformAccount.save();
                }

                pendingTransfer.status = 'completed';
                pendingTransfer.completedAt = new Date();
                pendingTransfer.senderSnapshot = createUserSnapshot(sender);
                pendingTransfer.receiverSnapshot = createUserSnapshot(receiver);
                await pendingTransfer.save(session ? { session } : undefined);

                await createTransferLedgerEntries({
                    transfer: pendingTransfer,
                    senderBefore,
                    senderAfter,
                    receiverBefore,
                    receiverAfter,
                    platformBefore,
                    platformAfter,
                    session
                });

                const { senderTxn } = await createTransferTransactions({
                    transfer: pendingTransfer,
                    senderBefore,
                    senderAfter,
                    senderGems: sender.gems,
                    receiverBefore,
                    receiverAfter,
                    receiverGems: receiver.gems,
                    idempotencyKey,
                    session
                });

                const transferMessage = await createTransferChatMessage({
                    transfer: pendingTransfer,
                    sender,
                    receiver,
                    session
                });

                await createAuditEntry({
                    action: 'coin_transfer.completed',
                    transfer: pendingTransfer,
                    actorUserId: senderUserId,
                    requestId: req?.id || null,
                    idempotencyKey,
                    meta: {
                        transactionId: senderTxn.transactionId
                    },
                    session
                });

                return {
                    transfer: pendingTransfer,
                    sender,
                    receiver,
                    senderTxn,
                    transferMessage
                };
            } catch (error) {
                if (!session) {
                    await rollbackTransferMutation({
                        senderId: sender._id,
                        receiverId: receiver?._id,
                        grossAmount: safeAmount,
                        receiverAmount: eligibility.breakdown.receiverAmount,
                        platformFee: eligibility.breakdown.platformFee,
                        platformAccountKey: config.platformAccountKey
                    });
                }

                pendingTransfer.status = 'failed';
                pendingTransfer.failureReason = error.code || error.message || 'coin_transfer_failed';
                pendingTransfer.failedAt = new Date();
                await pendingTransfer.save(session ? { session } : undefined);

                await createAuditEntry({
                    action: 'coin_transfer.failed',
                    transfer: pendingTransfer,
                    actorUserId: senderUserId,
                    requestId: req?.id || null,
                    idempotencyKey,
                    meta: {
                        errorCode: error.code || '',
                        errorMessage: error.message || ''
                    },
                    session
                });

                throw error;
            }
        });

        if (io) {
            const senderBalance = buildProgressPayload(result.sender, {
                source: 'coin_transfer_sent'
            });
            const receiverBalance = buildProgressPayload(result.receiver, {
                source: 'coin_transfer_received'
            });
            const transferEvent = {
                transfer: serializeTransferForViewer(result.transfer, senderUserId),
                senderBalance,
                receiverBalance
            };

            io.to(`user:${normalizedSenderId}`).emit('balance_update', senderBalance);
            io.to(`user:${normalizedReceiverId}`).emit('balance_update', receiverBalance);
            io.to(`user:${normalizedSenderId}`).emit('coin_transfer:updated', {
                ...transferEvent,
                type: 'coin_transfer_completed',
                viewerDirection: 'sent'
            });
            io.to(`user:${normalizedReceiverId}`).emit('coin_transfer:updated', {
                ...transferEvent,
                type: 'coin_transfer_completed',
                viewerDirection: 'received'
            });
            const dmPayload = {
                message: result.transferMessage,
                from: {
                    id: normalizedSenderId,
                    username: result.sender.username
                }
            };
            io.to(`user:${normalizedSenderId}`).emit('dm:received', dmPayload);
            io.to(`user:${normalizedReceiverId}`).emit('dm:received', dmPayload);
        }

        return {
            success: true,
            transfer: serializeTransferForViewer(result.transfer, senderUserId),
            transactionId: result.senderTxn.transactionId,
            newBalance: buildProgressPayload(result.sender, {
                source: 'coin_transfer_sent'
            }),
            receiverBalance: buildProgressPayload(result.receiver, {
                source: 'coin_transfer_received'
            }),
            message: result.transferMessage
        };
    } finally {
        await Promise.all([
            releaseRedisLock(redis, senderLockKey),
            releaseRedisLock(redis, pairLockKey)
        ]);
    }
};

const getCoinTransferHistory = async ({
    userId,
    view = 'all',
    status = '',
    chatId = '',
    dateFrom = '',
    dateTo = '',
    page = 1,
    limit = 20
} = {}) => {
    const normalizedView = String(view || 'all').trim().toLowerCase();
    const normalizedStatus = String(status || '').trim().toLowerCase();
    const normalizedChatId = String(chatId || '').trim();
    const safePage = Math.max(Number.parseInt(page, 10) || 1, 1);
    const safeLimit = Math.min(Math.max(Number.parseInt(limit, 10) || 20, 1), 100);

    const query = {};
    if (normalizedView === 'sent') {
        query.senderUserId = userId;
    } else if (normalizedView === 'received') {
        query.receiverUserId = userId;
    } else {
        query.$or = [
            { senderUserId: userId },
            { receiverUserId: userId }
        ];
    }

    if (normalizedStatus) {
        query.status = normalizedStatus;
    }

    if (normalizedChatId) {
        query.chatId = normalizedChatId;
    }

    const createdAt = {};
    const safeDateFrom = safeDate(dateFrom);
    const safeDateTo = safeDate(dateTo);
    if (safeDateFrom) {
        createdAt.$gte = safeDateFrom;
    }
    if (safeDateTo) {
        createdAt.$lte = safeDateTo;
    }
    if (Object.keys(createdAt).length > 0) {
        query.createdAt = createdAt;
    }

    const [transfers, total] = await Promise.all([
        CoinTransfer.find(query)
            .populate('senderUserId', 'uid username avatar')
            .populate('receiverUserId', 'uid username avatar')
            .sort({ createdAt: -1 })
            .limit(safeLimit)
            .skip((safePage - 1) * safeLimit),
        CoinTransfer.countDocuments(query)
    ]);

    return {
        transfers: transfers.map((transfer) => serializeTransferForViewer(transfer, userId)),
        pagination: {
            page: safePage,
            limit: safeLimit,
            total,
            pages: Math.ceil(total / safeLimit)
        }
    };
};

module.exports = {
    ENTITLEMENT_KEYS,
    assessCoinTransferEligibility,
    buildEligibilityResponse,
    calculateCoinTransferBreakdown,
    createCoinTransferError,
    executeCoinTransfer,
    getCoinTransferEligibility,
    getCoinTransferHistory,
    previewCoinTransfer,
    serializeTransferForViewer
};
