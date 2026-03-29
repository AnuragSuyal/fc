const mongoose = require('mongoose');

const AuditLog = require('../models/AuditLog');
const ColorClashMatch = require('../models/ColorClashMatch');
const ColorClashSeason = require('../models/ColorClashSeason');
const ColorClashSeasonProgress = require('../models/ColorClashSeasonProgress');
const User = require('../models/User');
const rankingService = require('./rankingService');
const telemetry = require('./colorClashTelemetry');
const { RANKED_MIN_LEVEL } = require('../utils/colorClashValidation');

const GAME_ID = 'color_clash';
const LEADERBOARD_PREVIEW_LIMIT = 10;
const LEADERBOARD_SYNC_LIMIT = 200;
const RANK_LOCK_TTL_MS = 10000;
const FINAL_LEADERBOARD_LIMIT = 100;

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

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const buildDefaultTiers = () => ([
    { id: 'spark', name: 'Spark', order: 1, minRating: 0, maxRating: 999, divisions: 3, starsPerDivision: 4 },
    { id: 'pulse', name: 'Pulse', order: 2, minRating: 1000, maxRating: 1199, divisions: 3, starsPerDivision: 4 },
    { id: 'flux', name: 'Flux', order: 3, minRating: 1200, maxRating: 1399, divisions: 3, starsPerDivision: 4 },
    { id: 'prism', name: 'Prism', order: 4, minRating: 1400, maxRating: 1599, divisions: 3, starsPerDivision: 4 },
    { id: 'nova', name: 'Nova', order: 5, minRating: 1600, maxRating: 1799, divisions: 3, starsPerDivision: 4 },
    { id: 'zenith', name: 'Zenith', order: 6, minRating: 1800, maxRating: 2400, divisions: 1, starsPerDivision: 5 }
]);

const buildDefaultRewardConfig = () => ({
    seasonRewards: [
        { tierId: 'spark', coins: 100 },
        { tierId: 'pulse', coins: 250 },
        { tierId: 'flux', coins: 500 },
        { tierId: 'prism', coins: 750 },
        { tierId: 'nova', coins: 1000 },
        { tierId: 'zenith', coins: 1500 }
    ],
    leaderboardRewards: []
});

const buildSeasonWindow = (nowDate) => {
    const start = new Date(Date.UTC(
        nowDate.getUTCFullYear(),
        nowDate.getUTCMonth(),
        1,
        0,
        0,
        0,
        0
    ));
    const end = new Date(Date.UTC(
        nowDate.getUTCFullYear(),
        nowDate.getUTCMonth() + 1,
        1,
        0,
        0,
        0,
        -1
    ));
    const finalizeAt = new Date(end.getTime() + (2 * 24 * 60 * 60 * 1000));
    return { start, end, finalizeAt };
};

const buildSeasonKey = (nowDate) => `${GAME_ID}-${nowDate.getUTCFullYear()}-${String(nowDate.getUTCMonth() + 1).padStart(2, '0')}`;

const normalizeRankInput = (entry = {}) => ({
    userId: toIdString(entry.userId),
    seatIndex: Number.isInteger(entry.seatIndex) ? entry.seatIndex : null,
    placement: Math.max(1, Number(entry.placement || 1)),
    outcome: entry.outcome || (Number(entry.placement || 1) === 1 ? 'win' : 'loss'),
    handPointsRemaining: Math.max(0, Number(entry.handPointsRemaining || entry.handPoints || 0)),
    timeoutStrikes: Math.max(0, Number(entry.timeoutStrikes || 0)),
    status: entry.status || 'active'
});

class ColorClashSeasonService {
    constructor({ redis = null, now = () => Date.now() } = {}) {
        this.redis = redis;
        this.now = now;
    }

    configure({ redis, now } = {}) {
        if (redis) {
            this.redis = redis;
            rankingService.configure({ redisClient: redis });
        }
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

    async withRankLock(matchId, work) {
        if (!this.redis) {
            return work();
        }

        const lockKey = `cc:lock:rank:${toIdString(matchId)}`;
        const token = `${this.now()}:${Math.random()}`;
        const acquired = await this.redis.set(lockKey, token, { NX: true, PX: RANK_LOCK_TTL_MS });
        if (!acquired) {
            throw createServiceError('RANK_LOCK_UNAVAILABLE', 'Another ranked update is in progress for this match', 409);
        }

        try {
            return await work();
        } finally {
            const currentValue = await this.redis.get(lockKey);
            if (currentValue === token) {
                await this.redis.del(lockKey);
            }
        }
    }

    async reconcileSeasonStatuses({ session = null } = {}) {
        const nowDate = new Date(this.now());
        await applySession(ColorClashSeason.updateMany({
            status: 'active',
            endsAt: { $lt: nowDate }
        }, {
            $set: { status: 'settling', updatedAt: nowDate }
        }), session);

        await applySession(ColorClashSeason.updateMany({
            status: 'upcoming',
            startsAt: { $lte: nowDate },
            endsAt: { $gte: nowDate }
        }, {
            $set: { status: 'active', updatedAt: nowDate }
        }), session);

        await applySession(ColorClashSeason.updateMany({
            status: 'settling',
            finalizeAt: { $lte: nowDate }
        }, {
            $set: { status: 'archived', updatedAt: nowDate }
        }), session);
    }

    buildDefaultSeason(nowDate = new Date(this.now())) {
        const { start, end, finalizeAt } = buildSeasonWindow(nowDate);
        const monthName = nowDate.toLocaleString('en-US', {
            month: 'long',
            year: 'numeric',
            timeZone: 'UTC'
        });
        return {
            key: buildSeasonKey(nowDate),
            name: `Color Clash ${monthName}`,
            status: 'active',
            startsAt: start,
            endsAt: end,
            finalizeAt,
            placementMatches: 5,
            rankedEnabled: true,
            tiers: buildDefaultTiers(),
            ratingConfig: {
                baseRating: 1000,
                kFactor: 32,
                streakBonus: 4,
                placementMultiplier: 1.5,
                inactivityDecay: 0
            },
            rewardConfig: buildDefaultRewardConfig(),
            themeRotation: ['forest_picnic', 'neon_orbit', 'candy_carnival'],
            finalLeaderboard: []
        };
    }

    serializeSeason(season) {
        if (!season) return null;
        return {
            id: toIdString(season._id),
            key: season.key,
            name: season.name,
            status: season.status,
            startsAt: season.startsAt,
            endsAt: season.endsAt,
            finalizeAt: season.finalizeAt,
            placementMatches: Number(season.placementMatches || 0),
            rankedEnabled: season.rankedEnabled !== false,
            tiers: season.tiers || [],
            ratingConfig: season.ratingConfig || {},
            rewardPreview: season.rewardConfig?.seasonRewards || [],
            themeRotation: season.themeRotation || []
        };
    }

    deriveTierState({ season, rating }) {
        const tiers = (season?.tiers || buildDefaultTiers())
            .slice()
            .sort((left, right) => Number(left.order || 0) - Number(right.order || 0));
        if (!tiers.length) {
            return {
                tierId: '',
                tierName: '',
                division: 1,
                stars: 0
            };
        }

        const safeRating = Math.max(0, Math.round(Number(rating || 0)));
        let tier = tiers[0];
        for (const candidate of tiers) {
            if (safeRating >= Number(candidate.minRating || 0)) {
                tier = candidate;
            }
            if (safeRating <= Number(candidate.maxRating || 0)) {
                break;
            }
        }

        const divisions = Math.max(1, Number(tier.divisions || 1));
        const starsPerDivision = Math.max(1, Number(tier.starsPerDivision || 1));
        const minRating = Number(tier.minRating || 0);
        const maxRating = Math.max(minRating, Number(tier.maxRating || minRating));

        let division = 1;
        let stars = 0;
        if (safeRating >= maxRating) {
            division = divisions;
            stars = starsPerDivision;
        } else if (safeRating > minRating) {
            const span = Math.max(1, (maxRating - minRating) + 1);
            const steps = divisions * starsPerDivision;
            const relative = clamp((safeRating - minRating) / span, 0, 0.999999);
            const stepIndex = Math.floor(relative * steps);
            division = Math.floor(stepIndex / starsPerDivision) + 1;
            stars = stepIndex % starsPerDivision;
        }

        return {
            tierId: tier.id,
            tierName: tier.name,
            division,
            stars,
            divisions,
            starsPerDivision
        };
    }

    async getCurrentSeason({ allowProvision = true, session = null } = {}) {
        await this.reconcileSeasonStatuses({ session });
        const nowDate = new Date(this.now());

        let season = await applySession(ColorClashSeason.findOne({
            status: 'active',
            startsAt: { $lte: nowDate },
            endsAt: { $gte: nowDate }
        }).sort({ startsAt: -1 }), session);

        if (season || !allowProvision) {
            return season;
        }

        const defaultSeason = this.buildDefaultSeason(nowDate);
        try {
            [season] = await ColorClashSeason.create([defaultSeason], { session, ordered: true });
        } catch (error) {
            if (error?.code !== 11000) {
                throw error;
            }
            season = await applySession(ColorClashSeason.findOne({ key: defaultSeason.key }), session);
        }
        return season;
    }

    async assertRankedAccess({ user, season = null }) {
        if (!user) {
            throw createServiceError('USER_NOT_FOUND', 'User not found', 404);
        }
        if (user.isGuest) {
            throw createServiceError('ACCOUNT_UPGRADE_REQUIRED', 'Registered accounts are required for ranked Color Clash', 403);
        }
        if (Number(user.level || 1) < RANKED_MIN_LEVEL) {
            throw createServiceError('RANKED_LOCKED', `Ranked queue unlocks at level ${RANKED_MIN_LEVEL}`, 403);
        }
        if (user.settings?.colorClash?.rankedAccessLocked || user.settings?.colorClash?.rankedLock?.active) {
            throw createServiceError(
                'RANKED_ACCESS_LOCKED',
                user.settings?.colorClash?.rankedLock?.reason ||
                user.settings?.colorClash?.rankedAccessLockReason ||
                'Ranked Color Clash access is temporarily locked for this account',
                403
            );
        }

        const resolvedSeason = season || await this.getCurrentSeason({ allowProvision: true });
        if (!resolvedSeason || resolvedSeason.status !== 'active' || resolvedSeason.rankedEnabled === false) {
            throw createServiceError('RANKED_SEASON_UNAVAILABLE', 'There is no active ranked Color Clash season right now', 403);
        }

        return resolvedSeason;
    }

    async getOrCreateSeasonProgress({ season, userId, session = null }) {
        if (!season?._id || !userId) {
            throw createServiceError('SEASON_PROGRESS_CONTEXT_MISSING', 'Season progress requires both season and user', 400);
        }

        let progress = await applySession(ColorClashSeasonProgress.findOne({
            seasonId: season._id,
            userId
        }), session);

        if (progress) {
            return progress;
        }

        const initialTier = this.deriveTierState({
            season,
            rating: season.ratingConfig?.baseRating || 1000
        });

        try {
            [progress] = await ColorClashSeasonProgress.create([{
                seasonId: season._id,
                userId,
                rating: Number(season.ratingConfig?.baseRating || 1000),
                peakRating: Number(season.ratingConfig?.baseRating || 1000),
                tierId: initialTier.tierId,
                division: initialTier.division,
                stars: initialTier.stars,
                placementMatchesRemaining: Number(season.placementMatches || 0),
                wins: 0,
                losses: 0,
                currentStreak: 0,
                bestStreak: 0,
                timeoutLosses: 0,
                forfeitLosses: 0,
                opponentDiversityScore: 100,
                smurfWatch: false,
                leaderboardScore: Number(season.ratingConfig?.baseRating || 1000),
                rewardStatus: 'pending',
                recentOpponentIds: []
            }], { session, ordered: true });
        } catch (error) {
            if (error?.code !== 11000) {
                throw error;
            }
            progress = await applySession(ColorClashSeasonProgress.findOne({
                seasonId: season._id,
                userId
            }), session);
        }

        return progress;
    }

    buildRankInputs(matchDoc) {
        const rawInputs = Array.isArray(matchDoc?.roundResult?.rankInputs) && matchDoc.roundResult.rankInputs.length
            ? matchDoc.roundResult.rankInputs
            : (matchDoc?.roundResult?.placements || []).map((placement) => ({
                userId: placement.userId,
                seatIndex: placement.seatIndex,
                placement: placement.placement,
                outcome: Number(placement.placement || 0) === 1 ? 'win' : 'loss',
                handPointsRemaining: placement.handPoints || 0,
                timeoutStrikes: placement.timeoutStrikes || 0,
                status: placement.status || 'active'
            }));

        return rawInputs
            .map(normalizeRankInput)
            .filter((entry) => entry.userId)
            .sort((left, right) => left.placement - right.placement || left.userId.localeCompare(right.userId));
    }

    maybeMarkSmurfWatch({ user, nextProgress, season }) {
        if (nextProgress.smurfWatch) {
            return true;
        }

        const totalMatches = Number(nextProgress.wins || 0) + Number(nextProgress.losses || 0);
        const winRate = totalMatches > 0 ? Number(nextProgress.wins || 0) / totalMatches : 0;
        const baseRating = Number(season?.ratingConfig?.baseRating || 1000);

        return Boolean(
            ['high', 'critical'].includes(user?.settings?.colorClash?.riskState?.severity || 'none') ||
            Number(user?.level || 1) <= (RANKED_MIN_LEVEL + 1) &&
            totalMatches >= 5 &&
            (winRate >= 0.8 || Number(nextProgress.rating || 0) >= (baseRating + 180))
        );
    }

    computeRankedResults({ season, matchDoc, progressByUserId }) {
        const rankInputs = this.buildRankInputs(matchDoc);
        if (!rankInputs.length) {
            throw createServiceError('RANK_INPUTS_MISSING', 'Ranked Color Clash settlement requires round rank inputs', 409);
        }

        const baseK = Number(season.ratingConfig?.kFactor || 32);
        const streakBonus = Number(season.ratingConfig?.streakBonus || 0);
        const placementMultiplier = Number(season.ratingConfig?.placementMultiplier || 1);
        const maxPlacement = Math.max(...rankInputs.map((entry) => Number(entry.placement || 1)));

        return rankInputs.map((input) => {
            const progress = progressByUserId.get(input.userId);
            if (!progress) {
                throw createServiceError('SEASON_PROGRESS_MISSING', 'Ranked Color Clash player progress could not be loaded', 500, {
                    failedUserId: input.userId
                });
            }

            const placementScore = maxPlacement <= 1
                ? 1
                : (maxPlacement - Math.max(1, Number(input.placement || maxPlacement))) / (maxPlacement - 1);
            const opponents = rankInputs.filter((entry) => entry.userId !== input.userId);
            const expected = opponents.length
                ? opponents.reduce((total, opponent) => {
                    const opponentProgress = progressByUserId.get(opponent.userId);
                    const opponentRating = Number(opponentProgress?.rating || season.ratingConfig?.baseRating || 1000);
                    return total + (1 / (1 + (10 ** ((opponentRating - Number(progress.rating || 0)) / 400))));
                }, 0) / opponents.length
                : 1;

            const placementBoost = Number(progress.placementMatchesRemaining || 0) > 0 ? placementMultiplier : 1;
            const kFactor = Math.max(1, Math.round(baseK * placementBoost));
            let ratingDelta = Math.round(kFactor * (placementScore - expected));

            if (input.outcome === 'win' || Number(input.placement || 0) === 1) {
                ratingDelta += streakBonus * Math.min(3, Math.max(0, Number(progress.currentStreak || 0)));
            }
            if (Number(input.timeoutStrikes || 0) > 0) {
                ratingDelta -= Math.min(10, Number(input.timeoutStrikes || 0) * 2);
            }
            if (input.status === 'forfeited' || input.outcome === 'forfeit') {
                ratingDelta -= 12;
            }
            if (placementScore < 1 && ratingDelta >= 0) {
                ratingDelta = -1;
            }

            const ratingBefore = Number(progress.rating || season.ratingConfig?.baseRating || 1000);
            const ratingAfter = Math.max(0, ratingBefore + ratingDelta);
            const tierState = this.deriveTierState({ season, rating: ratingAfter });
            return {
                userId: input.userId,
                seatIndex: input.seatIndex,
                placement: input.placement,
                outcome: input.outcome,
                timeoutStrikes: Number(input.timeoutStrikes || 0),
                status: input.status,
                ratingBefore,
                ratingAfter,
                ratingDelta,
                tierState
            };
        });
    }

    async updateLeaderboard({ seasonId, progressEntries = [] }) {
        if (!seasonId || !progressEntries.length) {
            return { updated: 0 };
        }

        for (const entry of progressEntries) {
            await rankingService.updateColorClashSeasonRank({
                seasonId,
                userId: entry.userId,
                rating: entry.leaderboardScore ?? entry.rating
            });
        }

        return { updated: progressEntries.length };
    }

    async applyRankedMatchResult({ matchId, requestId = null, actorType = 'system', actorId = null } = {}) {
        return this.withRankLock(matchId, async () => {
            const transactionResult = await this.runInTransaction('ranked progression', async (session) => {
                const matchDoc = await applySession(ColorClashMatch.findById(matchId), session);
                if (!matchDoc) {
                    throw createServiceError('MATCH_NOT_FOUND', 'Color Clash match not found for ranked progression', 404);
                }

                if (matchDoc.tableMode !== 'ranked') {
                    if (matchDoc.rankProgression?.status !== 'skipped') {
                        matchDoc.set({
                            rankProgression: {
                                ...(matchDoc.rankProgression?.toObject ? matchDoc.rankProgression.toObject() : matchDoc.rankProgression || {}),
                                status: 'skipped',
                                error: null
                            }
                        });
                        await matchDoc.save({ session });
                    }
                    return {
                        skipped: true,
                        alreadyApplied: false,
                        season: null,
                        results: []
                    };
                }

                if (!['settled', 'skipped'].includes(matchDoc.settlement?.status)) {
                    throw createServiceError('SETTLEMENT_NOT_FINAL', 'Ranked Color Clash progression requires a final settlement state', 409);
                }

                if (matchDoc.rankProgression?.status === 'applied') {
                    const season = matchDoc.seasonId
                        ? await applySession(ColorClashSeason.findById(matchDoc.seasonId), session)
                        : null;
                    return {
                        skipped: false,
                        alreadyApplied: true,
                        season,
                        results: matchDoc.rankProgression?.results || []
                    };
                }

                const season = matchDoc.seasonId
                    ? await applySession(ColorClashSeason.findById(matchDoc.seasonId), session)
                    : await this.getCurrentSeason({ allowProvision: true, session });

                if (!season) {
                    throw createServiceError('SEASON_NOT_FOUND', 'No Color Clash season is available for ranked progression', 404);
                }

                if (!matchDoc.seasonId) {
                    matchDoc.seasonId = season._id;
                }

                const users = await applySession(User.find({
                    _id: { $in: (matchDoc.players || []).map((player) => player.userId) }
                }), session);
                const userById = new Map(users.map((user) => [toIdString(user._id), user]));
                const progressDocs = await Promise.all((matchDoc.players || []).map((player) =>
                    this.getOrCreateSeasonProgress({
                        season,
                        userId: player.userId,
                        session
                    })
                ));
                const progressByUserId = new Map(progressDocs.map((progress) => [toIdString(progress.userId), progress]));
                const results = this.computeRankedResults({
                    season,
                    matchDoc,
                    progressByUserId
                });

                const auditEntries = [];
                const savedProgressEntries = [];

                for (const result of results) {
                    const progressDoc = progressByUserId.get(result.userId);
                    const userDoc = userById.get(result.userId);
                    if (!progressDoc || !userDoc) {
                        throw createServiceError('RANKED_PLAYER_CONTEXT_MISSING', 'Ranked Color Clash player context is incomplete', 500, {
                            failedUserId: result.userId
                        });
                    }

                    const winsBefore = Number(progressDoc.wins || 0);
                    const lossesBefore = Number(progressDoc.losses || 0);
                    const currentStreakBefore = Number(progressDoc.currentStreak || 0);

                    progressDoc.rating = result.ratingAfter;
                    progressDoc.peakRating = Math.max(Number(progressDoc.peakRating || 0), result.ratingAfter);
                    progressDoc.tierId = result.tierState.tierId;
                    progressDoc.division = result.tierState.division;
                    progressDoc.stars = result.tierState.stars;
                    progressDoc.placementMatchesRemaining = Math.max(0, Number(progressDoc.placementMatchesRemaining || 0) - 1);
                    progressDoc.wins = winsBefore + ((result.outcome === 'win' || Number(result.placement || 0) === 1) ? 1 : 0);
                    progressDoc.losses = lossesBefore + ((result.outcome === 'win' || Number(result.placement || 0) === 1) ? 0 : 1);
                    progressDoc.currentStreak = (result.outcome === 'win' || Number(result.placement || 0) === 1)
                        ? currentStreakBefore + 1
                        : 0;
                    progressDoc.bestStreak = Math.max(Number(progressDoc.bestStreak || 0), Number(progressDoc.currentStreak || 0));
                    progressDoc.timeoutLosses = Number(progressDoc.timeoutLosses || 0) + (result.timeoutStrikes > 0 && result.outcome !== 'win' ? 1 : 0);
                    progressDoc.forfeitLosses = Number(progressDoc.forfeitLosses || 0) + (result.status === 'forfeited' ? 1 : 0);
                    const recentOpponents = [
                        ...progressDoc.recentOpponentIds.map((entry) => toIdString(entry)),
                        ...results.filter((entry) => entry.userId !== result.userId).map((entry) => entry.userId)
                    ].slice(-10);
                    progressDoc.recentOpponentIds = recentOpponents.map((entry) => new mongoose.Types.ObjectId(entry));
                    const uniqueOpponents = new Set(recentOpponents);
                    progressDoc.opponentDiversityScore = recentOpponents.length
                        ? Math.round((uniqueOpponents.size / recentOpponents.length) * 100)
                        : 100;
                    progressDoc.lastMatchId = matchDoc._id;
                    progressDoc.leaderboardScore = result.ratingAfter;
                    progressDoc.smurfWatch = this.maybeMarkSmurfWatch({
                        user: userDoc,
                        nextProgress: progressDoc,
                        season
                    });
                    await progressDoc.save({ session });
                    savedProgressEntries.push(progressDoc);

                    userDoc.gameStats = userDoc.gameStats || {};
                    userDoc.gameStats.colorClash = userDoc.gameStats.colorClash || {};
                    userDoc.gameStats.colorClash.rankedPlayed = Number(userDoc.gameStats.colorClash.rankedPlayed || 0) + 1;
                    if (result.outcome === 'win' || Number(result.placement || 0) === 1) {
                        userDoc.gameStats.colorClash.rankedWon = Number(userDoc.gameStats.colorClash.rankedWon || 0) + 1;
                    }
                    userDoc.gameStats.colorClash.currentRating = result.ratingAfter;
                    const tierOrderById = new Map((season.tiers || []).map((tier) => [tier.id, Number(tier.order || 0)]));
                    const currentBestTierId = userDoc.gameStats.colorClash.seasonBestTier || '';
                    const currentBestOrder = Number(tierOrderById.get(currentBestTierId) || 0);
                    const nextTierOrder = Number(tierOrderById.get(result.tierState.tierId) || 0);
                    if (!currentBestTierId || nextTierOrder >= currentBestOrder) {
                        userDoc.gameStats.colorClash.seasonBestTier = result.tierState.tierId;
                    }
                    await userDoc.save({ session });

                    auditEntries.push({
                        entityType: 'rank_progress',
                        entityId: progressDoc._id,
                        action: 'ranked_match_applied',
                        actorType,
                        actorId,
                        requestId,
                        userId: userDoc._id,
                        roomId: matchDoc.roomId,
                        matchId: matchDoc._id,
                        before: {
                            rating: result.ratingBefore,
                            wins: winsBefore,
                            losses: lossesBefore
                        },
                        after: {
                            rating: result.ratingAfter,
                            wins: progressDoc.wins,
                            losses: progressDoc.losses,
                            tierId: result.tierState.tierId,
                            division: result.tierState.division,
                            stars: result.tierState.stars
                        },
                        meta: {
                            seasonId: season._id,
                            placement: result.placement,
                            ratingDelta: result.ratingDelta
                        },
                        createdAt: new Date(this.now())
                    });
                }

                const serializedResults = results.map((result) => ({
                    userId: new mongoose.Types.ObjectId(result.userId),
                    placement: result.placement,
                    ratingBefore: result.ratingBefore,
                    ratingAfter: result.ratingAfter,
                    ratingDelta: result.ratingDelta,
                    tierId: result.tierState.tierId,
                    division: result.tierState.division,
                    stars: result.tierState.stars
                }));

                matchDoc.set({
                    seasonId: season._id,
                    rankProgression: {
                        ...(matchDoc.rankProgression?.toObject ? matchDoc.rankProgression.toObject() : matchDoc.rankProgression || {}),
                        status: 'applied',
                        seasonId: season._id,
                        appliedAt: new Date(this.now()),
                        error: null,
                        leaderboardSyncError: null,
                        results: serializedResults
                    }
                });
                await matchDoc.save({ session });

                if (auditEntries.length) {
                    await AuditLog.create([
                        {
                            entityType: 'match',
                            entityId: matchDoc._id,
                            action: 'rank_progression_applied',
                            actorType,
                            actorId,
                            requestId,
                            roomId: matchDoc.roomId,
                            matchId: matchDoc._id,
                            before: {
                                rankStatus: 'pending'
                            },
                            after: {
                                rankStatus: 'applied',
                                seasonId: season._id
                            },
                            meta: {
                                resultCount: serializedResults.length
                            },
                            createdAt: new Date(this.now())
                        },
                        ...auditEntries
                    ], { session, ordered: true });
                }

                return {
                    skipped: false,
                    alreadyApplied: false,
                    season,
                    results: serializedResults.map((entry) => ({
                        userId: toIdString(entry.userId),
                        placement: entry.placement,
                        ratingBefore: entry.ratingBefore,
                        ratingAfter: entry.ratingAfter,
                        ratingDelta: entry.ratingDelta,
                        tierId: entry.tierId,
                        division: entry.division,
                        stars: entry.stars
                    })),
                    progressEntries: savedProgressEntries.map((entry) => entry.toObject())
                };
            });

            if (transactionResult.skipped || transactionResult.alreadyApplied) {
                telemetry.info('rank_progression_skipped', {
                    matchId,
                    skipped: transactionResult.skipped,
                    alreadyApplied: transactionResult.alreadyApplied
                });
                return transactionResult;
            }

            try {
                await this.updateLeaderboard({
                    seasonId: transactionResult.season._id,
                    progressEntries: transactionResult.progressEntries
                });
                await ColorClashMatch.findByIdAndUpdate(matchId, {
                    $set: {
                        'rankProgression.leaderboardSyncedAt': new Date(this.now()),
                        'rankProgression.leaderboardSyncError': null
                    }
                });
                telemetry.info('leaderboard_sync_success', {
                    matchId,
                    seasonId: transactionResult.season?._id?.toString?.() || null,
                    players: transactionResult.progressEntries?.length || 0
                });
            } catch (error) {
                await ColorClashMatch.findByIdAndUpdate(matchId, {
                    $set: {
                        'rankProgression.leaderboardSyncError': error.code || error.message || 'LEADERBOARD_SYNC_FAILED'
                    }
                }).catch(() => {});
                telemetry.error('leaderboard_sync_failed', {
                    matchId,
                    seasonId: transactionResult.season?._id?.toString?.() || null,
                    code: error.code || 'LEADERBOARD_SYNC_FAILED',
                    message: error.message
                });
            }

            telemetry.info('rank_progression_applied', {
                matchId,
                seasonId: transactionResult.season?._id?.toString?.() || null,
                playerCount: transactionResult.results?.length || 0
            });
            return transactionResult;
        });
    }

    serializeProgress(progress, season) {
        if (!progress) return null;
        const tierState = this.deriveTierState({
            season,
            rating: progress.rating
        });
        return {
            seasonId: toIdString(progress.seasonId),
            userId: toIdString(progress.userId),
            rating: Number(progress.rating || 0),
            peakRating: Number(progress.peakRating || 0),
            tierId: tierState.tierId,
            tierName: tierState.tierName,
            division: Number(progress.division || tierState.division || 1),
            stars: Number(progress.stars ?? tierState.stars ?? 0),
            placementMatchesRemaining: Number(progress.placementMatchesRemaining || 0),
            wins: Number(progress.wins || 0),
            losses: Number(progress.losses || 0),
            currentStreak: Number(progress.currentStreak || 0),
            bestStreak: Number(progress.bestStreak || 0),
            timeoutLosses: Number(progress.timeoutLosses || 0),
            forfeitLosses: Number(progress.forfeitLosses || 0),
            opponentDiversityScore: Number(progress.opponentDiversityScore || 0),
            smurfWatch: Boolean(progress.smurfWatch),
            leaderboardScore: Number(progress.leaderboardScore || progress.rating || 0),
            finalRank: progress.finalRank ?? null,
            rewardStatus: progress.rewardStatus || 'pending',
            lastMatchId: progress.lastMatchId ? toIdString(progress.lastMatchId) : null
        };
    }

    async rebuildLeaderboardFromMongo({ seasonId }) {
        const progresses = await ColorClashSeasonProgress.find({ seasonId })
            .sort({ leaderboardScore: -1, rating: -1, updatedAt: 1 })
            .limit(LEADERBOARD_SYNC_LIMIT)
            .lean();
        if (!progresses.length) {
            return [];
        }

        await this.updateLeaderboard({
            seasonId,
            progressEntries: progresses
        });
        return progresses;
    }

    async getSeasonSummaryForUser({ userId = null, previewLimit = LEADERBOARD_PREVIEW_LIMIT } = {}) {
        const season = await this.getCurrentSeason({ allowProvision: true });
        if (!season) {
            return {
                season: null,
                userProgress: null,
                leaderboardPreview: [],
                userRank: null,
                rewardPreview: []
            };
        }

        let userProgress = null;
        if (userId) {
            userProgress = await this.getOrCreateSeasonProgress({
                season,
                userId
            });
        }

        const leaderboard = await this.getLeaderboard({
            seasonId: season._id,
            limit: previewLimit,
            offset: 0,
            userId
        });

        return {
            season: this.serializeSeason(season),
            userProgress: this.serializeProgress(userProgress, season),
            leaderboardPreview: leaderboard.rankings,
            userRank: leaderboard.userRank,
            rewardPreview: season.rewardConfig?.seasonRewards || []
        };
    }

    async getLeaderboard({ seasonId = null, limit = 50, offset = 0, userId = null } = {}) {
        const season = seasonId
            ? await ColorClashSeason.findById(seasonId).lean()
            : await this.getCurrentSeason({ allowProvision: true });
        if (!season) {
            return {
                season: null,
                rankings: [],
                userRank: null,
                limit: Number(limit || 50),
                offset: Number(offset || 0)
            };
        }

        const resolvedSeasonId = toIdString(season._id);
        let rawRankings = await rankingService.getColorClashSeasonLeaderboard({
            seasonId: resolvedSeasonId,
            limit,
            offset
        });

        if (!rawRankings.length && Number(offset || 0) === 0) {
            await this.rebuildLeaderboardFromMongo({ seasonId: resolvedSeasonId });
            rawRankings = await rankingService.getColorClashSeasonLeaderboard({
                seasonId: resolvedSeasonId,
                limit,
                offset
            });
        }

        const userIds = rawRankings.map((entry) => entry.value);
        const [users, progresses] = await Promise.all([
            User.find({ _id: { $in: userIds } })
                .select('username avatar level vipLevel')
                .lean(),
            ColorClashSeasonProgress.find({
                seasonId: resolvedSeasonId,
                userId: { $in: userIds }
            }).lean()
        ]);
        const userById = new Map(users.map((entry) => [toIdString(entry._id), entry]));
        const progressByUserId = new Map(progresses.map((entry) => [toIdString(entry.userId), entry]));

        let userRank = userId
            ? await rankingService.getColorClashUserSeasonRank({
                seasonId: resolvedSeasonId,
                userId
            })
            : null;
        if (!userRank && userId) {
            const userProgress = await ColorClashSeasonProgress.findOne({
                seasonId: resolvedSeasonId,
                userId
            }).lean();
            if (userProgress) {
                const higherRankCount = await ColorClashSeasonProgress.countDocuments({
                    seasonId: resolvedSeasonId,
                    leaderboardScore: { $gt: Number(userProgress.leaderboardScore || userProgress.rating || 0) }
                });
                userRank = {
                    rank: higherRankCount + 1,
                    score: Math.round(Number(userProgress.leaderboardScore || userProgress.rating || 0))
                };
            }
        }

        return {
            season: this.serializeSeason(season),
            rankings: rawRankings.map((entry, index) => {
                const userDoc = userById.get(entry.value) || {};
                const progressDoc = progressByUserId.get(entry.value) || null;
                const tierState = this.deriveTierState({
                    season,
                    rating: Number(progressDoc?.rating || entry.score || 0)
                });
                return {
                    rank: Number(offset || 0) + index + 1,
                    userId: entry.value,
                    username: userDoc.username || 'Unknown',
                    avatar: userDoc.avatar || 'default-avatar.png',
                    level: userDoc.level || 1,
                    vipLevel: userDoc.vipLevel || 0,
                    rating: Math.round(Number(entry.score || progressDoc?.rating || 0)),
                    tierId: progressDoc?.tierId || tierState.tierId,
                    division: Number(progressDoc?.division || tierState.division || 1),
                    stars: Number(progressDoc?.stars ?? tierState.stars ?? 0)
                };
            }),
            userRank,
            limit: Number(limit || 50),
            offset: Number(offset || 0)
        };
    }

    async finalizeSeasonSnapshot({ seasonId }) {
        const season = await ColorClashSeason.findById(seasonId);
        if (!season) {
            throw createServiceError('SEASON_NOT_FOUND', 'Color Clash season not found for finalization', 404);
        }

        const leaderboard = await this.getLeaderboard({
            seasonId,
            limit: FINAL_LEADERBOARD_LIMIT,
            offset: 0
        });

        season.finalLeaderboard = leaderboard.rankings.map((entry) => ({
            userId: entry.userId,
            rank: entry.rank,
            rating: entry.rating
        }));
        if (season.status === 'settling' && season.finalizeAt <= new Date(this.now())) {
            season.status = 'archived';
        }
        await season.save();

        return {
            season: this.serializeSeason(season),
            finalLeaderboard: season.finalLeaderboard
        };
    }
}

const seasonService = new ColorClashSeasonService();

module.exports = seasonService;
module.exports.ColorClashSeasonService = ColorClashSeasonService;
module.exports.buildDefaultTiers = buildDefaultTiers;
