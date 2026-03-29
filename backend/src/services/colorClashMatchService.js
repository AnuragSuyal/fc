const mongoose = require('mongoose');

const Room = require('../models/Room');
const User = require('../models/User');
const ColorClashMatch = require('../models/ColorClashMatch');
const ColorClashRound = require('../models/ColorClashRound');
const ColorClashMove = require('../models/ColorClashMove');
const antiFraudService = require('./colorClashAntiFraudService');
const settlementService = require('./colorClashSettlementService');
const seasonService = require('./colorClashSeasonService');
const telemetry = require('./colorClashTelemetry');
const {
    MOVE_TYPES,
    createInitialState,
    applyMove,
    autoActionOnTimeout,
    serializePublicState,
    serializePrivateState
} = require('./colorClashRulesEngine');

const LOBBY_TTL_SECONDS = 60 * 60 * 2;
const MATCH_TTL_SECONDS = 60 * 60 * 6;
const SNAPSHOT_TTL_SECONDS = 60 * 60 * 2;
const PRESENCE_TTL_SECONDS = 120;
const MOVE_TTL_SECONDS = 60 * 60 * 24;
const ROOM_LOCK_TTL_MS = 5000;
const MATCH_LOCK_TTL_MS = 5000;
const REPLAY_LIMIT = 200;
const REPLAY_MAX_GAP = 25;

const KEYS = Object.freeze({
    lobby: (roomId) => `cc:room:${roomId}:lobby`,
    matchState: (matchId) => `cc:match:${matchId}:state`,
    hand: (matchId, userId) => `cc:match:${matchId}:hand:${userId}`,
    draw: (matchId) => `cc:match:${matchId}:draw`,
    discard: (matchId) => `cc:match:${matchId}:discard`,
    timer: (matchId) => `cc:match:${matchId}:timer`,
    replay: (matchId) => `cc:match:${matchId}:replay`,
    snapshot: (matchId, userId) => `cc:match:${matchId}:snapshot:${userId}`,
    playersPresence: (matchId) => `cc:presence:match:${matchId}:players`,
    spectatorsPresence: (matchId) => `cc:presence:match:${matchId}:spectators`,
    move: (matchId, userId, clientMoveId) => `cc:move:${matchId}:${userId}:${clientMoveId}`,
    roomLock: (roomId) => `cc:lock:room:${roomId}`,
    matchLock: (matchId) => `cc:lock:match:${matchId}`
});

const toRoomChannel = (roomId) => `cc:room:${roomId}`;
const toMatchChannel = (matchId) => `cc:match:${matchId}`;
const toUserChannel = (userId) => `cc:user:${userId}`;

const jsonClone = (value) => JSON.parse(JSON.stringify(value));

const safeParseJson = (value, fallback = null) => {
    if (!value) return fallback;
    try {
        return JSON.parse(value);
    } catch (_) {
        return fallback;
    }
};

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

class ColorClashMatchService {
    constructor({
        redis = null,
        io = null,
        now = () => Date.now()
    } = {}) {
        this.redis = redis;
        this.io = io;
        this.now = now;
        this.countdownTimers = new Map();
        this.turnTimers = new Map();
        this.replayLimit = REPLAY_LIMIT;
        this.replayMaxGap = REPLAY_MAX_GAP;
    }

    configure({ redis, io, now } = {}) {
        if (redis) this.redis = redis;
        if (io) this.io = io;
        if (now) this.now = now;
        antiFraudService.configure({ now: this.now });
        settlementService.configure({ redis: this.redis, io: this.io, now: this.now });
        seasonService.configure({ redis: this.redis, now: this.now });
        return this;
    }

    requireRedis() {
        if (!this.redis) {
            throw createServiceError('REDIS_UNAVAILABLE', 'Color Clash runtime requires Redis', 503);
        }
        return this.redis;
    }

    async readJson(key, fallback = null) {
        const redis = this.requireRedis();
        const raw = await redis.get(key);
        return safeParseJson(raw, fallback);
    }

    async writeJson(key, value, ttlSeconds) {
        const redis = this.requireRedis();
        await redis.set(
            key,
            JSON.stringify(value),
            ttlSeconds ? { EX: ttlSeconds } : undefined
        );
    }

    async deleteKeys(keys = []) {
        const redis = this.requireRedis();
        const validKeys = keys.filter(Boolean);
        if (!validKeys.length) return;
        await redis.del(validKeys);
    }

    async withLock(lockKey, ttlMs, work) {
        const redis = this.requireRedis();
        const token = `${this.now()}:${Math.random()}`;
        const acquired = await redis.set(lockKey, token, { NX: true, PX: ttlMs });
        if (!acquired) {
            throw createServiceError('LOCK_UNAVAILABLE', 'Another game action is in progress', 409);
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

    buildLobbyFromRoom(room) {
        const roomId = toIdString(room._id);
        const gameConfig = room.gameConfig || {};
        return {
            roomId,
            gameId: 'color_clash',
            lobbyVersion: 1,
            status: gameConfig.lobbyStatus || 'open',
            activeMatchId: gameConfig.activeMatchId ? toIdString(gameConfig.activeMatchId) : null,
            minPlayersToStart: Number(gameConfig.minPlayersToStart || 2),
            maxPlayers: Number(gameConfig.maxPlayers || 4),
            countdownSec: Number(gameConfig.countdownSec || 6),
            allowSpectators: gameConfig.allowSpectators !== false,
            seats: {},
            playersByUserId: {},
            countdownEndsAt: null,
            updatedAtMs: this.now()
        };
    }

    async getRoomById(roomId) {
        const room = await Room.findById(roomId)
            .populate('hostId', 'username avatar')
            .lean();
        if (!room) {
            throw createServiceError('ROOM_NOT_FOUND', 'Game room not found', 404);
        }
        if (room.type !== 'game') {
            throw createServiceError('INVALID_ROOM_TYPE', 'Color Clash requires a game room', 400);
        }
        if (room.gameConfig?.gameId && room.gameConfig.gameId !== 'color_clash') {
            throw createServiceError('INVALID_GAME_ROOM', 'Room is not configured for Color Clash', 400);
        }
        return room;
    }

    isRoomMember(room, userId) {
        const userIdString = toIdString(userId);
        return toIdString(room.hostId?._id || room.hostId) === userIdString ||
            (room.participants || []).some((entry) => toIdString(entry.userId?._id || entry.userId) === userIdString) ||
            (room.coHosts || []).some((entry) => toIdString(entry) === userIdString) ||
            (room.moderators || []).some((entry) => toIdString(entry) === userIdString);
    }

    isInvitedToRoom(room, userId) {
        const userIdString = toIdString(userId);
        return (room.gameConfig?.invitedUserIds || []).some((entry) => toIdString(entry) === userIdString);
    }

    async resolveRoomAccess(room, userId, { spectatorRequested = false } = {}) {
        const userIdString = toIdString(userId);
        const visibility = room.gameConfig?.visibility || (room.settings?.isPrivate ? 'private' : 'public');
        const allowSpectators = room.gameConfig?.allowSpectators !== false;
        const isMember = this.isRoomMember(room, userIdString);

        if (isMember) {
            return {
                allowed: true,
                viewerRole: spectatorRequested ? 'spectator' : 'player',
                visibility,
                allowSpectators,
                isMember
            };
        }

        if (spectatorRequested && !allowSpectators) {
            throw createServiceError('SPECTATORS_DISABLED', 'Spectators are not allowed for this room', 403);
        }

        const [viewer, host] = await Promise.all([
            User.findById(userIdString).select('friends blockedUsers').lean(),
            User.findById(room.hostId?._id || room.hostId).select('friends blockedUsers').lean()
        ]);

        const blockedByViewer = (viewer?.blockedUsers || []).some((entry) => toIdString(entry) === toIdString(room.hostId?._id || room.hostId));
        const blockedByHost = (host?.blockedUsers || []).some((entry) => toIdString(entry) === userIdString);
        if (blockedByViewer || blockedByHost) {
            throw createServiceError('ROOM_ACCESS_BLOCKED', 'You cannot access this Color Clash room', 403);
        }

        const invited = this.isInvitedToRoom(room, userIdString);
        const hostFriend = (host?.friends || []).some((entry) => toIdString(entry) === userIdString);

        let allowed = false;
        if (visibility === 'public') {
            allowed = true;
        } else if (visibility === 'private') {
            allowed = invited || hostFriend;
        } else if (visibility === 'invite_only') {
            allowed = invited;
        }

        if (!allowed) {
            throw createServiceError('ROOM_ACCESS_DENIED', 'You do not have access to this Color Clash room', 403);
        }

        return {
            allowed: true,
            viewerRole: spectatorRequested ? 'spectator' : 'player',
            visibility,
            allowSpectators,
            isMember: false
        };
    }

    async getOrCreateLobby(roomId) {
        const redis = this.requireRedis();
        const existing = await this.readJson(KEYS.lobby(roomId));
        if (existing) {
            return existing;
        }

        const room = await this.getRoomById(roomId);
        const lobby = this.buildLobbyFromRoom(room);
        await this.writeJson(KEYS.lobby(roomId), lobby, LOBBY_TTL_SECONDS);
        return lobby;
    }

    async saveLobbyState(roomId, lobbyState) {
        const nextLobbyState = {
            ...lobbyState,
            updatedAtMs: this.now()
        };
        await this.writeJson(KEYS.lobby(roomId), nextLobbyState, LOBBY_TTL_SECONDS);
        return nextLobbyState;
    }

    applyRiskContext(entry, riskContext = {}) {
        if (!entry || !riskContext) return entry;
        if (riskContext.ipHash) entry.ipHash = riskContext.ipHash;
        if (riskContext.deviceHash) entry.deviceHash = riskContext.deviceHash;
        if (riskContext.region) entry.region = riskContext.region;
        return entry;
    }

    sanitizeLobbyForClient(lobbyState) {
        if (!lobbyState) return lobbyState;
        const playersByUserId = {};
        for (const [userId, entry] of Object.entries(lobbyState.playersByUserId || {})) {
            playersByUserId[userId] = {
                ...entry
            };
            delete playersByUserId[userId].ipHash;
            delete playersByUserId[userId].deviceHash;
        }

        return {
            ...lobbyState,
            playersByUserId
        };
    }

    hydrateEngineState(matchEnvelope, handsBySeat, drawPile, discardPile) {
        return {
            gameId: matchEnvelope.gameId,
            phase: matchEnvelope.phase,
            roundNumber: matchEnvelope.roundNumber,
            shuffleSeed: matchEnvelope.shuffleSeed,
            versionSeed: matchEnvelope.versionSeed,
            rulesConfig: matchEnvelope.rulesConfig,
            deckDefinition: matchEnvelope.deckDefinition,
            players: jsonClone(matchEnvelope.players),
            handsBySeat,
            drawPile,
            discardPile,
            discardTop: discardPile[discardPile.length - 1] || null,
            currentTurnSeat: matchEnvelope.currentTurnSeat,
            direction: matchEnvelope.direction,
            currentHue: matchEnvelope.currentHue,
            pendingEffect: jsonClone(matchEnvelope.pendingEffect),
            turnContext: jsonClone(matchEnvelope.turnContext),
            roundResult: jsonClone(matchEnvelope.roundResult)
        };
    }

    buildMatchEnvelope({ matchDoc, roundDoc, room, engineState, version }) {
        return {
            matchId: toIdString(matchDoc._id),
            roomId: toIdString(room._id || room),
            roundId: toIdString(roundDoc?._id || roundDoc),
            gameId: 'color_clash',
            status: engineState.phase === 'completed' ? 'completed' : 'active',
            tableMode: matchDoc.tableMode,
            roundNumber: engineState.roundNumber,
            version,
            shuffleSeed: engineState.shuffleSeed,
            versionSeed: engineState.versionSeed,
            rulesConfig: jsonClone(engineState.rulesConfig),
            deckDefinition: jsonClone(engineState.deckDefinition),
            players: jsonClone(engineState.players),
            currentTurnSeat: engineState.currentTurnSeat,
            direction: engineState.direction,
            currentHue: engineState.currentHue,
            pendingEffect: jsonClone(engineState.pendingEffect),
            turnContext: jsonClone(engineState.turnContext),
            phase: engineState.phase,
            roundResult: jsonClone(engineState.roundResult),
            configSnapshot: jsonClone(matchDoc.configSnapshot || {})
        };
    }

    async writeActiveMatchState({ matchEnvelope, engineState }) {
        const matchId = matchEnvelope.matchId;
        await this.writeJson(KEYS.matchState(matchId), matchEnvelope, MATCH_TTL_SECONDS);
        await this.writeJson(KEYS.draw(matchId), engineState.drawPile, MATCH_TTL_SECONDS);
        await this.writeJson(KEYS.discard(matchId), engineState.discardPile, MATCH_TTL_SECONDS);

        for (const player of matchEnvelope.players) {
            const userId = toIdString(player.userId);
            const hand = engineState.handsBySeat[String(player.seatIndex)] || [];
            await this.writeJson(KEYS.hand(matchId, userId), hand, MATCH_TTL_SECONDS);
        }
    }

    async loadActiveMatchState(matchId) {
        const matchEnvelope = await this.readJson(KEYS.matchState(matchId));
        if (!matchEnvelope) {
            throw createServiceError('MATCH_NOT_FOUND', 'Match runtime not found', 404);
        }

        const drawPile = await this.readJson(KEYS.draw(matchId), []);
        const discardPile = await this.readJson(KEYS.discard(matchId), []);
        const handsBySeat = {};
        for (const player of matchEnvelope.players || []) {
            const userId = toIdString(player.userId);
            handsBySeat[String(player.seatIndex)] = await this.readJson(KEYS.hand(matchId, userId), []);
        }

        return {
            matchEnvelope,
            engineState: this.hydrateEngineState(matchEnvelope, handsBySeat, drawPile, discardPile)
        };
    }

    async appendReplayEvent(matchId, replayEvent) {
        const redis = this.requireRedis();
        const key = KEYS.replay(matchId);
        await redis.rPush(key, JSON.stringify(replayEvent));
        await redis.lTrim(key, -this.replayLimit, -1);
        await redis.expire(key, MATCH_TTL_SECONDS);
    }

    async getReplaySinceVersion(matchId, version) {
        const redis = this.requireRedis();
        const entries = await redis.lRange(KEYS.replay(matchId), 0, -1);
        const parsed = entries
            .map((entry) => safeParseJson(entry))
            .filter(Boolean)
            .filter((entry) => Number(entry.version) > Number(version || 0))
            .sort((left, right) => Number(left.version) - Number(right.version));

        if (parsed.length > this.replayMaxGap) {
            return {
                snapshotRequired: true,
                replay: []
            };
        }

        return {
            snapshotRequired: false,
            replay: parsed
        };
    }

    async touchMatchPresence(matchId, userId, role) {
        const redis = this.requireRedis();
        const key = role === 'spectator'
            ? KEYS.spectatorsPresence(matchId)
            : KEYS.playersPresence(matchId);
        await redis.sAdd(key, toIdString(userId));
        await redis.expire(key, PRESENCE_TTL_SECONDS);
    }

    async readPresenceCounts(matchId) {
        const redis = this.requireRedis();
        const players = await redis.sCard(KEYS.playersPresence(matchId));
        const spectators = await redis.sCard(KEYS.spectatorsPresence(matchId));
        return { players, spectators };
    }

    emit(eventName, target, payload) {
        if (!this.io) return;
        this.io.to(target).emit(eventName, payload);
    }

    async emitLobbyState(roomId, lobbyState) {
        const safeLobby = this.sanitizeLobbyForClient(lobbyState);
        this.emit('cc:room:lobby_state', toRoomChannel(roomId), {
            roomId,
            lobbyVersion: safeLobby.lobbyVersion,
            status: safeLobby.status,
            seats: safeLobby.seats,
            playersByUserId: safeLobby.playersByUserId,
            countdownEndsAt: safeLobby.countdownEndsAt,
            activeMatchId: safeLobby.activeMatchId
        });
    }

    async persistMatchProjection(matchId, engineState, version, statusOverride = null) {
        const publicState = serializePublicState({ state: engineState });
        const status = statusOverride || (engineState.phase === 'completed' ? 'completed' : 'active');
        const patch = {
            version,
            publicState,
            status,
            roundResult: engineState.roundResult || null,
            updatedAt: new Date(this.now())
        };
        if (status === 'completed') {
            patch.endedAt = new Date(this.now());
        }
        await ColorClashMatch.findByIdAndUpdate(matchId, patch);
        return publicState;
    }

    async persistRoundProjection(roundId, engineState) {
        const update = {
            publicEndState: engineState.phase === 'completed'
                ? serializePublicState({ state: engineState })
                : null,
            status: engineState.phase === 'completed' ? 'ended' : 'active',
            updatedAt: new Date(this.now())
        };
        if (engineState.phase === 'completed') {
            update.endedAt = new Date(this.now());
        }
        await ColorClashRound.findByIdAndUpdate(roundId, update);
    }

    async writeReconnectSnapshots(matchEnvelope, engineState) {
        const timerPayload = this.buildTurnTimerPayload(matchEnvelope);
        for (const player of matchEnvelope.players) {
            const userId = toIdString(player.userId);
            const snapshot = {
                matchId: matchEnvelope.matchId,
                roomId: matchEnvelope.roomId,
                version: matchEnvelope.version,
                viewerRole: 'player',
                publicState: this.buildClientPublicState(
                    matchEnvelope,
                    engineState,
                    timerPayload
                ),
                privateState: serializePrivateState({ state: engineState, seatIndex: player.seatIndex })
            };
            await this.writeJson(KEYS.snapshot(matchEnvelope.matchId, userId), snapshot, SNAPSHOT_TTL_SECONDS);
        }
    }

    buildPublicPatchPayload(matchEnvelope, engineState, rulesEvents, actorSeat = null) {
        const timerPayload = this.buildTurnTimerPayload(matchEnvelope);
        return {
            matchId: matchEnvelope.matchId,
            roomId: matchEnvelope.roomId,
            version: matchEnvelope.version,
            actorSeat,
            publicState: this.buildClientPublicState(
                matchEnvelope,
                engineState,
                timerPayload
            ),
            events: jsonClone(rulesEvents || [])
        };
    }

    buildTurnTimerPayload(matchEnvelope) {
        if (!matchEnvelope || matchEnvelope.phase === 'completed' || matchEnvelope.status === 'completed') {
            return null;
        }

        const timeoutSec = Number(
            matchEnvelope.configSnapshot?.roomGameConfig?.turnTimeoutSec ||
            matchEnvelope.configSnapshot?.roomSettings?.turnTimeoutSec ||
            25
        );
        const turnEndsAt = this.now() + (timeoutSec * 1000);
        return {
            matchId: matchEnvelope.matchId,
            version: matchEnvelope.version,
            seatIndex: matchEnvelope.currentTurnSeat,
            turnEndsAt,
            graceEndsAt: turnEndsAt + 5000
        };
    }

    buildClientPublicState(matchEnvelope, engineState, timerPayload = null) {
        const publicState = serializePublicState({ state: engineState });
        const turnContext = {
            ...(publicState.turnContext || {})
        };

        if (timerPayload && timerPayload.seatIndex === publicState.currentTurnSeat) {
            turnContext.turnEndsAt = Number(timerPayload.turnEndsAt);
            turnContext.graceEndsAt = Number(timerPayload.graceEndsAt);
        }

        return {
            ...publicState,
            turnContext
        };
    }

    async subscribeRoom({ roomId, userId, profile = {}, riskContext = {} }) {
        const room = await this.getRoomById(roomId);
        const lobby = await this.getOrCreateLobby(roomId);
        const userIdString = toIdString(userId);
        let lobbyChanged = false;
        const access = await this.resolveRoomAccess(room, userId, {
            spectatorRequested: !this.isRoomMember(room, userIdString)
        });
        const isParticipant = access.viewerRole === 'player';

        if (!lobby.playersByUserId[userIdString]) {
            lobby.playersByUserId[userIdString] = {
                userId: userIdString,
                username: profile.username || room.participants?.find((entry) =>
                    toIdString(entry.userId?._id || entry.userId) === userIdString
                )?.userId?.username || room.hostId?.username || 'Guest',
                avatar: profile.avatar || room.participants?.find((entry) =>
                    toIdString(entry.userId?._id || entry.userId) === userIdString
                )?.userId?.avatar || room.hostId?.avatar || '',
                seatIndex: null,
                ready: false,
                role: isParticipant ? 'player' : 'spectator',
                joinedAtMs: this.now(),
                lastSeenAtMs: this.now()
            };
            this.applyRiskContext(lobby.playersByUserId[userIdString], riskContext);
            lobby.lobbyVersion += 1;
            lobbyChanged = true;
        } else {
            lobby.playersByUserId[userIdString].lastSeenAtMs = this.now();
            this.applyRiskContext(lobby.playersByUserId[userIdString], riskContext);
        }

        const savedLobby = await this.saveLobbyState(roomId, lobby);
        if (lobbyChanged) {
            await this.emitLobbyState(roomId, savedLobby);
        }
        return {
            room,
            lobby: savedLobby,
            viewerRole: savedLobby.playersByUserId[userIdString]?.role || 'spectator'
        };
    }

    async getLobbySnapshot({ roomId, userId }) {
        const room = await this.getRoomById(roomId);
        const lobby = await this.getOrCreateLobby(roomId);
        const knownEntry = lobby.playersByUserId?.[toIdString(userId)];
        const access = await this.resolveRoomAccess(room, userId, {
            spectatorRequested: !knownEntry && !this.isRoomMember(room, userId)
        });

        return {
            room,
            lobby,
            viewerRole: knownEntry?.role || access.viewerRole
        };
    }

    async claimSeat({ roomId, userId, seatIndex, profile = {}, riskContext = {} }) {
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            const lobby = await this.getOrCreateLobby(roomId);
            const userIdString = toIdString(userId);
            if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex >= lobby.maxPlayers) {
                throw createServiceError('INVALID_SEAT', 'Seat index is invalid', 422);
            }

            for (const [seatKey, occupantUserId] of Object.entries(lobby.seats || {})) {
                if (Number(seatKey) === seatIndex && occupantUserId && occupantUserId !== userIdString) {
                    throw createServiceError('SEAT_TAKEN', 'Seat is already taken', 409);
                }
            }

            if (!lobby.playersByUserId[userIdString]) {
                lobby.playersByUserId[userIdString] = {
                    userId: userIdString,
                    username: profile.username || 'Guest',
                    avatar: profile.avatar || '',
                    seatIndex: null,
                    ready: false,
                    role: 'player',
                    joinedAtMs: this.now(),
                    lastSeenAtMs: this.now()
                };
            }
            this.applyRiskContext(lobby.playersByUserId[userIdString], riskContext);

            const previousSeat = lobby.playersByUserId[userIdString].seatIndex;
            if (previousSeat !== null && previousSeat !== undefined) {
                delete lobby.seats[String(previousSeat)];
            }

            lobby.playersByUserId[userIdString].seatIndex = seatIndex;
            lobby.playersByUserId[userIdString].role = 'player';
            lobby.playersByUserId[userIdString].lastSeenAtMs = this.now();
            lobby.playersByUserId[userIdString].ready = false;
            lobby.seats[String(seatIndex)] = userIdString;
            lobby.lobbyVersion += 1;

            let savedLobby = await this.saveLobbyState(roomId, lobby);
            savedLobby = await this.cancelCountdownIfIneligible(roomId, savedLobby, 'seat_change');
            await this.emitLobbyState(roomId, savedLobby);
            return savedLobby;
        });
    }

    async leaveSeat({ roomId, userId }) {
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            const lobby = await this.getOrCreateLobby(roomId);
            const userIdString = toIdString(userId);
            const entry = lobby.playersByUserId[userIdString];
            if (!entry) {
                throw createServiceError('LOBBY_MEMBER_NOT_FOUND', 'Lobby member not found', 404);
            }

            if (entry.seatIndex !== null && entry.seatIndex !== undefined) {
                delete lobby.seats[String(entry.seatIndex)];
            }
            entry.seatIndex = null;
            entry.ready = false;
            entry.lastSeenAtMs = this.now();
            lobby.lobbyVersion += 1;

            let savedLobby = await this.saveLobbyState(roomId, lobby);
            savedLobby = await this.cancelCountdownIfIneligible(roomId, savedLobby, 'leave_seat');
            await this.emitLobbyState(roomId, savedLobby);
            return savedLobby;
        });
    }

    async setReady({ roomId, userId, ready, seatIndex = null, profile = {}, riskContext = {} }) {
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            const room = await this.getRoomById(roomId);
            let lobby = await this.getOrCreateLobby(roomId);
            const userIdString = toIdString(userId);

            if (seatIndex !== null && seatIndex !== undefined &&
                lobby.playersByUserId[userIdString]?.seatIndex !== seatIndex) {
                if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex >= lobby.maxPlayers) {
                    throw createServiceError('INVALID_SEAT', 'Seat index is invalid', 422);
                }
                for (const [seatKey, occupantUserId] of Object.entries(lobby.seats || {})) {
                    if (Number(seatKey) === seatIndex && occupantUserId && occupantUserId !== userIdString) {
                        throw createServiceError('SEAT_TAKEN', 'Seat is already taken', 409);
                    }
                }
                if (!lobby.playersByUserId[userIdString]) {
                    lobby.playersByUserId[userIdString] = {
                        userId: userIdString,
                        username: profile.username || 'Guest',
                        avatar: profile.avatar || '',
                        seatIndex: null,
                        ready: false,
                        role: 'player',
                        joinedAtMs: this.now(),
                        lastSeenAtMs: this.now()
                    };
                }
                this.applyRiskContext(lobby.playersByUserId[userIdString], riskContext);
                const previousSeat = lobby.playersByUserId[userIdString].seatIndex;
                if (previousSeat !== null && previousSeat !== undefined) {
                    delete lobby.seats[String(previousSeat)];
                }
                lobby.playersByUserId[userIdString].seatIndex = seatIndex;
                lobby.playersByUserId[userIdString].role = 'player';
                lobby.playersByUserId[userIdString].ready = false;
                lobby.playersByUserId[userIdString].lastSeenAtMs = this.now();
                lobby.seats[String(seatIndex)] = userIdString;
                lobby.lobbyVersion += 1;
            }

            const entry = lobby.playersByUserId[userIdString];
            if (!entry || entry.seatIndex === null || entry.seatIndex === undefined) {
                throw createServiceError('SEAT_REQUIRED', 'Player must claim a seat before readying', 422);
            }

            const stakeConfig = settlementService.normalizeStakeConfig(room.gameConfig?.stake || {});
            if (Boolean(ready) && settlementService.requiresEscrow(stakeConfig)) {
                await settlementService.precheckStakeEntry({
                    userId,
                    entryFee: stakeConfig.entryFee,
                    currency: stakeConfig.currency
                });
            }

            entry.ready = Boolean(ready);
            entry.lastSeenAtMs = this.now();
            this.applyRiskContext(entry, riskContext);
            lobby.lobbyVersion += 1;
            lobby = await this.saveLobbyState(roomId, lobby);

            if (entry.ready) {
                lobby = await this.startCountdownIfEligible(roomId, lobby);
            } else {
                lobby = await this.cancelCountdownIfIneligible(roomId, lobby, 'player_unready');
            }

            await this.emitLobbyState(roomId, lobby);
            return lobby;
        });
    }

    getReadyPlayerEntries(lobby) {
        return Object.values(lobby.playersByUserId || {})
            .filter((entry) => entry.role === 'player' && Number.isInteger(entry.seatIndex) && entry.ready)
            .sort((left, right) => left.seatIndex - right.seatIndex);
    }

    clearCountdownTimer(roomId) {
        const existing = this.countdownTimers.get(roomId);
        if (existing) {
            clearTimeout(existing);
            this.countdownTimers.delete(roomId);
        }
    }

    async startCountdownIfEligible(roomId, lobbyState = null) {
        let lobby = lobbyState || await this.getOrCreateLobby(roomId);
        const readyPlayers = this.getReadyPlayerEntries(lobby);
        if (readyPlayers.length < lobby.minPlayersToStart || lobby.activeMatchId) {
            return lobby;
        }
        if (lobby.status === 'countdown' && lobby.countdownEndsAt) {
            return lobby;
        }

        lobby.status = 'countdown';
        lobby.countdownEndsAt = this.now() + (lobby.countdownSec * 1000);
        lobby.lobbyVersion += 1;
        lobby = await this.saveLobbyState(roomId, lobby);
        this.emit('cc:room:countdown_started', toRoomChannel(roomId), {
            roomId,
            lobbyVersion: lobby.lobbyVersion,
            countdownEndsAt: lobby.countdownEndsAt
        });
        telemetry.info('countdown_started', {
            roomId,
            lobbyVersion: lobby.lobbyVersion,
            readyPlayers: readyPlayers.length
        });
        this.clearCountdownTimer(roomId);
        const delayMs = Math.max(0, lobby.countdownEndsAt - this.now());
        this.countdownTimers.set(roomId, setTimeout(() => {
            this.handleCountdownElapsed(roomId).catch((error) => {
                console.error('Color Clash countdown error:', error.message);
            });
        }, delayMs));
        return lobby;
    }

    async cancelCountdown(roomId, reason = 'eligibility_lost') {
        let lobby = await this.getOrCreateLobby(roomId);
        if (lobby.status !== 'countdown') {
            return lobby;
        }
        this.clearCountdownTimer(roomId);
        lobby.status = 'open';
        lobby.countdownEndsAt = null;
        lobby.lobbyVersion += 1;
        lobby = await this.saveLobbyState(roomId, lobby);
        this.emit('cc:room:countdown_cancelled', toRoomChannel(roomId), {
            roomId,
            lobbyVersion: lobby.lobbyVersion,
            reason
        });
        telemetry.info('countdown_cancelled', {
            roomId,
            lobbyVersion: lobby.lobbyVersion,
            reason
        });
        return lobby;
    }

    async cancelCountdownIfIneligible(roomId, lobbyState = null, reason = 'eligibility_lost') {
        const lobby = lobbyState || await this.getOrCreateLobby(roomId);
        const readyPlayers = this.getReadyPlayerEntries(lobby);
        if (lobby.status === 'countdown' && readyPlayers.length < lobby.minPlayersToStart) {
            return this.cancelCountdown(roomId, reason);
        }
        return lobby;
    }

    async handleCountdownElapsed(roomId) {
        this.clearCountdownTimer(roomId);
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            let lobby = await this.getOrCreateLobby(roomId);
            const readyPlayers = this.getReadyPlayerEntries(lobby);
            if (readyPlayers.length < lobby.minPlayersToStart) {
                return this.cancelCountdown(roomId, 'eligibility_lost');
            }
            return this.createMatchFromLobby({ roomId, lobby, lockHeld: true });
        });
    }

    async clearMatchRuntimeState(matchId, players = []) {
        const keys = [
            KEYS.matchState(matchId),
            KEYS.draw(matchId),
            KEYS.discard(matchId),
            KEYS.timer(matchId),
            KEYS.replay(matchId),
            KEYS.playersPresence(matchId),
            KEYS.spectatorsPresence(matchId)
        ];

        for (const player of players) {
            const userId = toIdString(player.userId);
            if (!userId) continue;
            keys.push(KEYS.hand(matchId, userId));
            keys.push(KEYS.snapshot(matchId, userId));
        }

        await this.deleteKeys(keys);
    }

    async abortPendingMatchStart({
        roomId,
        lobby,
        matchId,
        roundId = null,
        players = [],
        reason = 'match_start_failed',
        error = null,
        refundHeldEscrows = true
    }) {
        const roomIdString = toIdString(roomId);
        const matchIdString = toIdString(matchId);
        this.clearTurnTimer(matchIdString);
        await this.clearMatchRuntimeState(matchIdString, players);

        if (roundId) {
            await ColorClashRound.findByIdAndUpdate(roundId, {
                $set: {
                    status: 'cancelled',
                    endedAt: new Date(this.now()),
                    updatedAt: new Date(this.now())
                }
            });
        }

        await ColorClashMatch.findByIdAndUpdate(matchId, {
            $set: {
                status: 'invalidated',
                endedAt: new Date(this.now()),
                updatedAt: new Date(this.now()),
                'settlement.error': error?.code || error?.message || reason
            }
        });

        if (refundHeldEscrows) {
            try {
                await settlementService.refundHeldEscrowsForMatch({
                    matchId,
                    reason
                });
            } catch (refundError) {
                await ColorClashMatch.findByIdAndUpdate(matchId, {
                    $set: {
                        'settlement.status': 'failed',
                        'settlement.error': refundError.code || refundError.message || 'REFUND_FAILED'
                    }
                });
            }
        }

        const nextLobby = lobby || await this.getOrCreateLobby(roomIdString);
        const wasCountingDown = nextLobby.status === 'countdown';
        nextLobby.status = 'open';
        nextLobby.activeMatchId = null;
        nextLobby.countdownEndsAt = null;
        for (const entry of Object.values(nextLobby.playersByUserId || {})) {
            entry.ready = false;
        }
        nextLobby.lobbyVersion += 1;
        const savedLobby = await this.saveLobbyState(roomIdString, nextLobby);

        await Room.findByIdAndUpdate(roomId, {
            $set: {
                'gameConfig.activeMatchId': null,
                'gameConfig.lobbyStatus': 'open'
            }
        });

        if (wasCountingDown) {
            this.emit('cc:room:countdown_cancelled', toRoomChannel(roomIdString), {
                roomId: roomIdString,
                lobbyVersion: savedLobby.lobbyVersion,
                reason
            });
        }
        await this.emitLobbyState(roomIdString, savedLobby);

        return savedLobby;
    }

    async createMatchFromLobby({ roomId, lobby = null, lockHeld = false }) {
        if (!lockHeld) {
            return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () =>
                this.createMatchFromLobby({ roomId, lobby, lockHeld: true }));
        }

        const room = await this.getRoomById(roomId);
        const activeLobby = lobby || await this.getOrCreateLobby(roomId);
        const readyPlayers = this.getReadyPlayerEntries(activeLobby);

        if (readyPlayers.length < activeLobby.minPlayersToStart) {
            throw createServiceError('NOT_ENOUGH_READY_PLAYERS', 'Not enough ready players to start the match', 409);
        }
        if (activeLobby.activeMatchId || room.gameConfig?.activeMatchId) {
            throw createServiceError('MATCH_ALREADY_ACTIVE', 'Room already has an active match', 409);
        }

        let seasonId = room.gameConfig?.seasonId || null;
        if ((room.gameConfig?.tableMode || 'friend_room') === 'ranked' && !seasonId) {
            const currentSeason = await seasonService.getCurrentSeason({ allowProvision: true });
            seasonId = currentSeason?._id || null;
            if (seasonId) {
                await Room.findByIdAndUpdate(room._id, {
                    $set: {
                        'gameConfig.seasonId': seasonId
                    }
                });
                room.gameConfig = {
                    ...(room.gameConfig || {}),
                    seasonId
                };
            }
        }

        const matchDoc = await ColorClashMatch.create({
            roomId: room._id,
            gameId: 'color_clash',
            status: 'pending',
            tableMode: room.gameConfig?.tableMode || 'friend_room',
            seasonId,
            configSnapshot: {
                roomGameConfig: jsonClone(room.gameConfig || {}),
                roomSettings: {
                    allowSpectators: room.gameConfig?.allowSpectators !== false,
                    countdownSec: room.gameConfig?.countdownSec || activeLobby.countdownSec,
                    turnTimeoutSec: room.gameConfig?.turnTimeoutSec || 25
                }
            },
            players: readyPlayers.map((entry) => ({
                userId: entry.userId,
                seatIndex: entry.seatIndex,
                usernameSnapshot: entry.username,
                avatarSnapshot: entry.avatar,
                status: 'active'
            })),
            playerContexts: readyPlayers.map((entry) => ({
                userId: entry.userId,
                ipHash: activeLobby.playersByUserId?.[toIdString(entry.userId)]?.ipHash || null,
                deviceHash: activeLobby.playersByUserId?.[toIdString(entry.userId)]?.deviceHash || null,
                region: activeLobby.playersByUserId?.[toIdString(entry.userId)]?.region || ''
            })),
            currentRoundNumber: 1,
            version: 0
        });

        const stakeConfig = settlementService.normalizeStakeConfig(room.gameConfig?.stake || {});

        try {
            if (settlementService.requiresEscrow(stakeConfig)) {
                await settlementService.ensureEntryHoldsForMatch({
                    matchId: matchDoc._id,
                    roomId: room._id,
                    seasonId,
                    tableMode: room.gameConfig?.tableMode || 'friend_room',
                    players: readyPlayers.map((entry) => ({
                        userId: entry.userId,
                        seatIndex: entry.seatIndex
                    })),
                    stakeConfig
                });
            }

            return this.dealAndStartMatch({
                room,
                lobby: activeLobby,
                matchDoc,
                readyPlayers
            });
        } catch (error) {
            await this.abortPendingMatchStart({
                roomId: room._id,
                lobby: activeLobby,
                matchId: matchDoc._id,
                players: readyPlayers,
                reason: 'prestart_refund',
                error,
                refundHeldEscrows: settlementService.requiresEscrow(stakeConfig)
            });
            throw error;
        }
    }

    async dealAndStartMatch({ room, lobby, matchDoc, readyPlayers }) {
        const roundNumber = 1;
        const shuffleSeed = `${toIdString(matchDoc._id)}:${toIdString(room._id)}:${roundNumber}`;
        const created = createInitialState({
            players: readyPlayers.map((entry) => ({
                seatIndex: entry.seatIndex,
                userId: entry.userId
            })),
            rulesConfig: room.gameConfig?.rules || {},
            shuffleSeed,
            roundNumber
        });

        const roundDoc = await ColorClashRound.create({
            matchId: matchDoc._id,
            roomId: room._id,
            roundNumber,
            status: 'active',
            publicStartState: serializePublicState({ state: created.state }),
            startedAt: new Date(this.now())
        });

        const matchEnvelope = this.buildMatchEnvelope({
            matchDoc,
            roundDoc,
            room,
            engineState: created.state,
            version: 1
        });

        await this.writeActiveMatchState({
            matchEnvelope,
            engineState: created.state
        });
        await this.writeReconnectSnapshots(matchEnvelope, created.state);
        await this.persistMatchProjection(toIdString(matchDoc._id), created.state, 1, 'active');

        await Room.findByIdAndUpdate(room._id, {
            $set: {
                'gameConfig.activeMatchId': matchDoc._id,
                'gameConfig.lobbyStatus': 'in_progress'
            }
        });

        lobby.status = 'in_progress';
        lobby.activeMatchId = toIdString(matchDoc._id);
        lobby.countdownEndsAt = null;
        lobby.lobbyVersion += 1;
        await this.saveLobbyState(toIdString(room._id), lobby);
        await this.emitLobbyState(toIdString(room._id), lobby);

        await this.appendReplayEvent(toIdString(matchDoc._id), {
            version: 1,
            eventName: 'cc:room:match_started',
            payload: {
                roomId: toIdString(room._id),
                matchId: toIdString(matchDoc._id),
                players: readyPlayers.map((entry) => ({
                    userId: entry.userId,
                    seatIndex: entry.seatIndex,
                    username: entry.username,
                    avatar: entry.avatar
                }))
            }
        });
        await this.appendReplayEvent(toIdString(matchDoc._id), {
            version: 1,
            eventName: 'cc:match:state_patch',
            payload: this.buildPublicPatchPayload(matchEnvelope, created.state, created.events, null)
        });

        this.emit('cc:room:match_started', toRoomChannel(toIdString(room._id)), {
            roomId: toIdString(room._id),
            matchId: toIdString(matchDoc._id),
            version: 1,
            players: readyPlayers.map((entry) => ({
                userId: entry.userId,
                seatIndex: entry.seatIndex,
                username: entry.username,
                avatar: entry.avatar
            }))
        });
        this.emit('cc:match:state_patch', toMatchChannel(toIdString(matchDoc._id)), this.buildPublicPatchPayload(matchEnvelope, created.state, created.events, null));
        telemetry.info('match_started', {
            roomId: toIdString(room._id),
            matchId: toIdString(matchDoc._id),
            tableMode: matchDoc.tableMode,
            playerCount: readyPlayers.length
        });

        for (const player of readyPlayers) {
            const privateState = serializePrivateState({ state: created.state, seatIndex: player.seatIndex });
            this.emit('cc:player:hand_state', toUserChannel(player.userId), {
                matchId: toIdString(matchDoc._id),
                roomId: toIdString(room._id),
                version: 1,
                seatIndex: player.seatIndex,
                privateState
            });
        }

        await ColorClashMatch.findByIdAndUpdate(matchDoc._id, {
            $set: {
                status: 'active',
                version: 1,
                publicState: serializePublicState({ state: created.state }),
                startedAt: new Date(this.now()),
                updatedAt: new Date(this.now())
            }
        });

        // Valid-start boundary: after Mongo match/round docs exist, Redis hands/draw/discard
        // are written, Room.gameConfig.activeMatchId is set, and the initial state has been
        // emitted. Paid tables only become financially valid after escrows also lock successfully.
        const stakeConfig = settlementService.normalizeStakeConfig(room.gameConfig?.stake || {});
        if (settlementService.requiresEscrow(stakeConfig)) {
            try {
                await settlementService.lockEscrowsForValidStart({
                    matchId: matchDoc._id,
                    playerUserIds: readyPlayers.map((entry) => entry.userId)
                });
            } catch (error) {
                await this.abortPendingMatchStart({
                    roomId: room._id,
                    lobby,
                    matchId: matchDoc._id,
                    roundId: roundDoc._id,
                    players: readyPlayers,
                    reason: 'valid_start_lock_failed',
                    error,
                    refundHeldEscrows: true
                });
                throw error;
            }
        }

        await this.scheduleTurnTimer(matchEnvelope);

        return {
            matchId: toIdString(matchDoc._id),
            roomId: toIdString(room._id),
            roundId: toIdString(roundDoc._id),
            version: 1,
            lobbyVersion: lobby.lobbyVersion
        };
    }

    async cancelRoom({ roomId, reason = 'cancelled_by_host' }) {
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            const room = await this.getRoomById(roomId);
            if (room.gameConfig?.activeMatchId) {
                const activeMatch = await ColorClashMatch.findById(room.gameConfig.activeMatchId).lean();
                if (activeMatch && !['completed', 'cancelled'].includes(activeMatch.status)) {
                    throw createServiceError('MATCH_ACTIVE', 'Cannot cancel a room with an active Color Clash match', 409);
                }
            }

            let lobby = await this.getOrCreateLobby(roomId);
            if (lobby.status === 'countdown') {
                this.emit('cc:room:countdown_cancelled', toRoomChannel(roomId), {
                    roomId,
                    lobbyVersion: lobby.lobbyVersion,
                    reason
                });
            }

            this.clearCountdownTimer(roomId);
            lobby.status = 'cancelled';
            lobby.activeMatchId = null;
            lobby.countdownEndsAt = null;
            lobby.lobbyVersion += 1;
            lobby = await this.saveLobbyState(roomId, lobby);

            await Room.findByIdAndUpdate(roomId, {
                $set: {
                    'gameConfig.activeMatchId': null,
                    'gameConfig.lobbyStatus': 'cancelled',
                    showInExplore: false,
                    endedAt: new Date(this.now())
                }
            });

            await this.emitLobbyState(roomId, lobby);
            return {
                roomId,
                lobby
            };
        });
    }

    clearTurnTimer(matchId) {
        const existing = this.turnTimers.get(matchId);
        if (existing) {
            clearTimeout(existing);
            this.turnTimers.delete(matchId);
        }
    }

    async scheduleTurnTimer(matchEnvelope) {
        const matchId = matchEnvelope.matchId;
        this.clearTurnTimer(matchId);
        if (matchEnvelope.phase === 'completed' || matchEnvelope.status === 'completed') {
            return;
        }

        const timeoutSec = Number(matchEnvelope.configSnapshot?.roomGameConfig?.turnTimeoutSec || 25);
        const timerPayload = {
            matchId,
            version: matchEnvelope.version,
            seatIndex: matchEnvelope.currentTurnSeat,
            turnEndsAt: this.now() + (timeoutSec * 1000),
            graceEndsAt: this.now() + ((timeoutSec + 5) * 1000)
        };
        await this.writeJson(KEYS.timer(matchId), timerPayload, MATCH_TTL_SECONDS);

        this.turnTimers.set(matchId, setTimeout(() => {
            this.handleTimeout({
                matchId,
                expectedVersion: timerPayload.version,
                expectedSeat: timerPayload.seatIndex
            }).catch((error) => {
                console.error('Color Clash timeout error:', error.message);
            });
        }, timeoutSec * 1000));
    }

    async markTerminalMatch(matchEnvelope, engineState) {
        this.clearTurnTimer(matchEnvelope.matchId);
        await this.deleteKeys([KEYS.timer(matchEnvelope.matchId)]);
        await this.persistRoundProjection(matchEnvelope.roundId, engineState);
        await this.persistMatchProjection(matchEnvelope.matchId, engineState, matchEnvelope.version, 'completed');
        await Room.findByIdAndUpdate(matchEnvelope.roomId, {
            $set: {
                'gameConfig.activeMatchId': null,
                'gameConfig.lastCompletedMatchId': matchEnvelope.matchId,
                'gameConfig.lobbyStatus': 'finished'
            }
        });
        const lobby = await this.getOrCreateLobby(matchEnvelope.roomId);
        lobby.status = 'finished';
        lobby.activeMatchId = null;
        lobby.countdownEndsAt = null;
        lobby.lobbyVersion += 1;
        await this.saveLobbyState(matchEnvelope.roomId, lobby);
        await this.emitLobbyState(matchEnvelope.roomId, lobby);
        try {
            await settlementService.settleMatch({
                matchId: matchEnvelope.matchId
            });
        } catch (error) {
            console.error('Color Clash settlement error:', error.message);
        }
        await this.expireTerminalState(matchEnvelope.matchId);
    }

    async expireTerminalState(matchId) {
        const redis = this.requireRedis();
        const matchEnvelope = await this.readJson(KEYS.matchState(matchId));
        const keysToExpire = [
            KEYS.matchState(matchId),
            KEYS.draw(matchId),
            KEYS.discard(matchId),
            KEYS.replay(matchId),
            KEYS.timer(matchId),
            KEYS.playersPresence(matchId),
            KEYS.spectatorsPresence(matchId)
        ];
        if (matchEnvelope?.players) {
            for (const player of matchEnvelope.players) {
                const userId = toIdString(player.userId);
                keysToExpire.push(KEYS.hand(matchId, userId));
                keysToExpire.push(KEYS.snapshot(matchId, userId));
            }
        }

        for (const key of keysToExpire) {
            if (!key) continue;
            await redis.expire(key, SNAPSHOT_TTL_SECONDS);
        }
    }

    getSeatForUser(matchEnvelope, userId) {
        const userIdString = toIdString(userId);
        return matchEnvelope.players.find((player) => toIdString(player.userId) === userIdString) || null;
    }

    async storeMoveResult(matchId, userId, clientMoveId, result) {
        await this.writeJson(KEYS.move(matchId, userId, clientMoveId), result, MOVE_TTL_SECONDS);
        return result;
    }

    async readStoredMoveResult(matchId, userId, clientMoveId) {
        return this.readJson(KEYS.move(matchId, userId, clientMoveId));
    }

    buildMoveRecord({
        matchEnvelope,
        actor,
        clientMoveId,
        moveType,
        versionBefore,
        versionAfter,
        payload,
        publicPatch,
        status = 'accepted',
        reasonCode = null
    }) {
        return {
            matchId: matchEnvelope.matchId,
            roundId: matchEnvelope.roundId,
            roomId: matchEnvelope.roomId,
            sequence: versionAfter,
            versionBefore,
            versionAfter,
            actorUserId: actor.userId,
            actorSeat: actor.seatIndex,
            clientMoveId,
            moveType,
            status,
            payload,
            publicPatch,
            reasonCode
        };
    }

    async submitMove({ matchId, userId, clientMoveId, expectedVersion, move }) {
        const userIdString = toIdString(userId);
        const stored = await this.readStoredMoveResult(matchId, userIdString, clientMoveId);
        if (stored) {
            telemetry.warn('move_duplicate_ignored', {
                matchId,
                userId: userIdString,
                clientMoveId
            });
            return {
                ...stored,
                duplicate: true
            };
        }

        return this.withLock(KEYS.matchLock(matchId), MATCH_LOCK_TTL_MS, async () => {
            const matchDoc = await ColorClashMatch.findById(matchId).lean();
            if (!matchDoc) {
                throw createServiceError('MATCH_NOT_FOUND', 'Match not found', 404);
            }

            const { matchEnvelope, engineState } = await this.loadActiveMatchState(matchId);
            if (matchEnvelope.status !== 'active' || engineState.phase !== 'active') {
                const failed = {
                    accepted: false,
                    errorCode: 'MATCH_NOT_ACTIVE',
                    snapshotRequired: true,
                    currentVersion: matchEnvelope.version
                };
                telemetry.warn('move_rejected', {
                    matchId,
                    userId: userIdString,
                    reason: failed.errorCode
                });
                return this.storeMoveResult(matchId, userIdString, clientMoveId, failed);
            }
            if (Number(expectedVersion) !== Number(matchEnvelope.version)) {
                const failed = {
                    accepted: false,
                    errorCode: 'VERSION_MISMATCH',
                    snapshotRequired: true,
                    currentVersion: matchEnvelope.version
                };
                telemetry.warn('move_rejected', {
                    matchId,
                    userId: userIdString,
                    reason: failed.errorCode,
                    expectedVersion,
                    actualVersion: matchEnvelope.version
                });
                return this.storeMoveResult(matchId, userIdString, clientMoveId, failed);
            }

            const actor = this.getSeatForUser(matchEnvelope, userIdString);
            if (!actor) {
                const failed = {
                    accepted: false,
                    errorCode: 'PLAYER_NOT_IN_MATCH',
                    snapshotRequired: false
                };
                telemetry.warn('move_rejected', {
                    matchId,
                    userId: userIdString,
                    reason: failed.errorCode
                });
                return this.storeMoveResult(matchId, userIdString, clientMoveId, failed);
            }

            let result;
            try {
                result = applyMove({
                    state: engineState,
                    actorSeat: actor.seatIndex,
                    move
                });
            } catch (error) {
                const failed = {
                    accepted: false,
                    errorCode: error.code || error.message || 'MOVE_REJECTED',
                    snapshotRequired: false,
                    currentVersion: matchEnvelope.version
                };
                telemetry.warn('move_rejected', {
                    matchId,
                    userId: userIdString,
                    actorSeat: actor.seatIndex,
                    reason: failed.errorCode
                });
                this.emit('cc:player:command_error', toUserChannel(userIdString), {
                    matchId,
                    clientMoveId,
                    ...failed
                });
                return this.storeMoveResult(matchId, userIdString, clientMoveId, failed);
            }

            const nextVersion = matchEnvelope.version + 1;
            const nextEnvelope = {
                ...matchEnvelope,
                version: nextVersion,
                status: result.nextState.phase === 'completed' ? 'completed' : 'active',
                currentTurnSeat: result.nextState.currentTurnSeat,
                direction: result.nextState.direction,
                currentHue: result.nextState.currentHue,
                pendingEffect: jsonClone(result.nextState.pendingEffect),
                turnContext: jsonClone(result.nextState.turnContext),
                phase: result.nextState.phase,
                roundResult: jsonClone(result.nextState.roundResult),
                players: jsonClone(result.nextState.players),
                versionSeed: result.nextState.versionSeed
            };

            await this.writeActiveMatchState({
                matchEnvelope: nextEnvelope,
                engineState: result.nextState
            });
            await this.writeReconnectSnapshots(nextEnvelope, result.nextState);
            const publicPatch = this.buildPublicPatchPayload(nextEnvelope, result.nextState, result.events, actor.seatIndex);
            await this.persistMatchProjection(matchId, result.nextState, nextVersion, nextEnvelope.status);
            await this.persistRoundProjection(nextEnvelope.roundId, result.nextState);
            await ColorClashMove.create(this.buildMoveRecord({
                matchEnvelope: nextEnvelope,
                actor,
                clientMoveId,
                moveType: move.type || MOVE_TYPES.PLAY_CARD,
                versionBefore: matchEnvelope.version,
                versionAfter: nextVersion,
                payload: jsonClone(move),
                publicPatch
            }));
            await this.appendReplayEvent(matchId, {
                version: nextVersion,
                eventName: 'cc:match:state_patch',
                payload: publicPatch
            });
            telemetry.info('move_submitted', {
                matchId,
                userId: userIdString,
                actorSeat: actor.seatIndex,
                moveType: move.type || MOVE_TYPES.PLAY_CARD,
                version: nextVersion
            });

            this.emit('cc:match:state_patch', toMatchChannel(matchId), publicPatch);
            for (const [seatIndex, privateState] of Object.entries(result.privateDiffs || {})) {
                const target = nextEnvelope.players.find((player) => String(player.seatIndex) === String(seatIndex));
                if (!target) continue;
                this.emit('cc:player:hand_state', toUserChannel(target.userId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    seatIndex: Number(seatIndex),
                    privateState
                });
            }

            if ((move.type === MOVE_TYPES.DRAW_CARD || move.type === MOVE_TYPES.KEEP_DRAWN) && result.privateDiffs?.[actor.seatIndex]) {
                this.emit('cc:player:draw_result', toUserChannel(userIdString), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    seatIndex: actor.seatIndex,
                    privateState: result.privateDiffs[actor.seatIndex]
                });
            }

            if (result.nextState.pendingEffect?.kind === 'prism_surge_challenge') {
                const targetPlayer = nextEnvelope.players.find((player) => player.seatIndex === result.nextState.pendingEffect.targetSeat);
                if (targetPlayer) {
                    this.emit('cc:player:challenge_prompt', toUserChannel(targetPlayer.userId), {
                        matchId,
                        roomId: nextEnvelope.roomId,
                        version: nextVersion,
                        privateState: serializePrivateState({ state: result.nextState, seatIndex: targetPlayer.seatIndex })
                    });
                }
            }

            for (const event of result.events || []) {
                if (event.type === 'last_card_alert') {
                    this.emit('cc:match:last_card_alert', toMatchChannel(matchId), {
                        matchId,
                        roomId: nextEnvelope.roomId,
                        version: nextVersion,
                        seatIndex: event.seatIndex
                    });
                }
            }

            if (result.nextState.phase === 'completed') {
                this.emit('cc:match:round_result', toMatchChannel(matchId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    result: result.nextState.roundResult
                });
                this.emit('cc:match:finished', toMatchChannel(matchId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    result: result.nextState.roundResult
                });
                telemetry.info('match_finished', {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    reason: result.nextState.roundResult?.endReason || result.nextState.phase,
                    version: nextVersion
                });
                await this.markTerminalMatch(nextEnvelope, result.nextState);
            } else {
                await this.scheduleTurnTimer(nextEnvelope);
            }

            const success = {
                accepted: true,
                duplicate: false,
                matchId,
                version: nextVersion,
                publicState: publicPatch.publicState
            };
            return this.storeMoveResult(matchId, userIdString, clientMoveId, success);
        });
    }

    async submitChallenge({ matchId, userId, clientMoveId, expectedVersion, decision }) {
        telemetry.info('challenge_submitted', {
            matchId,
            userId: toIdString(userId),
            decision
        });
        return this.submitMove({
            matchId,
            userId,
            clientMoveId,
            expectedVersion,
            move: {
                type: decision === 'decline' ? MOVE_TYPES.DECLINE_CHALLENGE : MOVE_TYPES.CHALLENGE
            }
        });
    }

    async handleTimeout({ matchId, expectedVersion, expectedSeat }) {
        return this.withLock(KEYS.matchLock(matchId), MATCH_LOCK_TTL_MS, async () => {
            const { matchEnvelope, engineState } = await this.loadActiveMatchState(matchId);
            if (Number(matchEnvelope.version) !== Number(expectedVersion) ||
                Number(matchEnvelope.currentTurnSeat) !== Number(expectedSeat) ||
                matchEnvelope.status !== 'active') {
                return { ignored: true };
            }

            const result = autoActionOnTimeout({ state: engineState });
            const timedOutPlayer = matchEnvelope.players.find((player) => player.seatIndex === expectedSeat) || null;
            const actor = timedOutPlayer
                ? this.getSeatForUser(matchEnvelope, timedOutPlayer.userId)
                : null;
            const nextVersion = matchEnvelope.version + 1;
            const nextEnvelope = {
                ...matchEnvelope,
                version: nextVersion,
                status: result.nextState.phase === 'completed' ? 'completed' : 'active',
                currentTurnSeat: result.nextState.currentTurnSeat,
                direction: result.nextState.direction,
                currentHue: result.nextState.currentHue,
                pendingEffect: jsonClone(result.nextState.pendingEffect),
                turnContext: jsonClone(result.nextState.turnContext),
                phase: result.nextState.phase,
                roundResult: jsonClone(result.nextState.roundResult),
                players: jsonClone(result.nextState.players),
                versionSeed: result.nextState.versionSeed
            };

            await this.writeActiveMatchState({
                matchEnvelope: nextEnvelope,
                engineState: result.nextState
            });
            await this.writeReconnectSnapshots(nextEnvelope, result.nextState);
            const publicPatch = this.buildPublicPatchPayload(nextEnvelope, result.nextState, result.events, expectedSeat);
            await this.persistMatchProjection(matchId, result.nextState, nextVersion, nextEnvelope.status);
            await this.persistRoundProjection(nextEnvelope.roundId, result.nextState);
            await ColorClashMove.create(this.buildMoveRecord({
                matchEnvelope: nextEnvelope,
                actor: actor || { userId: timedOutPlayer?.userId || null, seatIndex: expectedSeat },
                clientMoveId: `timeout:${matchId}:${expectedVersion}`,
                moveType: 'timeout_auto_action',
                versionBefore: matchEnvelope.version,
                versionAfter: nextVersion,
                payload: jsonClone(result.autoMove),
                publicPatch,
                status: 'auto_applied'
            }));
            await this.appendReplayEvent(matchId, {
                version: nextVersion,
                eventName: 'cc:match:state_patch',
                payload: publicPatch
            });
            telemetry.warn('timeout_auto_action_applied', {
                matchId,
                expectedSeat,
                version: nextVersion,
                autoMoveType: result.autoMove?.type || 'unknown'
            });

            this.emit('cc:match:state_patch', toMatchChannel(matchId), publicPatch);
            for (const [seatIndex, privateState] of Object.entries(result.privateDiffs || {})) {
                const target = nextEnvelope.players.find((player) => String(player.seatIndex) === String(seatIndex));
                if (!target) continue;
                this.emit('cc:player:hand_state', toUserChannel(target.userId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    seatIndex: Number(seatIndex),
                    privateState
                });
            }

            if (result.nextState.phase === 'completed') {
                this.emit('cc:match:round_result', toMatchChannel(matchId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    result: result.nextState.roundResult
                });
                this.emit('cc:match:finished', toMatchChannel(matchId), {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    version: nextVersion,
                    result: result.nextState.roundResult
                });
                telemetry.info('match_finished', {
                    matchId,
                    roomId: nextEnvelope.roomId,
                    reason: result.nextState.roundResult?.endReason || 'timeout_completion',
                    version: nextVersion
                });
                await this.markTerminalMatch(nextEnvelope, result.nextState);
            } else {
                await this.scheduleTurnTimer(nextEnvelope);
            }

            const timedOutState = result.nextState.players.find((player) => player.seatIndex === expectedSeat) || null;
            if (timedOutPlayer?.userId && Number(timedOutState?.timeoutStrikes || 0) >= 2) {
                antiFraudService.recordTimeoutSignal({
                    matchId,
                    userId: timedOutPlayer.userId,
                    actorType: 'system'
                }).catch(() => {});

                if (result.nextState.phase === 'completed' && result.autoMove?.type === 'forfeit') {
                    antiFraudService.recordForfeitSignal({
                        matchId,
                        userId: timedOutPlayer.userId,
                        actorType: 'system'
                    }).catch(() => {});
                }
            }

            return {
                accepted: true,
                autoApplied: true,
                version: nextVersion
            };
        });
    }

    async voteRematch({ roomId, userId, vote }) {
        return this.withLock(KEYS.roomLock(roomId), ROOM_LOCK_TTL_MS, async () => {
            const room = await this.getRoomById(roomId);
            const lastCompletedMatchId = room.gameConfig?.lastCompletedMatchId;
            if (!lastCompletedMatchId) {
                throw createServiceError('REMATCH_UNAVAILABLE', 'No completed Color Clash match is available for rematch', 409);
            }

            const completedMatch = await ColorClashMatch.findById(lastCompletedMatchId).lean();
            if (!completedMatch || completedMatch.status !== 'completed') {
                throw createServiceError('REMATCH_UNAVAILABLE', 'The last Color Clash match is not eligible for rematch', 409);
            }

            const eligiblePlayers = completedMatch.players || [];
            const userIdString = toIdString(userId);
            if (!eligiblePlayers.some((player) => toIdString(player.userId) === userIdString)) {
                throw createServiceError('REMATCH_FORBIDDEN', 'Only players from the previous match can vote for rematch', 403);
            }

            const nowMs = this.now();
            const rematchWindowMs = 45 * 1000;
            let lobby = await this.getOrCreateLobby(roomId);
            if (!lobby.rematchWindowEndsAt || Number(lobby.rematchWindowEndsAt) <= nowMs) {
                lobby.rematchWindowEndsAt = nowMs + rematchWindowMs;
                lobby.rematchVotesByUserId = {};
            }

            lobby.rematchVotesByUserId = lobby.rematchVotesByUserId || {};
            if (vote) {
                lobby.rematchVotesByUserId[userIdString] = true;
            } else {
                delete lobby.rematchVotesByUserId[userIdString];
            }
            lobby.lobbyVersion += 1;

            const allAccepted = eligiblePlayers.every((player) =>
                lobby.rematchVotesByUserId[toIdString(player.userId)] === true
            );

            if (!allAccepted) {
                lobby = await this.saveLobbyState(roomId, lobby);
                await this.emitLobbyState(roomId, lobby);
                return {
                    status: 'waiting',
                    roomId,
                    votes: lobby.rematchVotesByUserId,
                    rematchWindowEndsAt: lobby.rematchWindowEndsAt,
                    lobbyVersion: lobby.lobbyVersion
                };
            }

            lobby.status = 'open';
            lobby.activeMatchId = null;
            lobby.countdownEndsAt = null;
            lobby.rematchWindowEndsAt = null;
            lobby.rematchVotesByUserId = {};
            lobby.seats = {};

            for (const player of eligiblePlayers) {
                const userIdKey = toIdString(player.userId);
                lobby.playersByUserId[userIdKey] = {
                    ...(lobby.playersByUserId[userIdKey] || {
                        userId: userIdKey,
                        joinedAtMs: nowMs,
                        lastSeenAtMs: nowMs
                    }),
                    username: player.usernameSnapshot || lobby.playersByUserId?.[userIdKey]?.username || 'Guest',
                    avatar: player.avatarSnapshot || lobby.playersByUserId?.[userIdKey]?.avatar || '',
                    seatIndex: player.seatIndex,
                    ready: true,
                    role: 'player',
                    lastSeenAtMs: nowMs
                };
                lobby.seats[String(player.seatIndex)] = userIdKey;
            }
            lobby.lobbyVersion += 1;
            lobby = await this.saveLobbyState(roomId, lobby);
            await this.emitLobbyState(roomId, lobby);

            const createdMatch = await this.createMatchFromLobby({
                roomId,
                lobby,
                lockHeld: true
            });

            return {
                status: 'matched',
                roomId,
                votes: {},
                rematchWindowEndsAt: null,
                ...createdMatch
            };
        });
    }

    async authorizeMatchAccess(matchId, userId) {
        const matchDoc = await ColorClashMatch.findById(matchId).lean();
        if (!matchDoc) {
            throw createServiceError('MATCH_NOT_FOUND', 'Match not found', 404);
        }

        const room = await this.getRoomById(matchDoc.roomId);
        const userIdString = toIdString(userId);
        const player = (matchDoc.players || []).find((entry) => toIdString(entry.userId) === userIdString);
        if (player) {
            return {
                matchDoc,
                room,
                viewerRole: 'player'
            };
        }

        await this.resolveRoomAccess(room, userId, { spectatorRequested: true });
        return {
            matchDoc,
            room,
            viewerRole: 'spectator'
        };
    }

    async joinSpectator({ matchId, userId }) {
        const access = await this.authorizeMatchAccess(matchId, userId);
        if (access.viewerRole !== 'spectator') {
            return access;
        }
        await this.touchMatchPresence(matchId, userId, 'spectator');
        return access;
    }

    async subscribeMatch({ matchId, userId }) {
        const access = await this.authorizeMatchAccess(matchId, userId);
        await this.touchMatchPresence(matchId, userId, access.viewerRole);
        return access;
    }
}

const matchService = new ColorClashMatchService();

module.exports = matchService;
module.exports.ColorClashMatchService = ColorClashMatchService;
module.exports.KEYS = KEYS;
module.exports.toRoomChannel = toRoomChannel;
module.exports.toMatchChannel = toMatchChannel;
module.exports.toUserChannel = toUserChannel;
module.exports.createServiceError = createServiceError;
