const matchService = require('../services/colorClashMatchService');
const snapshotService = require('../services/colorClashSnapshotService');
const antiFraudService = require('../services/colorClashAntiFraudService');
const { toRoomChannel, toMatchChannel, toUserChannel } = require('../services/colorClashMatchService');

const safeAck = (ack, payload) => {
    if (typeof ack === 'function') {
        ack(payload);
    }
};

const errorPayload = (error) => ({
    ok: false,
    error: {
        code: error.code || 'COLOR_CLASH_ERROR',
        message: error.message || 'Color Clash request failed',
        status: error.status || 500
    }
});

const registerColorClashSocket = ({
    io,
    socket,
    redis
}) => {
    matchService.configure({ io, redis });
    socket.join(toUserChannel(socket.userId));

    socket.on('cc:room:subscribe', async (payload = {}, ack) => {
        try {
            const roomId = payload.roomId;
            const result = await matchService.subscribeRoom({
                roomId,
                userId: socket.userId,
                profile: {
                    username: socket.username,
                    avatar: socket.avatar
                },
                riskContext: antiFraudService.buildRequestContext({
                    ip: socket.handshake?.address || socket.handshake?.headers?.['x-forwarded-for'] || null
                })
            });

            const safeLobby = matchService.sanitizeLobbyForClient(result.lobby);

            socket.join(toRoomChannel(roomId));
            safeAck(ack, {
                ok: true,
                roomId,
                viewerRole: result.viewerRole,
                lobby: safeLobby
            });
            socket.emit('cc:room:lobby_state', {
                roomId,
                lobbyVersion: safeLobby.lobbyVersion,
                status: safeLobby.status,
                seats: safeLobby.seats,
                playersByUserId: safeLobby.playersByUserId,
                countdownEndsAt: safeLobby.countdownEndsAt,
                activeMatchId: safeLobby.activeMatchId
            });
        } catch (error) {
            safeAck(ack, errorPayload(error));
        }
    });

    socket.on('cc:match:subscribe', async (payload = {}, ack) => {
        try {
            const matchId = payload.matchId;
            const lastVersion = Number(payload.lastVersion || 0);
            const access = await matchService.subscribeMatch({
                matchId,
                userId: socket.userId
            });

            socket.join(toMatchChannel(matchId));

            const reconnectPayload = lastVersion > 0
                ? await snapshotService.getReconnectPayload(matchId, socket.userId, lastVersion)
                : {
                    mode: 'snapshot',
                    viewerRole: access.viewerRole,
                    snapshot: await snapshotService.getMatchSnapshot(matchId, socket.userId, access.viewerRole)
                };

            safeAck(ack, {
                ok: true,
                matchId,
                ...reconnectPayload
            });
        } catch (error) {
            safeAck(ack, errorPayload(error));
        }
    });

    socket.on('cc:command:move', async (payload = {}, ack) => {
        try {
            const result = await matchService.submitMove({
                matchId: payload.matchId,
                userId: socket.userId,
                clientMoveId: payload.clientMoveId,
                expectedVersion: payload.expectedVersion,
                move: payload.move
            });

            if (!result.accepted) {
                socket.emit('cc:player:command_error', {
                    matchId: payload.matchId,
                    clientMoveId: payload.clientMoveId,
                    ...result
                });
            }

            safeAck(ack, {
                ok: result.accepted,
                ...result
            });
        } catch (error) {
            const payloadError = errorPayload(error);
            socket.emit('cc:player:command_error', {
                matchId: payload.matchId,
                clientMoveId: payload.clientMoveId,
                errorCode: payloadError.error.code,
                message: payloadError.error.message
            });
            safeAck(ack, payloadError);
        }
    });

    socket.on('cc:command:challenge', async (payload = {}, ack) => {
        try {
            const result = await matchService.submitChallenge({
                matchId: payload.matchId,
                userId: socket.userId,
                clientMoveId: payload.clientMoveId,
                expectedVersion: payload.expectedVersion,
                decision: payload.decision
            });

            if (!result.accepted) {
                socket.emit('cc:player:command_error', {
                    matchId: payload.matchId,
                    clientMoveId: payload.clientMoveId,
                    ...result
                });
            }

            safeAck(ack, {
                ok: result.accepted,
                ...result
            });
        } catch (error) {
            const payloadError = errorPayload(error);
            socket.emit('cc:player:command_error', {
                matchId: payload.matchId,
                clientMoveId: payload.clientMoveId,
                errorCode: payloadError.error.code,
                message: payloadError.error.message
            });
            safeAck(ack, payloadError);
        }
    });

    socket.on('cc:heartbeat', async (payload = {}, ack) => {
        try {
            if (payload.matchId) {
                await matchService.touchMatchPresence(
                    payload.matchId,
                    socket.userId,
                    payload.viewerRole === 'spectator' ? 'spectator' : 'player'
                );
            }
            safeAck(ack, {
                ok: true,
                matchId: payload.matchId || null,
                roomId: payload.roomId || null
            });
        } catch (error) {
            safeAck(ack, errorPayload(error));
        }
    });
};

module.exports = registerColorClashSocket;
