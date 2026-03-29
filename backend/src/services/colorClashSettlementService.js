const mongoose = require('mongoose');

const AuditLog = require('../models/AuditLog');
const ColorClashMatch = require('../models/ColorClashMatch');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const WalletEscrow = require('../models/WalletEscrow');
const antiFraudService = require('./colorClashAntiFraudService');
const seasonService = require('./colorClashSeasonService');
const telemetry = require('./colorClashTelemetry');

const GAME_ID = 'color_clash';
const HOLD_EXPIRY_MS = 15 * 60 * 1000;
const SETTLEMENT_LOCK_TTL_MS = 10 * 1000;
const DEFAULT_HOUSE_FEE_BPS = 500;
const DEFAULT_SINK_FEE_BPS = 200;
const DEFAULT_PAYOUTS = Object.freeze([{ place: 1, bps: 10000 }]);
const TERMINAL_SETTLEMENT_STATUSES = new Set(['settled', 'refunded', 'skipped']);
const PRESTART_ESCROW_STATUSES = new Set(['held']);
const LOCKED_ESCROW_STATUSES = new Set(['locked', 'settled']);

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value.toString === 'function') return value.toString();
    return String(value);
};

const createServiceError = (code, message, status = 400, extra = {}) => {
    const error = new Error(message || code);
    error.code = code;
    error.status = status;
    Object.assign(error, extra);
    return error;
};

const applySession = (query, session) => (session ? query.session(session) : query);

const sortByStableId = (items = [], getId = (entry) => entry) => items
    .slice()
    .sort((left, right) => toIdString(getId(left)).localeCompare(toIdString(getId(right))));

const buildSettlementKey = (matchId) => `cc:settlement:${toIdString(matchId)}`;
const buildHoldIdempotencyKey = (matchId, userId) => `cc:hold:${toIdString(matchId)}:${toIdString(userId)}`;
const buildRefundIdempotencyKey = (matchId, userId) => `cc:refund:${toIdString(matchId)}:${toIdString(userId)}`;
const buildPayoutIdempotencyKey = (matchId, userId) => `cc:payout:${toIdString(matchId)}:${toIdString(userId)}`;

const normalizePayouts = (payouts = DEFAULT_PAYOUTS) => {
    const normalized = (Array.isArray(payouts) && payouts.length ? payouts : DEFAULT_PAYOUTS)
        .map((entry) => ({
            place: Number(entry.place || 0),
            bps: Number(entry.bps || 0)
        }))
        .filter((entry) => entry.place > 0 && entry.bps > 0)
        .sort((left, right) => left.place - right.place);

    const seenPlaces = new Set();
    for (const entry of normalized) {
        if (seenPlaces.has(entry.place)) {
            throw createServiceError('INVALID_PAYOUT_CONFIG', 'Color Clash payout places must be unique', 400);
        }
        seenPlaces.add(entry.place);
    }

    const totalBps = normalized.reduce((total, entry) => total + entry.bps, 0);
    if (totalBps !== 10000) {
        throw createServiceError('INVALID_PAYOUT_CONFIG', 'Color Clash payout shares must total 10000 bps', 400);
    }

    return normalized;
};

const normalizeStakeConfig = (stake = {}) => {
    const entryFee = Math.max(0, Number(stake.entryFee || 0));
    if (entryFee <= 0 || stake.currency !== 'coins') {
        return {
            currency: 'none',
            entryFee: 0,
            payouts: DEFAULT_PAYOUTS.map((entry) => ({ ...entry })),
            houseFeeBps: 0,
            sinkFeeBps: 0
        };
    }

    const houseFeeBps = Math.max(0, Number.isFinite(Number(stake.houseFeeBps))
        ? Number(stake.houseFeeBps)
        : DEFAULT_HOUSE_FEE_BPS);
    const sinkFeeBps = Math.max(0, Number.isFinite(Number(stake.sinkFeeBps))
        ? Number(stake.sinkFeeBps)
        : DEFAULT_SINK_FEE_BPS);
    if ((houseFeeBps + sinkFeeBps) >= 10000) {
        throw createServiceError('INVALID_STAKE_FEES', 'Color Clash fee configuration leaves no distributable prize pool', 400);
    }

    return {
        currency: 'coins',
        entryFee,
        payouts: normalizePayouts(stake.payouts),
        houseFeeBps,
        sinkFeeBps
    };
};

const requiresEscrow = (stake = {}) => stake?.currency === 'coins' && Number(stake?.entryFee || 0) > 0;

const allocateAmountByWeight = (total, items, getWeight, getKey) => {
    const allocations = new Map();
    const normalizedTotal = Math.max(0, Number(total || 0));
    if (!normalizedTotal || !Array.isArray(items) || !items.length) {
        return allocations;
    }

    const weightedItems = items
        .map((item) => ({
            item,
            key: toIdString(getKey(item)),
            weight: Math.max(0, Number(getWeight(item) || 0))
        }))
        .filter((entry) => entry.key);
    const totalWeight = weightedItems.reduce((sum, entry) => sum + entry.weight, 0);
    if (!weightedItems.length || totalWeight <= 0) {
        return allocations;
    }

    const sorted = weightedItems.sort((left, right) => left.key.localeCompare(right.key));
    let allocated = 0;
    for (let index = 0; index < sorted.length; index += 1) {
        const entry = sorted[index];
        const share = index === (sorted.length - 1)
            ? normalizedTotal - allocated
            : Math.floor((normalizedTotal * entry.weight) / totalWeight);
        allocations.set(entry.key, share);
        allocated += share;
    }
    return allocations;
};

class ColorClashSettlementService {
    constructor({ redis = null, io = null, now = () => Date.now() } = {}) {
        this.redis = redis;
        this.io = io;
        this.now = now;
    }

    configure({ redis, io, now } = {}) {
        if (redis) this.redis = redis;
        if (io) this.io = io;
        if (now) this.now = now;
        antiFraudService.configure({ now: this.now });
        seasonService.configure({ redis: this.redis, now: this.now });
        return this;
    }

    requireRedis() {
        if (!this.redis) {
            throw createServiceError('REDIS_UNAVAILABLE', 'Color Clash settlement requires Redis', 503);
        }
        return this.redis;
    }

    settlementLockKey(matchId) {
        return `cc:lock:settlement:${toIdString(matchId)}`;
    }

    async withSettlementLock(matchId, work) {
        const redis = this.requireRedis();
        const lockKey = this.settlementLockKey(matchId);
        const token = `${this.now()}:${Math.random()}`;
        const acquired = await redis.set(lockKey, token, { NX: true, PX: SETTLEMENT_LOCK_TTL_MS });
        if (!acquired) {
            throw createServiceError('SETTLEMENT_LOCK_UNAVAILABLE', 'Another Color Clash settlement action is in progress', 409);
        }

        try {
            return await work();
        } finally {
            const currentValue = await redis.get(lockKey);
            if (currentValue === token) {
                await redis.del(lockKey);
            }
        }
    }

    async runInTransaction(label, work) {
        const session = await mongoose.startSession();
        let result;
        try {
            await session.withTransaction(async () => {
                result = await work(session);
            });
            return result;
        } catch (error) {
            const message = String(error?.message || '');
            if (
                message.includes('Transaction numbers are only allowed') ||
                message.includes('replica set member') ||
                message.includes('This MongoDB deployment does not support retryable writes')
            ) {
                throw createServiceError(
                    'TRANSACTIONS_REQUIRED',
                    `Color Clash ${label} requires MongoDB transactions backed by a replica set or mongos`,
                    503
                );
            }
            throw error;
        } finally {
            await session.endSession();
        }
    }

    emitBalanceUpdate(userId, balance) {
        if (!this.io || !userId) return;
        this.io.to(`user:${toIdString(userId)}`).emit('balance_update', balance);
    }

    buildEscrowReason(tableMode) {
        if (tableMode === 'ranked') return 'ranked_entry';
        if (tableMode === 'gold_stake') return 'queue_stake';
        if (tableMode === 'custom_chaos') return 'friend_stake';
        return 'stake_entry';
    }

    buildAuditEntry({
        entityType,
        entityId,
        action,
        actorType = 'system',
        actorId = null,
        requestId = null,
        idempotencyKey = null,
        userId = null,
        roomId = null,
        matchId = null,
        before = null,
        after = null,
        meta = null
    }) {
        return {
            entityType,
            entityId,
            action,
            actorType,
            actorId,
            requestId,
            idempotencyKey,
            userId,
            roomId,
            matchId,
            before,
            after,
            meta,
            createdAt: new Date(this.now())
        };
    }

    isCasualLikeTable(tableMode) {
        return ['casual_free', 'friend_room', 'custom_chaos'].includes(tableMode);
    }

    extractWinningUserIds(matchDoc) {
        const placements = Array.isArray(matchDoc?.roundResult?.placements)
            ? matchDoc.roundResult.placements
            : [];
        return placements
            .filter((entry) => Number(entry.placement || 0) === 1 && entry.userId)
            .map((entry) => toIdString(entry.userId));
    }

    async applyProfileStatsForMatch({ session, matchDoc }) {
        if (matchDoc.profileStatsAppliedAt) {
            return {
                skipped: true
            };
        }

        const winnerIds = new Set(this.extractWinningUserIds(matchDoc));
        const playerIds = (matchDoc.players || []).map((player) => toIdString(player.userId)).filter(Boolean);
        if (!playerIds.length) {
            return {
                skipped: true
            };
        }

        const userDocs = await applySession(User.find({
            _id: { $in: playerIds }
        }).select('gameStats'), session);

        for (const userDoc of userDocs) {
            userDoc.gameStats = userDoc.gameStats || {};
            userDoc.gameStats.colorClash = userDoc.gameStats.colorClash || {};
            userDoc.gameStats.colorClash.played = Number(userDoc.gameStats.colorClash.played || 0) + 1;
            if (this.isCasualLikeTable(matchDoc.tableMode)) {
                userDoc.gameStats.colorClash.casualPlayed = Number(userDoc.gameStats.colorClash.casualPlayed || 0) + 1;
            }
            if (winnerIds.has(toIdString(userDoc._id))) {
                userDoc.gameStats.colorClash.won = Number(userDoc.gameStats.colorClash.won || 0) + 1;
                if (this.isCasualLikeTable(matchDoc.tableMode)) {
                    userDoc.gameStats.colorClash.casualWon = Number(userDoc.gameStats.colorClash.casualWon || 0) + 1;
                }
            }
            userDoc.gameStats.colorClash.level = Math.floor(Number(userDoc.gameStats.colorClash.won || 0) / 10) + 1;
            await userDoc.save({ session });
        }

        matchDoc.profileStatsAppliedAt = new Date(this.now());
        await matchDoc.save({ session });

        return {
            skipped: false,
            appliedTo: userDocs.length
        };
    }

    async applyRankedProgressionAfterSettlement({ matchId, summary, actorType = 'system', actorId = null, requestId = null }) {
        const matchDoc = await ColorClashMatch.findById(matchId)
            .select('tableMode settlement rankProgression seasonId')
            .lean();
        if (!matchDoc || matchDoc.tableMode !== 'ranked') {
            return {
                skipped: true
            };
        }

        if (!['settled', 'skipped'].includes(matchDoc.settlement?.status)) {
            return {
                skipped: true,
                reason: 'settlement_not_final'
            };
        }

        try {
            const result = await seasonService.applyRankedMatchResult({
                matchId,
                requestId,
                actorType,
                actorId
            });
            telemetry.info('rank_update_success', {
                matchId,
                status: result?.alreadyApplied ? 'already_applied' : 'applied'
            });
            return {
                skipped: false,
                result
            };
        } catch (error) {
            telemetry.error('rank_update_failed', {
                matchId,
                code: error.code || 'RANK_APPLY_FAILED',
                message: error.message
            });
            await ColorClashMatch.findByIdAndUpdate(matchId, {
                $set: {
                    'rankProgression.status': 'failed',
                    'rankProgression.error': error.code || error.message || 'RANK_APPLY_FAILED'
                }
            }).catch(() => {});
            return {
                skipped: false,
                failed: true,
                error: error.code || error.message || 'RANK_APPLY_FAILED',
                settlement: summary
            };
        }
    }

    async precheckStakeEntry({ user = null, userId = null, entryFee = 0, currency = 'coins' }) {
        const normalizedEntryFee = Math.max(0, Number(entryFee || 0));
        if (currency !== 'coins' || normalizedEntryFee <= 0) {
            return {
                eligible: true,
                skipped: true,
                requiredAmount: 0
            };
        }

        const userDoc = user || await User.findById(userId).select('coins settings');
        if (!userDoc) {
            throw createServiceError('USER_NOT_FOUND', 'Color Clash player was not found', 404);
        }

        if (userDoc.settings?.colorClash?.stakeLock?.active || userDoc.settings?.colorClash?.stakeAccessLocked) {
            throw createServiceError(
                'STAKE_ACCESS_LOCKED',
                userDoc.settings?.colorClash?.stakeLock?.reason ||
                userDoc.settings?.colorClash?.stakeAccessLockReason ||
                'Stake Color Clash access is temporarily locked for this account',
                403,
                { failedUserId: toIdString(userDoc._id || userId) }
            );
        }

        if (Number(userDoc.coins || 0) < normalizedEntryFee) {
            throw createServiceError(
                'INSUFFICIENT_COINS',
                'Not enough coins to enter this Color Clash stake table',
                403,
                { failedUserId: toIdString(userDoc._id || userId) }
            );
        }

        return {
            eligible: true,
            skipped: false,
            requiredAmount: normalizedEntryFee,
            balance: Number(userDoc.coins || 0)
        };
    }

    async ensureEntryHoldsForMatch({
        matchId,
        roomId,
        seasonId = null,
        tableMode = 'gold_stake',
        players = [],
        stakeConfig = {},
        requestId = null,
        actorType = 'system',
        actorId = null
    }) {
        const normalizedStake = normalizeStakeConfig(stakeConfig);
        if (!requiresEscrow(normalizedStake)) {
            return {
                skipped: true,
                duplicate: false,
                escrows: [],
                totalEscrowed: 0
            };
        }

        const participantList = players
            .map((entry) => ({
                userId: toIdString(entry.userId || entry),
                seatIndex: Number.isInteger(entry.seatIndex) ? entry.seatIndex : Number.MAX_SAFE_INTEGER
            }))
            .filter((entry) => entry.userId)
            .sort((left, right) => left.seatIndex - right.seatIndex || left.userId.localeCompare(right.userId));

        if (!participantList.length) {
            throw createServiceError('NO_MATCH_PLAYERS', 'Color Clash stake holds require at least one player', 400);
        }

        const settlementKey = buildSettlementKey(matchId);
        const nowDate = new Date(this.now());
        const expiresAt = new Date(this.now() + HOLD_EXPIRY_MS);

        const result = await this.withSettlementLock(matchId, () => this.runInTransaction('stake hold creation', async (session) => {
            const matchDoc = await applySession(ColorClashMatch.findById(matchId), session);
            if (!matchDoc) {
                throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for hold creation', 404);
            }

            if (TERMINAL_SETTLEMENT_STATUSES.has(matchDoc.settlement?.status)) {
                return {
                    skipped: false,
                    duplicate: true,
                    escrows: await applySession(WalletEscrow.find({ matchId, userId: { $in: participantList.map((entry) => entry.userId) } }), session),
                    totalEscrowed: Number(matchDoc.settlement?.totalEscrowed || 0)
                };
            }

            const existingEscrows = await applySession(
                WalletEscrow.find({
                    matchId,
                    userId: { $in: participantList.map((entry) => entry.userId) }
                }),
                session
            );
            const existingByUserId = new Map(existingEscrows.map((entry) => [toIdString(entry.userId), entry]));

            for (const escrow of existingEscrows) {
                if (!['held', 'locked', 'settled'].includes(escrow.status)) {
                    throw createServiceError(
                        'ESCROW_STATE_CONFLICT',
                        'Color Clash stake hold is in an unexpected state',
                        409,
                        { failedUserId: toIdString(escrow.userId) }
                    );
                }
            }

            const missingParticipants = participantList.filter((entry) => !existingByUserId.has(entry.userId));
            if (!missingParticipants.length) {
                const totalEscrowed = existingEscrows.reduce((sum, escrow) => sum + Number(escrow.amount || 0), 0);
                return {
                    skipped: false,
                    duplicate: true,
                    escrows: existingEscrows,
                    totalEscrowed
                };
            }

            const userDocs = await applySession(
                User.find({ _id: { $in: missingParticipants.map((entry) => entry.userId) } }).select('coins gems settings'),
                session
            );
            const userById = new Map(userDocs.map((entry) => [toIdString(entry._id), entry]));
            const balanceUpdates = [];
            const auditEntries = [];

            for (const participant of missingParticipants) {
                const userDoc = userById.get(participant.userId);
                if (!userDoc) {
                    throw createServiceError('USER_NOT_FOUND', 'Color Clash player was not found during hold creation', 404, {
                        failedUserId: participant.userId
                    });
                }

                await this.precheckStakeEntry({
                    user: userDoc,
                    entryFee: normalizedStake.entryFee,
                    currency: normalizedStake.currency
                });

                const holdTransactionId = new mongoose.Types.ObjectId();
                const escrowId = new mongoose.Types.ObjectId();
                const balanceBeforeCoins = Number(userDoc.coins || 0);
                const balanceBeforeGems = Number(userDoc.gems || 0);
                userDoc.coins = balanceBeforeCoins - normalizedStake.entryFee;
                await userDoc.save({ session });

                await Transaction.create([{
                    _id: holdTransactionId,
                    userId: userDoc._id,
                    type: 'game_escrow_hold',
                    amount: { coins: -normalizedStake.entryFee },
                    balanceBefore: {
                        coins: balanceBeforeCoins,
                        gems: balanceBeforeGems
                    },
                    balanceAfter: {
                        coins: Number(userDoc.coins || 0),
                        gems: balanceBeforeGems
                    },
                    reference: {
                        roomId,
                        matchId,
                        seasonId,
                        escrowId,
                        gameId: GAME_ID,
                        tableMode
                    },
                    idempotencyKey: buildHoldIdempotencyKey(matchId, userDoc._id),
                    paymentMethod: 'system',
                    status: 'completed',
                    description: `Color Clash entry hold for ${tableMode}`,
                    completedAt: nowDate
                }], { session, ordered: true });

                await WalletEscrow.create([{
                    _id: escrowId,
                    userId: userDoc._id,
                    roomId,
                    matchId,
                    seasonId,
                    currency: 'coins',
                    amount: normalizedStake.entryFee,
                    status: 'held',
                    reason: this.buildEscrowReason(tableMode),
                    idempotencyKey: buildHoldIdempotencyKey(matchId, userDoc._id),
                    holdTransactionId,
                    payoutTransactionIds: [],
                    refundTransactionId: null,
                    settlementKey,
                    feeBreakdown: {
                        houseFee: 0,
                        sinkFee: 0,
                        payout: 0
                    },
                    balanceBefore: balanceBeforeCoins,
                    balanceAfterHold: Number(userDoc.coins || 0),
                    heldAt: nowDate,
                    expiresAt
                }], { session, ordered: true });

                auditEntries.push(this.buildAuditEntry({
                    entityType: 'escrow',
                    entityId: escrowId,
                    action: 'hold_created',
                    actorType,
                    actorId,
                    requestId,
                    idempotencyKey: buildHoldIdempotencyKey(matchId, userDoc._id),
                    userId: userDoc._id,
                    roomId,
                    matchId,
                    before: {
                        status: null,
                        coins: balanceBeforeCoins
                    },
                    after: {
                        status: 'held',
                        coins: Number(userDoc.coins || 0),
                        amount: normalizedStake.entryFee
                    },
                    meta: {
                        tableMode,
                        currency: 'coins'
                    }
                }));

                balanceUpdates.push({
                    userId: toIdString(userDoc._id),
                    balance: {
                        coins: Number(userDoc.coins || 0),
                        gems: balanceBeforeGems
                    }
                });
            }

            const allEscrows = await applySession(
                WalletEscrow.find({
                    matchId,
                    userId: { $in: participantList.map((entry) => entry.userId) }
                }),
                session
            );
            const totalEscrowed = allEscrows.reduce((sum, escrow) => sum + Number(escrow.amount || 0), 0);

            matchDoc.set({
                settlement: {
                    ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                    status: 'holds_created',
                    settlementKey,
                    currency: normalizedStake.currency,
                    entryFee: normalizedStake.entryFee,
                    totalEscrowed,
                    error: null
                }
            });
            await matchDoc.save({ session });

            if (auditEntries.length) {
                await AuditLog.create(auditEntries, { session, ordered: true });
            }

            return {
                skipped: false,
                duplicate: false,
                escrows: allEscrows,
                totalEscrowed,
                balanceUpdates
            };
        }));

        for (const update of result.balanceUpdates || []) {
            this.emitBalanceUpdate(update.userId, update.balance);
        }

        return {
            ...result,
            escrows: (result.escrows || []).map((entry) => entry.toObject ? entry.toObject() : entry)
        };
    }

    async createEntryHold({
        userId,
        roomId,
        matchId,
        seasonId = null,
        currency = 'coins',
        amount = 0,
        tableMode = 'gold_stake'
    }) {
        const result = await this.ensureEntryHoldsForMatch({
            roomId,
            matchId,
            seasonId,
            tableMode,
            players: [{ userId }],
            stakeConfig: {
                currency,
                entryFee: amount,
                payouts: DEFAULT_PAYOUTS,
                houseFeeBps: DEFAULT_HOUSE_FEE_BPS,
                sinkFeeBps: DEFAULT_SINK_FEE_BPS
            }
        });

        return {
            ...result,
            escrow: (result.escrows || []).find((entry) => toIdString(entry.userId) === toIdString(userId)) || null
        };
    }

    async refundHeldEscrowsForMatch({
        matchId,
        reason = 'match_cancelled_before_valid_start',
        actorType = 'system',
        actorId = null,
        requestId = null
    }) {
        const result = await this.withSettlementLock(matchId, () => this.runInTransaction('stake refund', async (session) => {
            const matchDoc = await applySession(ColorClashMatch.findById(matchId), session);
            if (!matchDoc) {
                throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for refund', 404);
            }

            const stakeConfig = normalizeStakeConfig(matchDoc.configSnapshot?.roomGameConfig?.stake || {});
            if (!requiresEscrow(stakeConfig)) {
                matchDoc.set({
                    settlement: {
                        ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                        status: 'skipped',
                        settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                        currency: 'none',
                        entryFee: 0,
                        error: null
                    }
                });
                await matchDoc.save({ session });
                return {
                    skipped: true,
                    refundedAmount: 0
                };
            }

            if (matchDoc.settlement?.status === 'settled') {
                return {
                    skipped: false,
                    alreadyProcessed: true,
                    refundedAmount: Number(matchDoc.settlement?.refundedAmount || 0)
                };
            }

            const heldEscrows = await applySession(
                WalletEscrow.find({ matchId, status: 'held' }),
                session
            );

            if (!heldEscrows.length) {
                const lockedEscrowExists = await applySession(
                    WalletEscrow.exists({ matchId, status: { $in: ['locked', 'settled'] } }),
                    session
                );
                if (lockedEscrowExists) {
                    throw createServiceError('ESCROWS_ALREADY_LOCKED', 'Color Clash stake escrows are already locked or settled', 409);
                }

                matchDoc.set({
                    settlement: {
                        ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                        status: 'refunded',
                        settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                        refundedAmount: Number(matchDoc.settlement?.refundedAmount || 0),
                        refundedAt: matchDoc.settlement?.refundedAt || new Date(this.now()),
                        error: null
                    }
                });
                await matchDoc.save({ session });
                return {
                    skipped: false,
                    alreadyProcessed: true,
                    refundedAmount: Number(matchDoc.settlement?.refundedAmount || 0)
                };
            }

            const userDocs = await applySession(
                User.find({ _id: { $in: heldEscrows.map((escrow) => escrow.userId) } }).select('coins gems'),
                session
            );
            const userById = new Map(userDocs.map((entry) => [toIdString(entry._id), entry]));
            const balanceUpdates = [];
            const auditEntries = [];
            const nowDate = new Date(this.now());
            let refundedAmount = 0;

            for (const escrow of sortByStableId(heldEscrows, (entry) => entry.userId)) {
                const userDoc = userById.get(toIdString(escrow.userId));
                if (!userDoc) {
                    throw createServiceError('USER_NOT_FOUND', 'Color Clash player was not found during refund', 404, {
                        failedUserId: toIdString(escrow.userId)
                    });
                }

                const refundTransactionId = new mongoose.Types.ObjectId();
                const balanceBeforeCoins = Number(userDoc.coins || 0);
                const balanceBeforeGems = Number(userDoc.gems || 0);
                userDoc.coins = balanceBeforeCoins + Number(escrow.amount || 0);
                await userDoc.save({ session });

                await Transaction.create([{
                    _id: refundTransactionId,
                    userId: userDoc._id,
                    type: 'game_escrow_refund',
                    amount: { coins: Number(escrow.amount || 0) },
                    balanceBefore: {
                        coins: balanceBeforeCoins,
                        gems: balanceBeforeGems
                    },
                    balanceAfter: {
                        coins: Number(userDoc.coins || 0),
                        gems: balanceBeforeGems
                    },
                    reference: {
                        roomId: escrow.roomId,
                        matchId: escrow.matchId,
                        seasonId: escrow.seasonId,
                        escrowId: escrow._id,
                        gameId: GAME_ID,
                        tableMode: matchDoc.tableMode
                    },
                    idempotencyKey: buildRefundIdempotencyKey(matchId, userDoc._id),
                    paymentMethod: 'system',
                    status: 'completed',
                    description: `Color Clash escrow refund: ${reason}`,
                    completedAt: nowDate
                }], { session, ordered: true });

                escrow.status = 'refunded';
                escrow.refundTransactionId = refundTransactionId;
                escrow.refundedAt = nowDate;
                escrow.feeBreakdown = {
                    houseFee: 0,
                    sinkFee: 0,
                    payout: 0
                };
                await escrow.save({ session });

                refundedAmount += Number(escrow.amount || 0);
                auditEntries.push(this.buildAuditEntry({
                    entityType: 'escrow',
                    entityId: escrow._id,
                    action: 'hold_refunded',
                    actorType,
                    actorId,
                    requestId,
                    idempotencyKey: buildRefundIdempotencyKey(matchId, userDoc._id),
                    userId: userDoc._id,
                    roomId: escrow.roomId,
                    matchId: escrow.matchId,
                    before: {
                        status: 'held',
                        coins: balanceBeforeCoins
                    },
                    after: {
                        status: 'refunded',
                        coins: Number(userDoc.coins || 0)
                    },
                    meta: {
                        reason
                    }
                }));

                balanceUpdates.push({
                    userId: toIdString(userDoc._id),
                    balance: {
                        coins: Number(userDoc.coins || 0),
                        gems: balanceBeforeGems
                    }
                });
            }

            matchDoc.set({
                settlement: {
                    ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                    status: 'refunded',
                    settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                    currency: stakeConfig.currency,
                    entryFee: stakeConfig.entryFee,
                    refundedAmount,
                    refundedAt: nowDate,
                    error: null
                }
            });
            await matchDoc.save({ session });

            await AuditLog.create(auditEntries, { session, ordered: true });

            return {
                skipped: false,
                refundedAmount,
                balanceUpdates
            };
        }));

        for (const update of result.balanceUpdates || []) {
            this.emitBalanceUpdate(update.userId, update.balance);
        }

        const summary = await this.getSettlementSummary(matchId);
        try {
            await antiFraudService.recordRefundSignal({
                matchId,
                actorType,
                actorId,
                requestId
            });
        } catch (error) {
            await ColorClashMatch.findByIdAndUpdate(matchId, {
                $set: {
                    'riskEvaluation.error': error.code || error.message || 'REFUND_SIGNAL_FAILED',
                    'riskEvaluation.lastProcessedAt': new Date(this.now())
                }
            }).catch(() => {});
        }

        return summary;
    }

    async lockEscrowsForValidStart({
        matchId,
        playerUserIds = null,
        requestId = null,
        actorType = 'system',
        actorId = null
    }) {
        const result = await this.withSettlementLock(matchId, () => this.runInTransaction('valid-start escrow lock', async (session) => {
            const matchDoc = await applySession(ColorClashMatch.findById(matchId), session);
            if (!matchDoc) {
                throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for escrow lock', 404);
            }

            const stakeConfig = normalizeStakeConfig(matchDoc.configSnapshot?.roomGameConfig?.stake || {});
            if (!requiresEscrow(stakeConfig)) {
                return {
                    skipped: true,
                    duplicate: false,
                    totalEscrowed: 0
                };
            }

            const userIds = (playerUserIds?.length ? playerUserIds : (matchDoc.players || []).map((entry) => entry.userId))
                .map((entry) => toIdString(entry));
            const escrows = await applySession(
                WalletEscrow.find({ matchId, userId: { $in: userIds } }),
                session
            );

            if (escrows.length !== userIds.length) {
                throw createServiceError('MISSING_ENTRY_HOLDS', 'Color Clash match cannot start without every paid player hold', 409);
            }

            if (escrows.every((escrow) => LOCKED_ESCROW_STATUSES.has(escrow.status))) {
                return {
                    skipped: false,
                    duplicate: true,
                    totalEscrowed: escrows.reduce((sum, escrow) => sum + Number(escrow.amount || 0), 0)
                };
            }

            for (const escrow of escrows) {
                if (!PRESTART_ESCROW_STATUSES.has(escrow.status) && !LOCKED_ESCROW_STATUSES.has(escrow.status)) {
                    throw createServiceError('ESCROW_LOCK_CONFLICT', 'Color Clash paid table has an escrow in an invalid lock state', 409);
                }
            }

            const nowDate = new Date(this.now());
            for (const escrow of escrows.filter((entry) => entry.status === 'held')) {
                escrow.status = 'locked';
                escrow.lockedAt = nowDate;
                await escrow.save({ session });
            }

            const totalEscrowed = escrows.reduce((sum, escrow) => sum + Number(escrow.amount || 0), 0);
            matchDoc.validStartedAt = nowDate;
            matchDoc.set({
                settlement: {
                    ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                    status: 'locked',
                    settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                    currency: stakeConfig.currency,
                    entryFee: stakeConfig.entryFee,
                    totalEscrowed,
                    lockedAt: nowDate,
                    error: null
                }
            });
            await matchDoc.save({ session });

            await AuditLog.create([this.buildAuditEntry({
                entityType: 'match',
                entityId: matchDoc._id,
                action: 'escrows_locked_for_valid_start',
                actorType,
                actorId,
                requestId,
                roomId: matchDoc.roomId,
                matchId: matchDoc._id,
                before: {
                    settlementStatus: matchDoc.settlement?.status || 'none'
                },
                after: {
                    settlementStatus: 'locked',
                    validStartedAt: nowDate
                },
                meta: {
                    totalEscrowed
                }
            })], { session, ordered: true });

            return {
                skipped: false,
                duplicate: false,
                totalEscrowed
            };
        }));

        return {
            ...result,
            summary: await this.getSettlementSummary(matchId)
        };
    }

    calculatePayoutBreakdown({ matchDoc, escrows, stakeConfig }) {
        const grossEscrow = escrows.reduce((sum, escrow) => sum + Number(escrow.amount || 0), 0);
        const houseFee = Math.floor((grossEscrow * Number(stakeConfig.houseFeeBps || 0)) / 10000);
        const sinkAmount = Math.floor((grossEscrow * Number(stakeConfig.sinkFeeBps || 0)) / 10000);
        const grossPool = grossEscrow - houseFee - sinkAmount;

        if (grossPool < 0) {
            throw createServiceError('INVALID_GROSS_POOL', 'Color Clash settlement cannot produce a negative prize pool', 500);
        }

        const placements = Array.isArray(matchDoc.roundResult?.placements)
            ? matchDoc.roundResult.placements.slice().sort((left, right) => Number(left.placement) - Number(right.placement))
            : [];
        if (!placements.length) {
            throw createServiceError('ROUND_RESULT_MISSING', 'Color Clash settlement requires a completed round result', 409);
        }

        const payoutRecipients = stakeConfig.payouts
            .map((config) => {
                const placement = placements.find((entry) => Number(entry.placement) === Number(config.place));
                if (!placement || !placement.userId) return null;
                return {
                    userId: toIdString(placement.userId),
                    place: Number(placement.placement),
                    bps: Number(config.bps),
                    amount: 0
                };
            })
            .filter(Boolean);

        if (!payoutRecipients.length) {
            throw createServiceError('PAYOUT_CONFIG_NO_RECIPIENTS', 'Color Clash payout configuration found no eligible recipients', 409);
        }

        let totalPaidOut = 0;
        for (const recipient of payoutRecipients) {
            recipient.amount = Math.floor((grossPool * recipient.bps) / 10000);
            totalPaidOut += recipient.amount;
        }
        if (totalPaidOut < grossPool) {
            payoutRecipients[0].amount += (grossPool - totalPaidOut);
            totalPaidOut = grossPool;
        }

        return {
            grossEscrow,
            grossPool,
            houseFee,
            sinkAmount,
            payoutRecipients,
            totalPaidOut
        };
    }

    async settleMatch({
        matchId,
        actorType = 'system',
        actorId = null,
        requestId = null
    }) {
        const existingMatch = await ColorClashMatch.findById(matchId).select('status settlement configSnapshot').lean();
        if (!existingMatch) {
            throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for settlement', 404);
        }

        if (existingMatch.status === 'invalidated' || existingMatch.status === 'cancelled') {
            const heldEscrowCount = await WalletEscrow.countDocuments({ matchId, status: 'held' });
            if (heldEscrowCount > 0) {
                return this.refundHeldEscrowsForMatch({
                    matchId,
                    reason: 'match_invalidated_before_settlement',
                    actorType,
                    actorId,
                    requestId
                });
            }
            return this.getSettlementSummary(matchId);
        }

        try {
            const result = await this.withSettlementLock(matchId, () => this.runInTransaction('stake settlement', async (session) => {
                const matchDoc = await applySession(ColorClashMatch.findById(matchId), session);
                if (!matchDoc) {
                    throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for settlement', 404);
                }

                const stakeConfig = normalizeStakeConfig(matchDoc.configSnapshot?.roomGameConfig?.stake || {});
                if (!requiresEscrow(stakeConfig)) {
                    matchDoc.set({
                        settlement: {
                            ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                            status: 'skipped',
                            settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                            currency: 'none',
                            entryFee: 0,
                            error: null
                        }
                    });
                    if (matchDoc.tableMode !== 'ranked') {
                        matchDoc.set({
                            rankProgression: {
                                ...(matchDoc.rankProgression?.toObject ? matchDoc.rankProgression.toObject() : matchDoc.rankProgression || {}),
                                status: 'skipped',
                                error: null
                            }
                        });
                    }
                    await this.applyProfileStatsForMatch({
                        session,
                        matchDoc
                    });
                    await matchDoc.save({ session });
                    return {
                        skipped: true
                    };
                }

                if (matchDoc.settlement?.status === 'settled') {
                    return {
                        skipped: false,
                        alreadyProcessed: true
                    };
                }

                if (matchDoc.status !== 'completed') {
                    throw createServiceError('MATCH_NOT_SETTLEABLE', 'Color Clash match must be completed before settlement', 409);
                }

                const escrows = await applySession(
                    WalletEscrow.find({ matchId, status: 'locked' }),
                    session
                );

                if (!escrows.length) {
                    throw createServiceError('NO_LOCKED_ESCROWS', 'Color Clash settlement requires locked paid entries', 409);
                }

                const breakdown = this.calculatePayoutBreakdown({
                    matchDoc,
                    escrows,
                    stakeConfig
                });
                const payoutMap = new Map(breakdown.payoutRecipients.map((entry) => [entry.userId, entry]));
                const houseFeeByUserId = allocateAmountByWeight(
                    breakdown.houseFee,
                    escrows,
                    (escrow) => escrow.amount,
                    (escrow) => escrow.userId
                );
                const sinkFeeByUserId = allocateAmountByWeight(
                    breakdown.sinkAmount,
                    escrows,
                    (escrow) => escrow.amount,
                    (escrow) => escrow.userId
                );

                const uniqueUserIds = Array.from(new Set([
                    ...escrows.map((escrow) => toIdString(escrow.userId)),
                    ...breakdown.payoutRecipients.map((entry) => entry.userId)
                ]));
                const userDocs = await applySession(
                    User.find({ _id: { $in: uniqueUserIds } }).select('coins gems gameStats'),
                    session
                );
                const userById = new Map(userDocs.map((entry) => [toIdString(entry._id), entry]));
                const payoutTransactionIdsByUserId = new Map();
                const auditEntries = [];
                const balanceUpdates = [];
                const nowDate = new Date(this.now());

                for (const recipient of breakdown.payoutRecipients.filter((entry) => entry.amount > 0)) {
                    const userDoc = userById.get(recipient.userId);
                    if (!userDoc) {
                        throw createServiceError('USER_NOT_FOUND', 'Color Clash winner could not be found for payout', 404, {
                            failedUserId: recipient.userId
                        });
                    }

                    const payoutTransactionId = new mongoose.Types.ObjectId();
                    const balanceBeforeCoins = Number(userDoc.coins || 0);
                    const balanceBeforeGems = Number(userDoc.gems || 0);
                    userDoc.coins = balanceBeforeCoins + recipient.amount;
                    await userDoc.save({ session });

                    await Transaction.create([{
                        _id: payoutTransactionId,
                        userId: userDoc._id,
                        type: 'game_payout',
                        amount: { coins: recipient.amount },
                        balanceBefore: {
                            coins: balanceBeforeCoins,
                            gems: balanceBeforeGems
                        },
                        balanceAfter: {
                            coins: Number(userDoc.coins || 0),
                            gems: balanceBeforeGems
                        },
                        reference: {
                            roomId: matchDoc.roomId,
                            matchId: matchDoc._id,
                            seasonId: matchDoc.seasonId || null,
                            gameId: GAME_ID,
                            tableMode: matchDoc.tableMode
                        },
                        idempotencyKey: buildPayoutIdempotencyKey(matchId, userDoc._id),
                        paymentMethod: 'system',
                        status: 'completed',
                        description: `Color Clash payout for placement ${recipient.place}`,
                        completedAt: nowDate
                    }], { session, ordered: true });

                    payoutTransactionIdsByUserId.set(recipient.userId, payoutTransactionId);
                    balanceUpdates.push({
                        userId: recipient.userId,
                        balance: {
                            coins: Number(userDoc.coins || 0),
                            gems: balanceBeforeGems
                        }
                    });
                }

                for (const escrow of escrows) {
                    const userId = toIdString(escrow.userId);
                    const payoutRecipient = payoutMap.get(userId);
                    const payoutAmount = Number(payoutRecipient?.amount || 0);
                    const payoutTransactionId = payoutTransactionIdsByUserId.get(userId);
                    const userDoc = userById.get(userId);

                    if (userDoc) {
                        userDoc.gameStats = userDoc.gameStats || {};
                        userDoc.gameStats.colorClash = userDoc.gameStats.colorClash || {};
                        userDoc.gameStats.colorClash.stakePlayed = Number(userDoc.gameStats.colorClash.stakePlayed || 0) + 1;
                        userDoc.gameStats.colorClash.stakeNetCoins = Number(userDoc.gameStats.colorClash.stakeNetCoins || 0) + (payoutAmount - Number(escrow.amount || 0));
                        await userDoc.save({ session });
                    }

                    escrow.status = 'settled';
                    escrow.settledAt = nowDate;
                    escrow.payoutTransactionIds = payoutTransactionId ? [payoutTransactionId] : [];
                    escrow.feeBreakdown = {
                        houseFee: Number(houseFeeByUserId.get(userId) || 0),
                        sinkFee: Number(sinkFeeByUserId.get(userId) || 0),
                        payout: payoutAmount
                    };
                    await escrow.save({ session });

                    auditEntries.push(this.buildAuditEntry({
                        entityType: 'escrow',
                        entityId: escrow._id,
                        action: 'escrow_settled',
                        actorType,
                        actorId,
                        requestId,
                        idempotencyKey: payoutTransactionId ? buildPayoutIdempotencyKey(matchId, userId) : null,
                        userId: escrow.userId,
                        roomId: escrow.roomId,
                        matchId: escrow.matchId,
                        before: {
                            status: 'locked'
                        },
                        after: {
                            status: 'settled',
                            payout: payoutAmount,
                            houseFee: escrow.feeBreakdown.houseFee,
                            sinkFee: escrow.feeBreakdown.sinkFee
                        },
                        meta: {
                            place: payoutRecipient?.place || null
                        }
                    }));
                }

                matchDoc.set({
                    settlement: {
                        ...(matchDoc.settlement?.toObject ? matchDoc.settlement.toObject() : matchDoc.settlement || {}),
                        status: 'settled',
                        settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
                        currency: stakeConfig.currency,
                        entryFee: stakeConfig.entryFee,
                        totalEscrowed: breakdown.grossEscrow,
                        grossPool: breakdown.grossPool,
                        houseFee: breakdown.houseFee,
                        sinkAmount: breakdown.sinkAmount,
                        totalPaidOut: breakdown.totalPaidOut,
                        payouts: breakdown.payoutRecipients.map((entry) => ({
                            userId: entry.userId,
                            place: entry.place,
                            amount: entry.amount,
                            transactionId: payoutTransactionIdsByUserId.get(entry.userId) || null
                        })),
                        settledAt: nowDate,
                        error: null
                    }
                });
                await this.applyProfileStatsForMatch({
                    session,
                    matchDoc
                });
                await matchDoc.save({ session });

                await AuditLog.create([
                    this.buildAuditEntry({
                        entityType: 'match',
                        entityId: matchDoc._id,
                        action: 'match_settled',
                        actorType,
                        actorId,
                        requestId,
                        roomId: matchDoc.roomId,
                        matchId: matchDoc._id,
                        before: {
                            settlementStatus: 'locked'
                        },
                        after: {
                            settlementStatus: 'settled',
                            totalPaidOut: breakdown.totalPaidOut,
                            houseFee: breakdown.houseFee,
                            sinkAmount: breakdown.sinkAmount
                        },
                        meta: {
                            payouts: breakdown.payoutRecipients
                        }
                    }),
                    ...auditEntries
                ], { session, ordered: true });

                return {
                    skipped: false,
                    alreadyProcessed: false,
                    balanceUpdates
                };
            }));

            for (const update of result.balanceUpdates || []) {
                this.emitBalanceUpdate(update.userId, update.balance);
            }

            const summary = await this.getSettlementSummary(matchId);
            const rankProgression = await this.applyRankedProgressionAfterSettlement({
                matchId,
                summary,
                actorType,
                actorId,
                requestId
            });
            telemetry.info('settlement_success', {
                matchId,
                status: summary.status,
                paidTable: summary.paidTable,
                totalPaidOut: summary.totalPaidOut,
                grossPool: summary.grossPool
            });
            let fraudProcessing = {
                skipped: true
            };
            try {
                fraudProcessing = await antiFraudService.recordMatchOutcomeSignals({
                    matchId,
                    actorType,
                    actorId,
                    requestId
                });
            } catch (error) {
                await ColorClashMatch.findByIdAndUpdate(matchId, {
                    $set: {
                        'riskEvaluation.error': error.code || error.message || 'RISK_SIGNAL_FAILED',
                        'riskEvaluation.lastProcessedAt': new Date(this.now())
                    }
                }).catch(() => {});
            }
            return {
                ...summary,
                rankProgression,
                fraudProcessing
            };
        } catch (error) {
            telemetry.error('settlement_failed', {
                matchId,
                code: error.code || 'SETTLEMENT_FAILED',
                message: error.message
            });
            await ColorClashMatch.findByIdAndUpdate(matchId, {
                $set: {
                    'settlement.status': 'failed',
                    'settlement.settlementKey': buildSettlementKey(matchId),
                    'settlement.error': error.code || error.message || 'SETTLEMENT_FAILED',
                    updatedAt: new Date(this.now())
                }
            }).catch(() => {});
            throw error;
        }
    }

    async getSettlementSummary(matchId) {
        const matchDoc = await ColorClashMatch.findById(matchId).lean();
        if (!matchDoc) {
            throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for settlement summary', 404);
        }

        const stakeConfig = normalizeStakeConfig(matchDoc.configSnapshot?.roomGameConfig?.stake || {});
        const escrows = await WalletEscrow.find({ matchId }).lean();
        return {
            matchId: toIdString(matchId),
            paidTable: requiresEscrow(stakeConfig),
            status: matchDoc.settlement?.status || 'none',
            settlementKey: matchDoc.settlement?.settlementKey || buildSettlementKey(matchId),
            currency: matchDoc.settlement?.currency || stakeConfig.currency,
            entryFee: Number(matchDoc.settlement?.entryFee || stakeConfig.entryFee || 0),
            totalEscrowed: Number(matchDoc.settlement?.totalEscrowed || 0),
            grossPool: Number(matchDoc.settlement?.grossPool || 0),
            houseFee: Number(matchDoc.settlement?.houseFee || 0),
            sinkAmount: Number(matchDoc.settlement?.sinkAmount || 0),
            totalPaidOut: Number(matchDoc.settlement?.totalPaidOut || 0),
            refundedAmount: Number(matchDoc.settlement?.refundedAmount || 0),
            payouts: matchDoc.settlement?.payouts || [],
            rankProgression: matchDoc.rankProgression || null,
            lockedAt: matchDoc.settlement?.lockedAt || null,
            settledAt: matchDoc.settlement?.settledAt || null,
            refundedAt: matchDoc.settlement?.refundedAt || null,
            error: matchDoc.settlement?.error || null,
            escrowCount: escrows.length
        };
    }
}

const settlementService = new ColorClashSettlementService();

module.exports = settlementService;
module.exports.ColorClashSettlementService = ColorClashSettlementService;
module.exports.normalizeStakeConfig = normalizeStakeConfig;
module.exports.requiresEscrow = requiresEscrow;
module.exports.buildSettlementKey = buildSettlementKey;
module.exports.buildHoldIdempotencyKey = buildHoldIdempotencyKey;
module.exports.DEFAULT_HOUSE_FEE_BPS = DEFAULT_HOUSE_FEE_BPS;
module.exports.DEFAULT_SINK_FEE_BPS = DEFAULT_SINK_FEE_BPS;
module.exports.DEFAULT_PAYOUTS = DEFAULT_PAYOUTS;
