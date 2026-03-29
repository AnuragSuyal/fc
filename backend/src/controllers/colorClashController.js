const Room = require('../models/Room');
const User = require('../models/User');
const rankingService = require('../services/rankingService');
const matchService = require('../services/colorClashMatchService');
const snapshotService = require('../services/colorClashSnapshotService');
const matchmakingService = require('../services/colorClashMatchmakingService');
const antiFraudService = require('../services/colorClashAntiFraudService');
const seasonService = require('../services/colorClashSeasonService');
const settlementService = require('../services/colorClashSettlementService');
const telemetry = require('../services/colorClashTelemetry');
const { isRoomAdmin } = require('../utils/roomPermissions');
const {
    DEFAULT_THEME_PACK_ID,
    RANKED_MIN_LEVEL,
    THEME_PACK_IDS
} = require('../utils/colorClashValidation');
const { createServiceError } = require('../services/colorClashMatchService');

const configureServices = (req) => {
    const redis = req.app.get('redis');
    const io = req.app.get('io');
    matchService.configure({ redis, io });
    matchmakingService.configure({ redis, io });
    antiFraudService.configure({});
    seasonService.configure({ redis });
    rankingService.configure({ redisClient: redis });
};

const getCurrentUser = async (req) => {
    const user = await User.findById(req.userId)
        .select('username avatar friends blockedUsers region level coins isGuest settings gameStats')
        .lean();

    if (!user) {
        throw createServiceError('USER_NOT_FOUND', 'User not found', 404);
    }

    return user;
};

const buildRoomPayload = (room, lobby, viewerRole) => ({
    room: matchmakingService.serializeRoomSummary(room),
    lobby: matchService.sanitizeLobbyForClient(lobby),
    viewerRole
});

const buildRequestContext = (req, user = null) => antiFraudService.buildRequestContext({
    ip: req.ip,
    deviceHash: user?.settings?.colorClash?.deviceHash || null
});

const buildEligibilityPayload = async (user, seasonSummary = null) => {
    const locks = await antiFraudService.getActiveLocksForUser({ user });
    const severity = locks?.riskState?.severity || 'none';
    return {
        rankedEligible: !user.isGuest &&
            Number(user.level || 1) >= RANKED_MIN_LEVEL &&
            !locks.rankedLocked &&
            Boolean(seasonSummary?.season?.rankedEnabled !== false && seasonSummary?.season),
        stakeEligible: !user.isGuest && !locks.stakeLocked,
        rankedLockReason: locks.rankedLocked ? locks.rankedLockReason : '',
        stakeLockReason: locks.stakeLocked ? locks.stakeLockReason : '',
        riskState: {
            severity,
            hasWarning: ['medium', 'high', 'critical'].includes(severity),
            locked: Boolean(locks.rankedLocked || locks.stakeLocked)
        }
    };
};

exports.getHome = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const [payload, seasonSummary] = await Promise.all([
            matchmakingService.getHome({ user }),
            seasonService.getSeasonSummaryForUser({ userId: req.userId })
        ]);
        const eligibility = await buildEligibilityPayload(user, seasonSummary);
        payload.season = seasonSummary.season;
        payload.userProgress = {
            ...payload.userProgress,
            currentSeason: seasonSummary.userProgress,
            currentUserRank: seasonSummary.userRank,
            eligibility
        };
        payload.leaderboardPreview = seasonSummary.leaderboardPreview;
        payload.rewardPreview = seasonSummary.rewardPreview;
        telemetry.info('home_viewed', {
            userId: req.userId,
            activeMatchId: payload.activeMatch?.matchId || null,
            hasQueueTicket: Boolean(payload.userProgress?.activeQueueTicketId)
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.getTables = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const payload = await matchmakingService.getTables({
            user,
            query: req.colorClashInput.query
        });
        telemetry.info('tables_viewed', {
            userId: req.userId,
            mode: req.colorClashInput.query.mode || 'all',
            roomCount: payload.rooms?.length || 0
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.createRoom = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const result = await matchmakingService.createFriendRoom({
            user,
            payload: req.colorClashInput.body,
            requestContext: buildRequestContext(req, user)
        });
        telemetry.info('room_created', {
            userId: req.userId,
            roomId: result.room?._id?.toString?.() || null,
            visibility: req.colorClashInput.body.visibility,
            tableMode: req.colorClashInput.body.tableMode
        });
        res.status(201).json(buildRoomPayload(result.room, result.lobby, result.viewerRole));
    } catch (error) {
        next(error);
    }
};

exports.joinRoom = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const roomId = req.colorClashInput.params.roomId;
        const result = await matchmakingService.joinFriendRoom({
            roomId,
            user,
            spectator: req.colorClashInput.body.spectator,
            requestContext: buildRequestContext(req, user)
        });
        telemetry.info(req.colorClashInput.body.spectator ? 'spectator_joined' : 'room_joined', {
            userId: req.userId,
            roomId,
            viewerRole: result.viewerRole
        });
        res.json(buildRoomPayload(result.room, result.lobby, result.viewerRole));
    } catch (error) {
        next(error);
    }
};

exports.joinMatchmaking = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const result = await matchmakingService.joinQueue({
            user,
            payload: req.colorClashInput.body,
            requestContext: buildRequestContext(req, user)
        });
        telemetry.info('queue_joined', {
            userId: req.userId,
            mode: req.colorClashInput.body.mode,
            stakeAmount: req.colorClashInput.body.stakeAmount || 0,
            status: result.status,
            queueTicketId: result.queueTicketId || null
        });
        res.json(result);
    } catch (error) {
        next(error);
    }
};

exports.leaveMatchmaking = async (req, res, next) => {
    try {
        configureServices(req);
        const result = await matchmakingService.leaveQueue({
            userId: req.userId,
            queueTicketId: req.colorClashInput.body.queueTicketId || null
        });
        telemetry.info('queue_left', {
            userId: req.userId,
            queueTicketId: req.colorClashInput.body.queueTicketId || null,
            removed: result.removed
        });
        res.json(result);
    } catch (error) {
        next(error);
    }
};

exports.setReady = async (req, res, next) => {
    try {
        configureServices(req);
        const user = await getCurrentUser(req);
        const roomId = req.colorClashInput.params.roomId;
        const lobby = await matchService.setReady({
            roomId,
            userId: req.userId,
            ready: req.colorClashInput.body.ready,
            seatIndex: req.colorClashInput.body.seatIndex,
            profile: {
                username: user.username,
                avatar: user.avatar || ''
            },
            riskContext: buildRequestContext(req, user)
        });
        telemetry.info('ready_toggled', {
            userId: req.userId,
            roomId,
            ready: req.colorClashInput.body.ready,
            seatIndex: req.colorClashInput.body.seatIndex ?? null
        });
        res.json({
            roomId,
            lobby,
            viewerRole: 'player'
        });
    } catch (error) {
        next(error);
    }
};

exports.cancelRoom = async (req, res, next) => {
    try {
        configureServices(req);
        const roomId = req.colorClashInput.params.roomId;
        const room = await Room.findById(roomId).lean();
        if (!room) {
            throw createServiceError('ROOM_NOT_FOUND', 'Color Clash room not found', 404);
        }
        if (!isRoomAdmin(room, req.userId)) {
            throw createServiceError('ROOM_CANCEL_FORBIDDEN', 'Only room admins can cancel this Color Clash room', 403);
        }
        const result = await matchService.cancelRoom({
            roomId,
            reason: req.colorClashInput.body.reason
        });
        telemetry.warn('room_cancelled', {
            userId: req.userId,
            roomId,
            reason: req.colorClashInput.body.reason || null
        });
        res.json({
            success: true,
            roomId: result.roomId,
            lobby: result.lobby
        });
    } catch (error) {
        next(error);
    }
};

exports.getLobby = async (req, res, next) => {
    try {
        configureServices(req);
        const result = await matchService.getLobbySnapshot({
            roomId: req.colorClashInput.params.roomId,
            userId: req.userId
        });
        res.json(buildRoomPayload(result.room, result.lobby, result.viewerRole));
    } catch (error) {
        next(error);
    }
};

exports.getMatchSnapshot = async (req, res, next) => {
    try {
        configureServices(req);
        const snapshot = await snapshotService.getMatchSnapshot(
            req.colorClashInput.params.matchId,
            req.userId
        );
        telemetry.info('match_snapshot_fetched', {
            userId: req.userId,
            matchId: req.colorClashInput.params.matchId,
            viewerRole: snapshot.viewerRole,
            version: snapshot.version
        });
        res.json(snapshot);
    } catch (error) {
        next(error);
    }
};

exports.reconnectMatch = async (req, res, next) => {
    try {
        configureServices(req);
        const payload = await snapshotService.getReconnectPayload(
            req.colorClashInput.params.matchId,
            req.userId,
            req.colorClashInput.body.lastKnownVersion
        );
        telemetry.info('match_reconnect_requested', {
            userId: req.userId,
            matchId: req.colorClashInput.params.matchId,
            mode: payload.mode,
            lastKnownVersion: req.colorClashInput.body.lastKnownVersion
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.getSettlementSummary = async (req, res, next) => {
    try {
        configureServices(req);
        await matchService.authorizeMatchAccess(
            req.colorClashInput.params.matchId,
            req.userId
        );
        const summary = await settlementService.getSettlementSummary(
            req.colorClashInput.params.matchId
        );
        telemetry.info('settlement_summary_fetched', {
            userId: req.userId,
            matchId: req.colorClashInput.params.matchId,
            status: summary.status
        });
        res.json(summary);
    } catch (error) {
        next(error);
    }
};

exports.voteRematch = async (req, res, next) => {
    try {
        configureServices(req);
        const matchId = req.colorClashInput.params.matchId;
        const access = await matchService.authorizeMatchAccess(matchId, req.userId);
        const result = await matchService.voteRematch({
            roomId: access.room._id.toString(),
            userId: req.userId,
            vote: req.colorClashInput.body.vote
        });
        res.json(result);
    } catch (error) {
        next(error);
    }
};

exports.getCurrentSeason = async (req, res, next) => {
    try {
        configureServices(req);
        const summary = await seasonService.getSeasonSummaryForUser({
            userId: req.userId
        });
        summary.eligibility = await buildEligibilityPayload(await getCurrentUser(req), summary);
        res.json(summary);
    } catch (error) {
        next(error);
    }
};

exports.getLeaderboards = async (req, res, next) => {
    try {
        configureServices(req);
        const { period, limit, offset } = req.colorClashInput.query;
        const leaderboard = await seasonService.getLeaderboard({
            limit,
            offset,
            userId: req.userId
        });
        res.json({
            gameId: 'color_clash',
            period,
            season: leaderboard.season,
            rankings: leaderboard.rankings,
            userRank: leaderboard.userRank,
            limit: leaderboard.limit,
            offset: leaderboard.offset
        });
    } catch (error) {
        next(error);
    }
};

exports.equipTheme = async (req, res, next) => {
    try {
        const themeId = req.colorClashInput.params.themeId;
        if (!THEME_PACK_IDS.includes(themeId)) {
            throw createServiceError('INVALID_THEME', 'Unsupported Color Clash theme pack', 400);
        }

        const user = await User.findById(req.userId).select('settings').lean();
        if (!user) {
            throw createServiceError('USER_NOT_FOUND', 'User not found', 404);
        }

        const ownedThemePackIds = user.settings?.colorClash?.ownedThemePackIds || THEME_PACK_IDS;
        if (!ownedThemePackIds.includes(themeId)) {
            throw createServiceError('THEME_NOT_OWNED', 'This Color Clash theme is not unlocked yet', 403);
        }

        await User.findByIdAndUpdate(req.userId, {
            $set: {
                'settings.colorClash.equippedThemePackId': themeId
            }
        });

        res.json({
            equippedThemePackId: themeId
        });
    } catch (error) {
        next(error);
    }
};

exports.completeTutorial = async (req, res, next) => {
    try {
        const version = req.colorClashInput.body.version;
        await User.findByIdAndUpdate(req.userId, {
            $addToSet: {
                'settings.colorClash.tutorialCompletedVersions': version
            },
            $setOnInsert: {
                'settings.colorClash.equippedThemePackId': DEFAULT_THEME_PACK_ID
            }
        });

        res.json({
            completed: true,
            version
        });
    } catch (error) {
        next(error);
    }
};
