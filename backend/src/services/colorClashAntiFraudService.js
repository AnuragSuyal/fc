const crypto = require('crypto');
const mongoose = require('mongoose');

const AntiFraudFlag = require('../models/AntiFraudFlag');
const AuditLog = require('../models/AuditLog');
const ColorClashMatch = require('../models/ColorClashMatch');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const WalletEscrow = require('../models/WalletEscrow');
const {
    POLICY,
    COMPETITIVE_MATCH_LIMIT,
    severityOrder,
    getHigherSeverity,
    resolveAutoAction
} = require('./colorClashRiskPolicy');

const COMPETITIVE_STATUSES = ['completed'];

const createServiceError = (code, message, status = 400, extra = {}) => {
    const error = new Error(message || code);
    error.code = code;
    error.status = status;
    Object.assign(error, extra);
    return error;
};

const applySession = (query, session) => (session ? query.session(session) : query);

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value.toString === 'function') return value.toString();
    return String(value);
};

const toObjectIdArray = (items = []) => items
    .map((entry) => toIdString(entry))
    .filter(Boolean)
    .map((entry) => new mongoose.Types.ObjectId(entry));

const stablePairKey = (left, right) => [toIdString(left), toIdString(right)]
    .filter(Boolean)
    .sort()
    .join(':');

const isStakeMatch = (matchDoc) => {
    const entryFee = Number(
        matchDoc?.settlement?.entryFee ||
        matchDoc?.configSnapshot?.roomGameConfig?.stake?.entryFee ||
        0
    );
    return entryFee > 0 || matchDoc?.tableMode === 'gold_stake';
};

const isCompetitiveMatch = (matchDoc) => matchDoc?.tableMode === 'ranked' || isStakeMatch(matchDoc);

const resolveScope = (matchDoc) => {
    if (matchDoc?.tableMode === 'ranked') return 'ranked';
    if (isStakeMatch(matchDoc)) return 'stake';
    return 'none';
};

const extractRankInput = (matchDoc, userId) => {
    const userIdString = toIdString(userId);
    const rankInputs = Array.isArray(matchDoc?.roundResult?.rankInputs)
        ? matchDoc.roundResult.rankInputs
        : [];
    const rankInput = rankInputs.find((entry) => toIdString(entry.userId) === userIdString);
    if (rankInput) return rankInput;

    const placement = Array.isArray(matchDoc?.roundResult?.placements)
        ? matchDoc.roundResult.placements.find((entry) => toIdString(entry.userId) === userIdString)
        : null;
    if (!placement) return null;
    return {
        userId: placement.userId,
        placement: placement.placement,
        outcome: Number(placement.placement || 0) === 1 ? 'win' : 'loss',
        timeoutStrikes: placement.timeoutStrikes || 0,
        status: placement.status || 'active'
    };
};

const hashValue = (value, salt = process.env.COLOR_CLASH_RISK_HASH_SALT || process.env.JWT_SECRET || 'color-clash-risk') => {
    const raw = String(value || '').trim();
    if (!raw) return null;
    return crypto
        .createHash('sha256')
        .update(`${salt}:${raw}`)
        .digest('hex');
};

class ColorClashAntiFraudService {
    constructor({ now = () => Date.now() } = {}) {
        this.now = now;
    }

    configure({ now } = {}) {
        if (now) this.now = now;
        return this;
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

    buildRequestContext({ ip = null, deviceHash = null } = {}) {
        return {
            ipHash: hashValue(ip),
            deviceHash: deviceHash || null
        };
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

    normalizeEvidence(evidence = {}) {
        return Object.entries(evidence)
            .filter(([, value]) => value !== undefined)
            .map(([key, value]) => ({ key, value }));
    }

    async getActiveLocksForUser({ userId = null, user = null }) {
        const userDoc = user || await User.findById(userId).select('isGuest level settings').lean();
        if (!userDoc) {
            throw createServiceError('USER_NOT_FOUND', 'User not found', 404);
        }

        const colorClashSettings = userDoc.settings?.colorClash || {};
        const rankedLocked = Boolean(
            colorClashSettings.rankedAccessLocked ||
            colorClashSettings.rankedLock?.active
        );
        const stakeLocked = Boolean(
            colorClashSettings.stakeAccessLocked ||
            colorClashSettings.stakeLock?.active
        );

        return {
            rankedLocked,
            rankedLockReason: colorClashSettings.rankedLock?.reason || colorClashSettings.rankedAccessLockReason || '',
            stakeLocked,
            stakeLockReason: colorClashSettings.stakeLock?.reason || colorClashSettings.stakeAccessLockReason || '',
            riskState: colorClashSettings.riskState || {
                severity: 'none',
                score: 0,
                lastFlagType: '',
                lastAutoAction: 'none',
                activeFlagCount: 0
            }
        };
    }

    async getCompetitiveMatchesForUser({ userId, limit = COMPETITIVE_MATCH_LIMIT, windowMs = null }) {
        const query = {
            status: { $in: COMPETITIVE_STATUSES },
            'players.userId': new mongoose.Types.ObjectId(toIdString(userId)),
            $or: [
                { tableMode: 'ranked' },
                { 'settlement.entryFee': { $gt: 0 } },
                { 'configSnapshot.roomGameConfig.stake.entryFee': { $gt: 0 } }
            ]
        };
        if (windowMs) {
            query.endedAt = { $gte: new Date(this.now() - windowMs) };
        }

        return ColorClashMatch.find(query)
            .sort({ endedAt: -1, createdAt: -1 })
            .limit(limit)
            .select('roomId seasonId tableMode players playerContexts roundResult endedAt settlement configSnapshot')
            .lean();
    }

    async getPairMatches({ leftUserId, rightUserId, windowMs = POLICY.repeatedPairing.windowMs, excludeMatchId = null }) {
        const query = {
            status: { $in: COMPETITIVE_STATUSES },
            endedAt: { $gte: new Date(this.now() - windowMs) },
            'players.userId': {
                $all: [
                    new mongoose.Types.ObjectId(toIdString(leftUserId)),
                    new mongoose.Types.ObjectId(toIdString(rightUserId))
                ]
            },
            $or: [
                { tableMode: 'ranked' },
                { 'settlement.entryFee': { $gt: 0 } },
                { 'configSnapshot.roomGameConfig.stake.entryFee': { $gt: 0 } }
            ]
        };
        if (excludeMatchId) {
            query._id = { $ne: excludeMatchId };
        }

        return ColorClashMatch.find(query)
            .sort({ endedAt: -1, createdAt: -1 })
            .select('roomId seasonId tableMode players playerContexts roundResult endedAt settlement')
            .lean();
    }

    getContextForUser(matchDoc, userId) {
        const userIdString = toIdString(userId);
        return (matchDoc?.playerContexts || []).find((entry) => toIdString(entry.userId) === userIdString) || null;
    }

    getWinnerUserId(matchDoc) {
        const winnerPlacement = Array.isArray(matchDoc?.roundResult?.placements)
            ? matchDoc.roundResult.placements.find((entry) => Number(entry.placement || 0) === 1 && entry.userId)
            : null;
        return winnerPlacement?.userId ? toIdString(winnerPlacement.userId) : '';
    }

    getUserIds(matchDoc) {
        return Array.from(new Set((matchDoc?.players || []).map((player) => toIdString(player.userId)).filter(Boolean)));
    }

    async checkRepeatedPairing({ matchDoc, leftUserId, rightUserId }) {
        const pairMatches = await this.getPairMatches({
            leftUserId,
            rightUserId,
            excludeMatchId: matchDoc?._id
        });
        const matches = [matchDoc, ...pairMatches];
        const pairCount = matches.length;
        let leftWins = 0;
        let rightWins = 0;

        for (const entry of matches) {
            const winnerUserId = this.getWinnerUserId(entry);
            if (winnerUserId === toIdString(leftUserId)) leftWins += 1;
            if (winnerUserId === toIdString(rightUserId)) rightWins += 1;
        }

        const dominantWins = Math.max(leftWins, rightWins);
        const dominantWinRate = pairCount > 0 ? dominantWins / pairCount : 0;
        let severity = 'low';
        if (pairCount >= POLICY.repeatedPairing.highMatches || (
            pairCount >= POLICY.repeatedPairing.dominantSample &&
            dominantWinRate >= POLICY.repeatedPairing.dominantWinRate
        )) {
            severity = 'high';
        } else if (pairCount >= POLICY.repeatedPairing.mediumMatches) {
            severity = 'medium';
        }

        return {
            flagType: 'repeated_pairing',
            severity,
            score: (pairCount * 10) + Math.round(dominantWinRate * 100),
            subjectType: 'pair',
            subjectId: stablePairKey(leftUserId, rightUserId),
            userIds: [leftUserId, rightUserId],
            roomId: matchDoc.roomId,
            matchId: matchDoc._id,
            seasonId: matchDoc.seasonId || null,
            evidence: {
                pairCount,
                leftWins,
                rightWins,
                dominantWinRate: Number(dominantWinRate.toFixed(4)),
                windowHours: POLICY.repeatedPairing.windowMs / (60 * 60 * 1000)
            }
        };
    }

    async checkSameIpPairing({ matchDoc, leftUserId, rightUserId, repeatedPairingSignal = null }) {
        const currentLeft = this.getContextForUser(matchDoc, leftUserId);
        const currentRight = this.getContextForUser(matchDoc, rightUserId);
        const currentSameIp = Boolean(currentLeft?.ipHash && currentLeft.ipHash === currentRight?.ipHash);
        if (!currentSameIp) {
            return {
                flagType: 'same_ip_pairing',
                severity: 'low',
                score: 0,
                subjectType: 'pair',
                subjectId: stablePairKey(leftUserId, rightUserId),
                userIds: [leftUserId, rightUserId],
                roomId: matchDoc.roomId,
                matchId: matchDoc._id,
                seasonId: matchDoc.seasonId || null,
                ipHash: currentLeft?.ipHash || null,
                evidence: {
                    sameIpOverlapCount: 0,
                    pairCount: repeatedPairingSignal?.evidence?.pairCount || 1
                }
            };
        }

        const pairMatches = await this.getPairMatches({
            leftUserId,
            rightUserId,
            excludeMatchId: matchDoc?._id
        });
        const sameIpOverlapCount = 1 + pairMatches.filter((entry) => {
            const leftContext = this.getContextForUser(entry, leftUserId);
            const rightContext = this.getContextForUser(entry, rightUserId);
            return Boolean(leftContext?.ipHash && leftContext.ipHash === rightContext?.ipHash);
        }).length;
        const pairCount = Number(repeatedPairingSignal?.evidence?.pairCount || sameIpOverlapCount);

        let severity = 'low';
        if (
            pairCount >= POLICY.sameIpPairing.highPairMatches &&
            sameIpOverlapCount >= POLICY.sameIpPairing.highOverlapMatches
        ) {
            severity = 'high';
        } else if (
            pairCount >= POLICY.sameIpPairing.mediumPairMatches &&
            sameIpOverlapCount >= POLICY.sameIpPairing.mediumOverlapMatches
        ) {
            severity = 'medium';
        }

        return {
            flagType: 'same_ip_pairing',
            severity,
            score: (sameIpOverlapCount * 25) + (pairCount * 5),
            subjectType: 'pair',
            subjectId: stablePairKey(leftUserId, rightUserId),
            userIds: [leftUserId, rightUserId],
            roomId: matchDoc.roomId,
            matchId: matchDoc._id,
            seasonId: matchDoc.seasonId || null,
            ipHash: currentLeft?.ipHash || null,
            evidence: {
                sameIpOverlapCount,
                pairCount
            }
        };
    }

    async checkLowOpponentDiversity({ userId }) {
        const matches = await this.getCompetitiveMatchesForUser({
            userId,
            limit: POLICY.lowOpponentDiversity.sampleSize
        });
        const opponentIds = [];
        for (const matchDoc of matches) {
            for (const player of matchDoc.players || []) {
                const playerUserId = toIdString(player.userId);
                if (playerUserId && playerUserId !== toIdString(userId)) {
                    opponentIds.push(playerUserId);
                }
            }
        }

        const uniqueOpponents = new Set(opponentIds);
        const sampleSize = matches.length;
        const diversityRatio = opponentIds.length ? uniqueOpponents.size / opponentIds.length : 1;
        let severity = 'low';
        if (
            sampleSize >= POLICY.lowOpponentDiversity.highSample &&
            uniqueOpponents.size <= POLICY.lowOpponentDiversity.highMaxUniqueOpponents &&
            diversityRatio <= POLICY.lowOpponentDiversity.highMaxRatio
        ) {
            severity = 'high';
        } else if (
            sampleSize >= POLICY.lowOpponentDiversity.mediumSample &&
            uniqueOpponents.size <= POLICY.lowOpponentDiversity.mediumMaxUniqueOpponents &&
            diversityRatio <= POLICY.lowOpponentDiversity.mediumMaxRatio
        ) {
            severity = 'medium';
        }

        return {
            flagType: 'low_opponent_diversity',
            severity,
            score: Math.max(0, 100 - Math.round(diversityRatio * 100)),
            subjectType: 'user',
            subjectId: toIdString(userId),
            userIds: [userId],
            evidence: {
                sampleSize,
                uniqueOpponents: uniqueOpponents.size,
                diversityRatio: Number(diversityRatio.toFixed(4))
            }
        };
    }

    async checkTimeoutAbuse({ userId }) {
        const matches = await this.getCompetitiveMatchesForUser({
            userId,
            limit: POLICY.timeoutAbuse.sampleSize
        });
        let timeoutMatches = 0;

        for (const matchDoc of matches) {
            const rankInput = extractRankInput(matchDoc, userId);
            if (Number(rankInput?.timeoutStrikes || 0) > 0) {
                timeoutMatches += 1;
            }
        }

        const sampleSize = matches.length;
        const timeoutRate = sampleSize > 0 ? timeoutMatches / sampleSize : 0;
        let severity = 'low';
        if (
            sampleSize >= POLICY.timeoutAbuse.highSample &&
            timeoutRate >= POLICY.timeoutAbuse.highRate
        ) {
            severity = 'high';
        } else if (
            sampleSize >= POLICY.timeoutAbuse.mediumSample &&
            timeoutRate >= POLICY.timeoutAbuse.mediumRate
        ) {
            severity = 'medium';
        }

        return {
            flagType: 'timeout_abuse',
            severity,
            score: Math.round(timeoutRate * 100),
            subjectType: 'user',
            subjectId: toIdString(userId),
            userIds: [userId],
            evidence: {
                sampleSize,
                timeoutMatches,
                timeoutRate: Number(timeoutRate.toFixed(4))
            }
        };
    }

    async checkSurrenderAbuse({ userId }) {
        const matches = await this.getCompetitiveMatchesForUser({
            userId,
            limit: POLICY.timeoutAbuse.sampleSize
        });
        let forfeitMatches = 0;

        for (const matchDoc of matches) {
            const rankInput = extractRankInput(matchDoc, userId);
            if (rankInput?.status === 'forfeited' || rankInput?.outcome === 'forfeit') {
                forfeitMatches += 1;
            }
        }

        const sampleSize = matches.length;
        let severity = 'low';
        if (
            sampleSize >= POLICY.surrenderAbuse.highSample &&
            forfeitMatches >= POLICY.surrenderAbuse.highCount
        ) {
            severity = 'high';
        } else if (
            sampleSize >= POLICY.surrenderAbuse.mediumSample &&
            forfeitMatches >= POLICY.surrenderAbuse.mediumCount
        ) {
            severity = 'medium';
        }

        return {
            flagType: 'surrender_abuse',
            severity,
            score: forfeitMatches * 10,
            subjectType: 'user',
            subjectId: toIdString(userId),
            userIds: [userId],
            evidence: {
                sampleSize,
                forfeitMatches
            }
        };
    }

    async checkRefundAbuse({ userId }) {
        const mediumWindowStart = new Date(this.now() - POLICY.refundAbuse.mediumWindowMs);
        const highWindowStart = new Date(this.now() - POLICY.refundAbuse.highWindowMs);
        const [mediumCount, highCount] = await Promise.all([
            WalletEscrow.countDocuments({
                userId,
                status: 'refunded',
                refundedAt: { $gte: mediumWindowStart }
            }),
            WalletEscrow.countDocuments({
                userId,
                status: 'refunded',
                refundedAt: { $gte: highWindowStart }
            })
        ]);

        let severity = 'low';
        if (highCount >= POLICY.refundAbuse.highCount) {
            severity = 'high';
        } else if (mediumCount >= POLICY.refundAbuse.mediumCount) {
            severity = 'medium';
        }

        return {
            flagType: 'refund_abuse',
            severity,
            score: (highCount * 12) + (mediumCount * 5),
            subjectType: 'user',
            subjectId: toIdString(userId),
            userIds: [userId],
            evidence: {
                refundsLastHour: mediumCount,
                refundsLastSixHours: highCount
            }
        };
    }

    async checkWalletCycle({ userId }) {
        const windowStart = new Date(this.now() - POLICY.walletCycleAnomaly.windowMs);
        const [escrows, payouts] = await Promise.all([
            WalletEscrow.find({
                userId,
                createdAt: { $gte: windowStart }
            }).select('status').lean(),
            Transaction.countDocuments({
                userId,
                type: 'game_payout',
                createdAt: { $gte: windowStart }
            })
        ]);

        const holdCount = escrows.length;
        const refundedCount = escrows.filter((entry) => entry.status === 'refunded').length;
        const settledCount = escrows.filter((entry) => entry.status === 'settled').length;
        const refundRate = holdCount > 0 ? refundedCount / holdCount : 0;
        let severity = 'low';
        if (
            holdCount >= POLICY.walletCycleAnomaly.highMinHolds &&
            refundRate >= POLICY.walletCycleAnomaly.highRefundRate &&
            settledCount <= POLICY.walletCycleAnomaly.highMaxSettled &&
            payouts <= POLICY.walletCycleAnomaly.highMaxSettled
        ) {
            severity = 'high';
        } else if (
            holdCount >= POLICY.walletCycleAnomaly.mediumMinHolds &&
            refundRate >= POLICY.walletCycleAnomaly.mediumRefundRate
        ) {
            severity = 'medium';
        }

        return {
            flagType: 'wallet_cycle_anomaly',
            severity,
            score: Math.round(refundRate * 100) + (holdCount * 2),
            subjectType: 'wallet',
            subjectId: toIdString(userId),
            userIds: [userId],
            evidence: {
                holdCount,
                refundedCount,
                settledCount,
                payoutCount: payouts,
                refundRate: Number(refundRate.toFixed(4))
            }
        };
    }

    async updateRiskState({
        session,
        userIds = [],
        severity = 'low',
        score = 0,
        flagType = '',
        autoAction = 'none',
        reason = '',
        flagId = null
    }) {
        const objectIds = toObjectIdArray(userIds);
        if (!objectIds.length) return;

        const users = await applySession(User.find({
            _id: { $in: objectIds }
        }), session);

        for (const userDoc of users) {
            userDoc.settings = userDoc.settings || {};
            userDoc.settings.colorClash = userDoc.settings.colorClash || {};
            const colorClashSettings = userDoc.settings.colorClash;
            const existingRiskState = colorClashSettings.riskState || {};
            const nextSeverity = getHigherSeverity(existingRiskState.severity || 'none', severity);
            const activeFlagCount = await applySession(AntiFraudFlag.countDocuments({
                status: { $in: ['open', 'reviewing', 'actioned'] },
                userIds: userDoc._id
            }), session);

            colorClashSettings.riskState = {
                severity: nextSeverity,
                score: Math.max(Number(existingRiskState.score || 0), Number(score || 0)),
                lastFlagType: flagType || existingRiskState.lastFlagType || '',
                lastAutoAction: autoAction || existingRiskState.lastAutoAction || 'none',
                activeFlagCount
            };
            colorClashSettings.lastRiskActionAt = new Date(this.now());

            if (autoAction === 'ranked_lock') {
                colorClashSettings.rankedAccessLocked = true;
                colorClashSettings.rankedAccessLockReason = reason;
                colorClashSettings.rankedLock = {
                    active: true,
                    reason,
                    flagId,
                    appliedAt: new Date(this.now())
                };
            } else if (autoAction === 'stake_lock') {
                colorClashSettings.stakeAccessLocked = true;
                colorClashSettings.stakeAccessLockReason = reason;
                colorClashSettings.stakeLock = {
                    active: true,
                    reason,
                    flagId,
                    appliedAt: new Date(this.now())
                };
            }

            await userDoc.save({ session });
        }
    }

    async maybeApplyAutoAction({
        session,
        flagDoc = null,
        userIds = [],
        autoAction = 'none',
        severity = 'low',
        flagType = '',
        actorType = 'system',
        actorId = null,
        requestId = null
    }) {
        if (autoAction === 'none') {
            await this.updateRiskState({
                session,
                userIds,
                severity,
                score: flagDoc?.score || 0,
                flagType,
                autoAction,
                reason: '',
                flagId: flagDoc?._id || null
            });
            return { applied: false, autoAction };
        }

        const reason = flagDoc?.severity === 'high'
            ? `Color Clash ${flagType.replace(/_/g, ' ')} triggered a temporary ${autoAction.replace(/_/g, ' ')}.`
            : 'Color Clash account activity was routed for manual review.';

        await this.updateRiskState({
            session,
            userIds,
            severity,
            score: flagDoc?.score || 0,
            flagType,
            autoAction,
            reason,
            flagId: flagDoc?._id || null
        });

        if (flagDoc) {
            flagDoc.status = autoAction === 'manual_review' ? 'reviewing' : 'actioned';
            flagDoc.autoAction = autoAction;
            await flagDoc.save({ session });
        }

        const auditEntries = userIds.map((userId) => this.buildAuditEntry({
            entityType: 'user',
            entityId: userId,
            action: 'risk_auto_action_applied',
            actorType,
            actorId,
            requestId,
            userId,
            roomId: flagDoc?.roomId || null,
            matchId: flagDoc?.matchId || null,
            before: {
                autoAction: 'none'
            },
            after: {
                autoAction,
                severity,
                flagType
            },
            meta: {
                flagId: flagDoc?._id || null,
                reason
            }
        }));
        if (auditEntries.length) {
            await AuditLog.create(auditEntries, { session, ordered: true });
        }

        return { applied: true, autoAction };
    }

    async maybeCreateFlag({
        signal,
        scope = 'ranked',
        actorType = 'system',
        actorId = null,
        requestId = null
    }) {
        if (!signal || !signal.flagType) {
            return { skipped: true };
        }

        if (severityOrder[signal.severity || 'low'] <= severityOrder.low) {
            const userId = signal.userIds?.[0] || null;
            await AuditLog.create([this.buildAuditEntry({
                entityType: signal.matchId ? 'match' : 'user',
                entityId: signal.matchId || signal.subjectId,
                action: 'fraud_signal_logged',
                actorType,
                actorId,
                requestId,
                userId,
                roomId: signal.roomId || null,
                matchId: signal.matchId || null,
                after: {
                    flagType: signal.flagType,
                    severity: signal.severity,
                    score: signal.score
                },
                meta: {
                    subjectType: signal.subjectType,
                    subjectId: signal.subjectId,
                    evidence: signal.evidence
                }
            })], { ordered: true });
            return {
                skipped: true,
                logged: true,
                autoAction: 'none'
            };
        }

        return this.runInTransaction('fraud flag write', async (session) => {
            const autoAction = resolveAutoAction({
                flagType: signal.flagType,
                severity: signal.severity,
                scope
            });
            const evidence = this.normalizeEvidence(signal.evidence);
            const recentWindowStart = new Date(this.now() - POLICY.repeatedPairing.windowMs);
            let flagDoc = await applySession(AntiFraudFlag.findOne({
                subjectType: signal.subjectType,
                subjectId: signal.subjectId,
                flagType: signal.flagType,
                status: { $in: ['open', 'reviewing', 'actioned'] },
                createdAt: { $gte: recentWindowStart }
            }).sort({ createdAt: -1 }), session);

            let created = false;
            if (!flagDoc) {
                [flagDoc] = await AntiFraudFlag.create([{
                    subjectType: signal.subjectType,
                    subjectId: signal.subjectId,
                    matchId: signal.matchId || null,
                    roomId: signal.roomId || null,
                    seasonId: signal.seasonId || null,
                    userIds: signal.userIds || [],
                    ipHash: signal.ipHash || null,
                    deviceHash: signal.deviceHash || null,
                    flagType: signal.flagType,
                    severity: signal.severity,
                    score: signal.score || 0,
                    evidence,
                    status: 'open',
                    autoAction
                }], { session, ordered: true });
                created = true;
            } else {
                const previous = {
                    severity: flagDoc.severity,
                    score: flagDoc.score,
                    autoAction: flagDoc.autoAction
                };
                flagDoc.severity = getHigherSeverity(flagDoc.severity, signal.severity);
                flagDoc.score = Math.max(Number(flagDoc.score || 0), Number(signal.score || 0));
                flagDoc.matchId = signal.matchId || flagDoc.matchId || null;
                flagDoc.roomId = signal.roomId || flagDoc.roomId || null;
                flagDoc.seasonId = signal.seasonId || flagDoc.seasonId || null;
                flagDoc.userIds = signal.userIds || flagDoc.userIds || [];
                flagDoc.ipHash = signal.ipHash || flagDoc.ipHash || null;
                flagDoc.deviceHash = signal.deviceHash || flagDoc.deviceHash || null;
                flagDoc.evidence = evidence;
                flagDoc.autoAction = autoAction;
                await flagDoc.save({ session });

                await AuditLog.create([this.buildAuditEntry({
                    entityType: 'fraud_flag',
                    entityId: flagDoc._id,
                    action: 'fraud_flag_updated',
                    actorType,
                    actorId,
                    requestId,
                    userId: signal.userIds?.[0] || null,
                    roomId: signal.roomId || null,
                    matchId: signal.matchId || null,
                    before: previous,
                    after: {
                        severity: flagDoc.severity,
                        score: flagDoc.score,
                        autoAction: flagDoc.autoAction
                    },
                    meta: {
                        subjectType: signal.subjectType,
                        subjectId: signal.subjectId,
                        evidence: signal.evidence
                    }
                })], { session, ordered: true });
            }

            if (created) {
                await AuditLog.create([this.buildAuditEntry({
                    entityType: 'fraud_flag',
                    entityId: flagDoc._id,
                    action: 'fraud_flag_created',
                    actorType,
                    actorId,
                    requestId,
                    userId: signal.userIds?.[0] || null,
                    roomId: signal.roomId || null,
                    matchId: signal.matchId || null,
                    after: {
                        flagType: signal.flagType,
                        severity: signal.severity,
                        score: signal.score || 0,
                        autoAction
                    },
                    meta: {
                        subjectType: signal.subjectType,
                        subjectId: signal.subjectId,
                        evidence: signal.evidence
                    }
                })], { session, ordered: true });
            }

            await this.maybeApplyAutoAction({
                session,
                flagDoc,
                userIds: (signal.userIds || []).map((entry) => toIdString(entry)),
                autoAction,
                severity: signal.severity,
                flagType: signal.flagType,
                actorType,
                actorId,
                requestId
            });

            return {
                skipped: false,
                created,
                flag: flagDoc.toObject(),
                autoAction
            };
        });
    }

    async recordRefundSignal({ matchId, actorType = 'system', actorId = null, requestId = null }) {
        const matchDoc = await ColorClashMatch.findById(matchId)
            .select('roomId seasonId tableMode settlement players riskEvaluation')
            .lean();
        if (!matchDoc) {
            throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for refund signal processing', 404);
        }
        if (matchDoc.riskEvaluation?.refundSignalsAppliedAt) {
            return { skipped: true, alreadyProcessed: true };
        }

        const signals = [];
        for (const userId of this.getUserIds(matchDoc)) {
            signals.push(await this.checkRefundAbuse({ userId }));
            signals.push(await this.checkWalletCycle({ userId }));
        }

        const scope = resolveScope(matchDoc) === 'ranked' ? 'ranked' : 'stake';
        const results = [];
        for (const signal of signals) {
            if (!signal) continue;
            results.push(await this.maybeCreateFlag({
                signal: {
                    ...signal,
                    matchId: matchDoc._id,
                    roomId: matchDoc.roomId,
                    seasonId: matchDoc.seasonId || null
                },
                scope,
                actorType,
                actorId,
                requestId
            }));
        }

        await ColorClashMatch.findByIdAndUpdate(matchId, {
            $set: {
                'riskEvaluation.refundSignalsAppliedAt': new Date(this.now()),
                'riskEvaluation.lastProcessedAt': new Date(this.now()),
                'riskEvaluation.error': null
            }
        });

        return {
            skipped: false,
            processed: signals.length,
            flags: results.filter((entry) => !entry.skipped)
        };
    }

    async recordTimeoutSignal({ matchId, userId, actorType = 'system', actorId = null, requestId = null }) {
        const matchDoc = matchId
            ? await ColorClashMatch.findById(matchId).select('tableMode settlement configSnapshot').lean()
            : null;
        const signal = await this.checkTimeoutAbuse({ userId });
        return this.maybeCreateFlag({
            signal: {
                ...signal,
                matchId,
                subjectType: 'user',
                subjectId: toIdString(userId),
                userIds: [userId]
            },
            scope: resolveScope(matchDoc),
            actorType,
            actorId,
            requestId
        });
    }

    async recordForfeitSignal({ matchId, userId, actorType = 'system', actorId = null, requestId = null }) {
        const matchDoc = matchId
            ? await ColorClashMatch.findById(matchId).select('tableMode settlement configSnapshot').lean()
            : null;
        const signal = await this.checkSurrenderAbuse({ userId });
        return this.maybeCreateFlag({
            signal: {
                ...signal,
                matchId,
                subjectType: 'user',
                subjectId: toIdString(userId),
                userIds: [userId]
            },
            scope: resolveScope(matchDoc),
            actorType,
            actorId,
            requestId
        });
    }

    async recordMatchOutcomeSignals({ matchId, actorType = 'system', actorId = null, requestId = null }) {
        const matchDoc = await ColorClashMatch.findById(matchId)
            .select('roomId seasonId tableMode status settlement players playerContexts roundResult riskEvaluation')
            .lean();
        if (!matchDoc) {
            throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for fraud signal processing', 404);
        }
        if (matchDoc.riskEvaluation?.matchSignalsAppliedAt) {
            return {
                skipped: true,
                alreadyProcessed: true
            };
        }
        if (!isCompetitiveMatch(matchDoc)) {
            await ColorClashMatch.findByIdAndUpdate(matchId, {
                $set: {
                    'riskEvaluation.matchSignalsAppliedAt': new Date(this.now()),
                    'riskEvaluation.lastProcessedAt': new Date(this.now()),
                    'riskEvaluation.error': null
                }
            });
            return {
                skipped: true,
                reason: 'non_competitive'
            };
        }

        const scope = resolveScope(matchDoc);
        const userIds = this.getUserIds(matchDoc);
        const results = [];
        const pairSignals = [];

        for (let index = 0; index < userIds.length; index += 1) {
            for (let inner = index + 1; inner < userIds.length; inner += 1) {
                const repeatedPairing = await this.checkRepeatedPairing({
                    matchDoc,
                    leftUserId: userIds[index],
                    rightUserId: userIds[inner]
                });
                pairSignals.push(repeatedPairing);
                pairSignals.push(await this.checkSameIpPairing({
                    matchDoc,
                    leftUserId: userIds[index],
                    rightUserId: userIds[inner],
                    repeatedPairingSignal: repeatedPairing
                }));
            }
        }

        for (const signal of pairSignals) {
            results.push(await this.maybeCreateFlag({
                signal,
                scope,
                actorType,
                actorId,
                requestId
            }));
        }

        for (const userId of userIds) {
            const timeoutSignal = await this.checkTimeoutAbuse({ userId });
            const forfeitSignal = await this.checkSurrenderAbuse({ userId });
            const diversitySignal = await this.checkLowOpponentDiversity({ userId });
            const walletCycleSignal = scope === 'stake'
                ? await this.checkWalletCycle({ userId })
                : null;

            for (const signal of [timeoutSignal, forfeitSignal, diversitySignal, walletCycleSignal]) {
                if (!signal) continue;
                results.push(await this.maybeCreateFlag({
                    signal: {
                        ...signal,
                        matchId: matchDoc._id,
                        roomId: matchDoc.roomId,
                        seasonId: matchDoc.seasonId || null
                    },
                    scope,
                    actorType,
                    actorId,
                    requestId
                }));
            }
        }

        await ColorClashMatch.findByIdAndUpdate(matchId, {
            $set: {
                'riskEvaluation.matchSignalsAppliedAt': new Date(this.now()),
                'riskEvaluation.lastProcessedAt': new Date(this.now()),
                'riskEvaluation.error': null
            }
        });

        return {
            skipped: false,
            processed: results.length,
            flags: results.filter((entry) => !entry.skipped)
        };
    }
}

const antiFraudService = new ColorClashAntiFraudService();

module.exports = antiFraudService;
module.exports.ColorClashAntiFraudService = ColorClashAntiFraudService;
module.exports.hashValue = hashValue;
module.exports.isCompetitiveMatch = isCompetitiveMatch;
module.exports.resolveScope = resolveScope;
