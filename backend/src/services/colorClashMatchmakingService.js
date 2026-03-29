const mongoose = require('mongoose');

const Room = require('../models/Room');
const User = require('../models/User');
const ColorClashMatch = require('../models/ColorClashMatch');
const matchService = require('./colorClashMatchService');
const settlementService = require('./colorClashSettlementService');
const seasonService = require('./colorClashSeasonService');
const {
    GAME_ID,
    DEFAULT_REGION,
    DEFAULT_THEME_PACK_ID,
    MATCHMAKING_MODES,
    RANKED_MIN_LEVEL,
    THEME_PACK_IDS
} = require('../utils/colorClashValidation');
const { createServiceError, toUserChannel } = require('./colorClashMatchService');

const QUEUE_TTL_SECONDS = 60 * 10;
const QUEUE_LOCK_TTL_MS = 5000;
const QUEUED_PLAYER_COUNT = 2;
const KEYS = Object.freeze({
    queue: (mode, stakeAmount, region) => `cc:mm:${mode}:${stakeAmount}:${region}`,
    ticket: (ticketId) => `cc:mm:ticket:${ticketId}`,
    user: (userId) => `cc:mm:user:${userId}`,
    queueLock: (mode, stakeAmount, region) => `cc:mm:lock:${mode}:${stakeAmount}:${region}`
});

const toIdString = (value) => {
    if (!value) return '';
    if (typeof value === 'string') return value;
    if (typeof value.toString === 'function') return value.toString();
    return String(value);
};

class ColorClashMatchmakingService {
    constructor({ redis = null, io = null, now = () => Date.now() } = {}) {
        this.redis = redis;
        this.io = io;
        this.now = now;
    }

    configure({ redis, io, now } = {}) {
        if (redis) this.redis = redis;
        if (io) this.io = io;
        if (now) this.now = now;
        matchService.configure({ redis: this.redis, io: this.io, now: this.now });
        settlementService.configure({ redis: this.redis, io: this.io, now: this.now });
        seasonService.configure({ redis: this.redis, now: this.now });
        return this;
    }

    requireRedis() {
        if (!this.redis) {
            throw createServiceError('REDIS_UNAVAILABLE', 'Color Clash matchmaking requires Redis', 503);
        }
        return this.redis;
    }

    normalizeRegion(region, fallback = DEFAULT_REGION) {
        const candidate = String(region || fallback || DEFAULT_REGION).trim();
        return candidate || DEFAULT_REGION;
    }

    async readJson(key, fallback = null) {
        const redis = this.requireRedis();
        const raw = await redis.get(key);
        if (!raw) return fallback;
        try {
            return JSON.parse(raw);
        } catch (_) {
            return fallback;
        }
    }

    async writeJson(key, value, ttlSeconds) {
        const redis = this.requireRedis();
        await redis.set(key, JSON.stringify(value), ttlSeconds ? { EX: ttlSeconds } : undefined);
    }

    async withLock(lockKey, ttlMs, work) {
        const redis = this.requireRedis();
        const token = `${this.now()}:${Math.random()}`;
        const acquired = await redis.set(lockKey, token, { NX: true, PX: ttlMs });
        if (!acquired) {
            throw createServiceError('LOCK_UNAVAILABLE', 'Another Color Clash queue action is in progress', 409);
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

    buildQueuePresets(user) {
        const isGuest = Boolean(user?.isGuest);
        const level = Number(user?.level || 1);
        const region = this.normalizeRegion(user?.region);
        const rankedLockReason = user?.settings?.colorClash?.rankedLock?.reason ||
            user?.settings?.colorClash?.rankedAccessLockReason ||
            '';
        const stakeLockReason = user?.settings?.colorClash?.stakeLock?.reason ||
            user?.settings?.colorClash?.stakeAccessLockReason ||
            '';
        const rankedLocked = Boolean(
            user?.settings?.colorClash?.rankedLock?.active ||
            user?.settings?.colorClash?.rankedAccessLocked
        );
        const stakeLocked = Boolean(
            user?.settings?.colorClash?.stakeLock?.active ||
            user?.settings?.colorClash?.stakeAccessLocked
        );
        const canUseRanked = !isGuest && level >= RANKED_MIN_LEVEL && !rankedLocked;
        const canUseGold = !isGuest && !stakeLocked;

        return [
            {
                queueId: `casual_free:${region}`,
                mode: 'casual_free',
                stakeAmount: 0,
                region,
                playerCount: QUEUED_PLAYER_COUNT,
                enabled: true,
                disabledReason: null,
                themePackId: DEFAULT_THEME_PACK_ID
            },
            {
                queueId: `gold_stake:50:${region}`,
                mode: 'gold_stake',
                stakeAmount: 50,
                region,
                playerCount: QUEUED_PLAYER_COUNT,
                enabled: canUseGold,
                disabledReason: canUseGold ? null : (stakeLocked
                    ? stakeLockReason || 'Stake Color Clash access is temporarily locked for this account.'
                    : 'Registered accounts are required for gold stake tables.'),
                themePackId: DEFAULT_THEME_PACK_ID
            },
            {
                queueId: `gold_stake:200:${region}`,
                mode: 'gold_stake',
                stakeAmount: 200,
                region,
                playerCount: QUEUED_PLAYER_COUNT,
                enabled: canUseGold,
                disabledReason: canUseGold ? null : (stakeLocked
                    ? stakeLockReason || 'Stake Color Clash access is temporarily locked for this account.'
                    : 'Registered accounts are required for gold stake tables.'),
                themePackId: 'neon_orbit'
            },
            {
                queueId: `ranked:${region}`,
                mode: 'ranked',
                stakeAmount: 0,
                region,
                playerCount: QUEUED_PLAYER_COUNT,
                enabled: canUseRanked,
                disabledReason: canUseRanked ? null : (rankedLocked
                    ? rankedLockReason || 'Ranked Color Clash access is temporarily locked for this account.'
                    : `Ranked queue unlocks for registered accounts at level ${RANKED_MIN_LEVEL}.`),
                themePackId: 'candy_carnival'
            }
        ];
    }

    async getExistingTicket(userId) {
        const redis = this.requireRedis();
        const ticketId = await redis.get(KEYS.user(userId));
        if (!ticketId) return null;
        const ticket = await this.readJson(KEYS.ticket(ticketId));
        if (!ticket) {
            await redis.del(KEYS.user(userId));
            return null;
        }
        return ticket;
    }

    async assertQueueEligibility(user, { mode, stakeAmount = 0 }) {
        if (!MATCHMAKING_MODES.includes(mode)) {
            throw createServiceError('INVALID_MODE', 'Unsupported Color Clash matchmaking mode', 400);
        }
        if (user.isGuest && (mode === 'gold_stake' || mode === 'ranked')) {
            throw createServiceError('ACCOUNT_UPGRADE_REQUIRED', 'Guests cannot enter stake or ranked Color Clash queues', 403);
        }
        if (mode === 'gold_stake') {
            await settlementService.precheckStakeEntry({
                user,
                entryFee: stakeAmount,
                currency: 'coins'
            });
        }
        if (mode === 'ranked') {
            await seasonService.assertRankedAccess({ user });
        }
    }

    buildStakeConfig({ entryFee = 0, payouts = null, houseFeeBps = null, sinkFeeBps = null } = {}) {
        return settlementService.normalizeStakeConfig({
            currency: Number(entryFee || 0) > 0 ? 'coins' : 'none',
            entryFee,
            payouts,
            houseFeeBps,
            sinkFeeBps
        });
    }

    serializeRoomSummary(room) {
        if (!room) return null;
        return {
            roomId: toIdString(room._id),
            displayId: room.roomId,
            name: room.name,
            description: room.description || '',
            host: room.hostId ? {
                userId: toIdString(room.hostId._id || room.hostId),
                username: room.hostId.username || 'Host',
                avatar: room.hostId.avatar || ''
            } : null,
            visibility: room.gameConfig?.visibility || 'private',
            tableMode: room.gameConfig?.tableMode || 'friend_room',
            seasonId: room.gameConfig?.seasonId ? toIdString(room.gameConfig.seasonId) : null,
            allowSpectators: room.gameConfig?.allowSpectators !== false,
            themePackId: room.gameConfig?.themePackId || DEFAULT_THEME_PACK_ID,
            maxPlayers: Number(room.gameConfig?.maxPlayers || 4),
            participantCount: Number(room.participantCount || room.participants?.length || 0),
            lobbyStatus: room.gameConfig?.lobbyStatus || 'open',
            activeMatchId: room.gameConfig?.activeMatchId ? toIdString(room.gameConfig.activeMatchId) : null,
            stake: {
                currency: room.gameConfig?.stake?.currency || 'none',
                entryFee: Number(room.gameConfig?.stake?.entryFee || 0),
                payouts: room.gameConfig?.stake?.payouts || [],
                houseFeeBps: Number(room.gameConfig?.stake?.houseFeeBps || 0),
                sinkFeeBps: Number(room.gameConfig?.stake?.sinkFeeBps || 0)
            },
            createdAt: room.createdAt,
            updatedAt: room.updatedAt
        };
    }

    serializeMatchSummary(match) {
        if (!match) return null;
        return {
            matchId: toIdString(match._id),
            roomId: toIdString(match.roomId),
            seasonId: match.seasonId ? toIdString(match.seasonId) : null,
            status: match.status,
            tableMode: match.tableMode,
            version: Number(match.version || 0),
            publicState: match.publicState || null,
            players: (match.players || []).map((player) => ({
                userId: toIdString(player.userId),
                seatIndex: player.seatIndex,
                username: player.usernameSnapshot || 'Guest',
                avatar: player.avatarSnapshot || '',
                status: player.status
            })),
            updatedAt: match.updatedAt,
            startedAt: match.startedAt
        };
    }

    async createFriendRoom({ user, payload, requestContext = {} }) {
        const visibility = payload.visibility || 'invite_only';
        const showInExplore = visibility === 'public';
        const maxPlayers = Number(payload.maxPlayers || 4);
        const minPlayersToStart = Math.min(
            maxPlayers,
            Math.max(2, Number(payload.minPlayersToStart || 2))
        );
        const stakeConfig = this.buildStakeConfig({
            entryFee: payload.stakeEntryFee,
            payouts: payload.stakePayouts,
            houseFeeBps: payload.houseFeeBps,
            sinkFeeBps: payload.sinkFeeBps
        });

        if (settlementService.requiresEscrow(stakeConfig)) {
            await settlementService.precheckStakeEntry({
                user,
                entryFee: stakeConfig.entryFee,
                currency: stakeConfig.currency
            });
        }

        const room = await Room.create({
            name: payload.name || 'Color Clash Room',
            description: payload.description || 'Original social card showdown',
            hostId: user._id,
            type: 'game',
            category: 'battle',
            showInExplore,
            settings: {
                isPrivate: visibility !== 'public',
                maxParticipants: Math.max(8, maxPlayers + 4),
                entryFee: 0,
                allowGifts: true
            },
            participants: [{
                userId: user._id,
                role: 'host',
                seatIndex: -1
            }],
            gameConfig: {
                gameId: GAME_ID,
                lobbyStatus: 'open',
                tableMode: payload.tableMode,
                visibility,
                allowSpectators: payload.allowSpectators,
                minPlayersToStart,
                maxPlayers,
                countdownSec: payload.countdownSec,
                turnTimeoutSec: payload.turnTimeoutSec,
                themePackId: payload.themePackId,
                rules: {
                    startingHandSize: 7,
                    timeoutStrikeLimit: 3,
                    customCards: payload.customCards || {}
                },
                stake: stakeConfig,
                invitedUserIds: payload.invitedUserIds || []
            }
        });

        await User.findByIdAndUpdate(user._id, {
            $set: {
                'status.currentRoom': room._id,
                'status.lastActive': new Date(this.now())
            }
        });

        const joined = await matchService.subscribeRoom({
            roomId: toIdString(room._id),
            userId: toIdString(user._id),
            profile: {
                username: user.username,
                avatar: user.avatar || ''
            },
            riskContext: {
                ...requestContext,
                region: user.region || this.normalizeRegion()
            }
        });

        return {
            room,
            lobby: joined.lobby,
            viewerRole: 'player'
        };
    }

    async joinFriendRoom({ roomId, user, spectator = false, requestContext = {} }) {
        const room = await matchService.getRoomById(roomId);
        await matchService.resolveRoomAccess(room, user._id, { spectatorRequested: spectator });

        const stakeConfig = settlementService.normalizeStakeConfig(room.gameConfig?.stake || {});
        if (!spectator && settlementService.requiresEscrow(stakeConfig)) {
            await settlementService.precheckStakeEntry({
                user,
                entryFee: stakeConfig.entryFee,
                currency: stakeConfig.currency
            });
        }

        if (!spectator && !matchService.isRoomMember(room, user._id)) {
            await Room.findByIdAndUpdate(roomId, {
                $push: {
                    participants: {
                        userId: user._id,
                        role: 'listener',
                        seatIndex: -1,
                        joinedAt: new Date(this.now()),
                        lastActive: new Date(this.now())
                    }
                }
            });
        }

        await User.findByIdAndUpdate(user._id, {
            $set: {
                'status.currentRoom': roomId,
                'status.lastActive': new Date(this.now())
            }
        });

        const joined = await matchService.subscribeRoom({
            roomId,
            userId: toIdString(user._id),
            profile: {
                username: user.username,
                avatar: user.avatar || ''
            },
            riskContext: {
                ...requestContext,
                region: user.region || this.normalizeRegion()
            }
        });

        return {
            room: await Room.findById(roomId).populate('hostId', 'username avatar').lean(),
            lobby: joined.lobby,
            viewerRole: spectator ? 'spectator' : joined.viewerRole
        };
    }

    async joinQueue({ user, payload, requestContext = {} }) {
        const redis = this.requireRedis();
        const mode = payload.mode;
        const stakeAmount = Number(payload.stakeAmount || 0);
        const region = this.normalizeRegion(payload.region, user.region);
        const themePackId = payload.themePackId || DEFAULT_THEME_PACK_ID;

        await this.assertQueueEligibility(user, { mode, stakeAmount });
        const existingTicket = await this.getExistingTicket(user._id);
        if (existingTicket) {
            const sameQueue = existingTicket.mode === mode &&
                Number(existingTicket.stakeAmount || 0) === stakeAmount &&
                existingTicket.region === region;
            if (sameQueue) {
                return {
                    status: 'queued',
                    duplicate: true,
                    queueTicketId: existingTicket.ticketId,
                    estimatedWaitMs: null
                };
            }
            throw createServiceError('QUEUE_ALREADY_ACTIVE', 'User is already queued for another Color Clash table', 409);
        }

        const ticketId = new mongoose.Types.ObjectId().toString();
        const ticket = {
            ticketId,
            userId: toIdString(user._id),
            username: user.username,
            avatar: user.avatar || '',
            region,
            mode,
            stakeAmount,
            playerCount: QUEUED_PLAYER_COUNT,
            themePackId: THEME_PACK_IDS.includes(themePackId) ? themePackId : DEFAULT_THEME_PACK_ID,
            queuedAtMs: this.now(),
            ipHash: requestContext.ipHash || null,
            deviceHash: requestContext.deviceHash || user.settings?.colorClash?.deviceHash || null
        };
        const queueKey = KEYS.queue(mode, stakeAmount, region);

        await this.writeJson(KEYS.ticket(ticketId), ticket, QUEUE_TTL_SECONDS);
        await redis.set(KEYS.user(user._id), ticketId, { EX: QUEUE_TTL_SECONDS });
        await redis.zAdd(queueKey, [{ score: ticket.queuedAtMs, value: ticketId }]);
        await redis.expire(queueKey, QUEUE_TTL_SECONDS);

        const matched = await this.attemptMatch({
            mode,
            stakeAmount,
            region,
            requestingUserId: toIdString(user._id)
        });

        if (matched && matched.players.some((entry) => toIdString(entry.userId) === toIdString(user._id))) {
            return {
                status: 'matched',
                duplicate: false,
                queueTicketId: ticketId,
                room: matched.room,
                match: matched.match
            };
        }

        return {
            status: 'queued',
            duplicate: false,
            queueTicketId: ticketId,
            estimatedWaitMs: null
        };
    }

    async leaveQueue({ userId, queueTicketId = null }) {
        const redis = this.requireRedis();
        const ticket = await this.getExistingTicket(userId);
        if (!ticket) {
            return {
                success: true,
                removed: false,
                queueTicketId: null
            };
        }

        if (queueTicketId && ticket.ticketId !== queueTicketId) {
            throw createServiceError('QUEUE_TICKET_NOT_FOUND', 'Requested queue ticket was not found for this user', 404);
        }

        await redis.zRem(KEYS.queue(ticket.mode, Number(ticket.stakeAmount || 0), ticket.region), ticket.ticketId);
        await redis.del(KEYS.ticket(ticket.ticketId), KEYS.user(userId));

        return {
            success: true,
            removed: true,
            queueTicketId: ticket.ticketId
        };
    }

    async attemptMatch({ mode, stakeAmount, region, requestingUserId = null }) {
        const redis = this.requireRedis();
        return this.withLock(KEYS.queueLock(mode, stakeAmount, region), QUEUE_LOCK_TTL_MS, async () => {
            const queueKey = KEYS.queue(mode, stakeAmount, region);
            const candidateTicketIds = await redis.zRange(queueKey, 0, QUEUED_PLAYER_COUNT - 1);
            if (candidateTicketIds.length < QUEUED_PLAYER_COUNT) {
                return null;
            }

            const tickets = [];
            for (const ticketId of candidateTicketIds) {
                const ticket = await this.readJson(KEYS.ticket(ticketId));
                if (!ticket) {
                    await redis.zRem(queueKey, ticketId);
                    continue;
                }
                tickets.push(ticket);
            }

            if (tickets.length < QUEUED_PLAYER_COUNT) {
                return null;
            }

            const users = await User.find({
                _id: {
                    $in: tickets.map((ticket) => ticket.userId)
                }
            }).select('username avatar region level coins isGuest settings').lean();
            const userMap = new Map(users.map((entry) => [toIdString(entry._id), entry]));

            if (users.length < QUEUED_PLAYER_COUNT) {
                for (const ticket of tickets) {
                    if (!userMap.has(ticket.userId)) {
                        await redis.zRem(queueKey, ticket.ticketId);
                        await redis.del(KEYS.ticket(ticket.ticketId), KEYS.user(ticket.userId));
                    }
                }
                return null;
            }

            for (const ticket of tickets) {
                await this.assertQueueEligibility(userMap.get(ticket.userId), {
                    mode: ticket.mode,
                    stakeAmount: ticket.stakeAmount
                });
            }

            const hostTicket = tickets[0];
            const rankedSeason = mode === 'ranked'
                ? await seasonService.getCurrentSeason({ allowProvision: true })
                : null;
            const stakeConfig = this.buildStakeConfig({
                entryFee: stakeAmount
            });
            const room = await Room.create({
                name: `Color Clash ${mode === 'casual_free' ? 'Table' : mode === 'gold_stake' ? 'Stake Table' : 'Ranked Table'}`,
                description: 'Realtime Color Clash table',
                hostId: hostTicket.userId,
                type: 'game',
                category: 'battle',
                showInExplore: false,
                settings: {
                    isPrivate: true,
                    maxParticipants: 12,
                    entryFee: 0,
                    allowGifts: true
                },
                participants: tickets.map((ticket, index) => ({
                    userId: ticket.userId,
                    role: index === 0 ? 'host' : 'listener',
                    seatIndex: -1,
                    joinedAt: new Date(this.now()),
                    lastActive: new Date(this.now())
                })),
                gameConfig: {
                    gameId: GAME_ID,
                    lobbyStatus: 'open',
                    tableMode: mode,
                    seasonId: rankedSeason?._id || null,
                    visibility: 'private',
                    allowSpectators: false,
                    minPlayersToStart: QUEUED_PLAYER_COUNT,
                    maxPlayers: QUEUED_PLAYER_COUNT,
                    countdownSec: 3,
                    turnTimeoutSec: 25,
                    themePackId: hostTicket.themePackId || DEFAULT_THEME_PACK_ID,
                    rules: {
                        startingHandSize: 7,
                        timeoutStrikeLimit: 3,
                        customCards: {}
                    },
                    stake: stakeConfig
                }
            });

            let lobby = matchService.buildLobbyFromRoom(room);
            for (let index = 0; index < tickets.length; index += 1) {
                const ticket = tickets[index];
                const user = userMap.get(ticket.userId);
                lobby.playersByUserId[ticket.userId] = {
                    userId: ticket.userId,
                    username: user.username,
                    avatar: user.avatar || '',
                    seatIndex: index,
                    ready: true,
                    role: 'player',
                    joinedAtMs: this.now(),
                    lastSeenAtMs: this.now(),
                    ipHash: ticket.ipHash || null,
                    deviceHash: ticket.deviceHash || null,
                    region: ticket.region || ''
                };
                lobby.seats[String(index)] = ticket.userId;
            }
            lobby.lobbyVersion += tickets.length;
            lobby = await matchService.saveLobbyState(toIdString(room._id), lobby);
            await matchService.emitLobbyState(toIdString(room._id), lobby);

            await User.updateMany({
                _id: {
                    $in: tickets.map((ticket) => ticket.userId)
                }
            }, {
                $set: {
                    'status.currentRoom': room._id,
                    'status.lastActive': new Date(this.now())
                }
            });

            let createdMatch;
            try {
                createdMatch = await matchService.createMatchFromLobby({
                    roomId: toIdString(room._id),
                    lobby
                });
            } catch (error) {
                const failedUserId = toIdString(error.failedUserId);
                if (failedUserId) {
                    const failedTicket = tickets.find((ticket) => ticket.userId === failedUserId);
                    if (failedTicket) {
                        await redis.zRem(queueKey, failedTicket.ticketId);
                        await redis.del(KEYS.ticket(failedTicket.ticketId), KEYS.user(failedTicket.userId));
                    }
                }

                await Room.findByIdAndUpdate(room._id, {
                    $set: {
                        'gameConfig.lobbyStatus': 'cancelled',
                        showInExplore: false,
                        endedAt: new Date(this.now())
                    }
                });

                if (failedUserId && failedUserId === toIdString(requestingUserId)) {
                    throw error;
                }
                return null;
            }

            for (const ticket of tickets) {
                await redis.zRem(queueKey, ticket.ticketId);
                await redis.del(KEYS.ticket(ticket.ticketId), KEYS.user(ticket.userId));
                if (this.io) {
                    this.io.to(toUserChannel(ticket.userId)).emit('cc:queue:matched', {
                        roomId: toIdString(room._id),
                        matchId: createdMatch.matchId,
                        mode,
                        stakeAmount
                    });
                }
            }

            const hydratedRoom = await Room.findById(room._id).populate('hostId', 'username avatar').lean();
            return {
                room: this.serializeRoomSummary(hydratedRoom),
                match: {
                    matchId: createdMatch.matchId,
                    roomId: createdMatch.roomId,
                    roundId: createdMatch.roundId,
                    version: createdMatch.version
                },
                players: tickets.map((ticket) => ({
                    userId: ticket.userId,
                    username: ticket.username,
                    avatar: ticket.avatar || ''
                }))
            };
        });
    }

    async listVisibleRooms({ mode = null, limit = 20 } = {}) {
        const query = {
            type: 'game',
            'gameConfig.gameId': GAME_ID,
            endedAt: null,
            showInExplore: true,
            'gameConfig.visibility': 'public'
        };
        if (mode) {
            query['gameConfig.tableMode'] = mode;
        }

        const rooms = await Room.find(query)
            .populate('hostId', 'username avatar')
            .sort({ updatedAt: -1, createdAt: -1 })
            .limit(limit)
            .lean();

        return rooms.map((room) => this.serializeRoomSummary(room));
    }

    async getHome({ user }) {
        const [activeMatch, queueTicket, rooms] = await Promise.all([
            ColorClashMatch.findOne({
                'players.userId': user._id,
                status: { $in: ['pending', 'countdown', 'dealing', 'active', 'round_end'] }
            }).sort({ updatedAt: -1 }).lean(),
            this.getExistingTicket(user._id),
            Room.find({
                type: 'game',
                'gameConfig.gameId': GAME_ID,
                endedAt: null,
                $or: [
                    { hostId: user._id },
                    { 'participants.userId': user._id },
                    { showInExplore: true, 'gameConfig.visibility': 'public' }
                ]
            })
                .populate('hostId', 'username avatar')
                .sort({ updatedAt: -1, createdAt: -1 })
                .limit(6)
                .lean()
        ]);

        return {
            gameId: GAME_ID,
            season: null,
            userProgress: {
                stats: user.gameStats?.colorClash || {},
                activeQueueTicketId: queueTicket?.ticketId || null
            },
            queuePresets: this.buildQueuePresets(user),
            rooms: rooms.map((room) => this.serializeRoomSummary(room)),
            activeMatch: this.serializeMatchSummary(activeMatch),
            themes: {
                equippedThemePackId: user.settings?.colorClash?.equippedThemePackId || DEFAULT_THEME_PACK_ID,
                ownedThemePackIds: user.settings?.colorClash?.ownedThemePackIds || THEME_PACK_IDS
            },
            tutorial: {
                completedVersions: user.settings?.colorClash?.tutorialCompletedVersions || []
            }
        };
    }

    async getTables({ user, query }) {
        const rooms = await this.listVisibleRooms({
            mode: query.mode || null,
            limit: query.limit || 20
        });

        return {
            gameId: GAME_ID,
            queuePresets: this.buildQueuePresets(user),
            rooms
        };
    }
}

const matchmakingService = new ColorClashMatchmakingService();

module.exports = matchmakingService;
module.exports.ColorClashMatchmakingService = ColorClashMatchmakingService;
module.exports.KEYS = KEYS;
