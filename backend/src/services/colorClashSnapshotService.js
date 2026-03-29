const {
    serializePrivateState
} = require('./colorClashRulesEngine');
const matchService = require('./colorClashMatchService');
const { KEYS, createServiceError } = require('./colorClashMatchService');

class ColorClashSnapshotService {
    mergeTimerIntoPublicState(publicState, timerPayload) {
        if (!publicState) {
            return publicState;
        }

        const turnContext = {
            ...(publicState.turnContext || {})
        };

        if (timerPayload && Number(timerPayload.seatIndex) === Number(publicState.currentTurnSeat)) {
            turnContext.turnEndsAt = Number(timerPayload.turnEndsAt);
            turnContext.graceEndsAt = Number(timerPayload.graceEndsAt);
        }

        return {
            ...publicState,
            turnContext
        };
    }

    async buildPublicStateWithTimer(matchId, matchEnvelope, engineState) {
        const timerPayload = await matchService.readJson(KEYS.timer(matchId));
        return this.mergeTimerIntoPublicState(matchService.buildClientPublicState(
            matchEnvelope,
            engineState,
            timerPayload
        ), timerPayload);
    }

    async buildPublicSnapshot({ matchEnvelope, engineState, viewerRole }) {
        const presence = await matchService.readPresenceCounts(matchEnvelope.matchId);
        return {
            matchId: matchEnvelope.matchId,
            roomId: matchEnvelope.roomId,
            version: matchEnvelope.version,
            viewerRole,
            publicState: await this.buildPublicStateWithTimer(
                matchEnvelope.matchId,
                matchEnvelope,
                engineState
            ),
            presence,
            replayAvailable: true
        };
    }

    async buildPrivateSnapshot({ matchEnvelope, engineState, userId }) {
        const player = matchEnvelope.players.find((entry) => entry.userId?.toString() === userId.toString());
        if (!player) {
            throw createServiceError('PLAYER_NOT_IN_MATCH', 'Player is not in this match', 403);
        }

        return {
            matchId: matchEnvelope.matchId,
            roomId: matchEnvelope.roomId,
            version: matchEnvelope.version,
            viewerRole: 'player',
            publicState: await this.buildPublicStateWithTimer(
                matchEnvelope.matchId,
                matchEnvelope,
                engineState
            ),
            privateState: serializePrivateState({ state: engineState, seatIndex: player.seatIndex }),
            replayAvailable: true
        };
    }

    async getReplaySinceVersion(matchId, version) {
        return matchService.getReplaySinceVersion(matchId, version);
    }

    async getMatchSnapshot(matchId, userId, viewerRole = null) {
        const access = await matchService.authorizeMatchAccess(matchId, userId);
        const resolvedRole = viewerRole || access.viewerRole;

        if (resolvedRole === 'player') {
            const cached = await matchService.readJson(KEYS.snapshot(matchId, userId));
            if (cached && Number(cached.version) >= 1) {
                if (cached.publicState) {
                    const timerPayload = await matchService.readJson(KEYS.timer(matchId));
                    cached.publicState = this.mergeTimerIntoPublicState(
                        cached.publicState,
                        timerPayload
                    );
                }
                return cached;
            }
        }

        const { matchEnvelope, engineState } = await matchService.loadActiveMatchState(matchId);
        if (resolvedRole === 'spectator') {
            return this.buildPublicSnapshot({
                matchEnvelope,
                engineState,
                viewerRole: 'spectator'
            });
        }

        return this.buildPrivateSnapshot({
            matchEnvelope,
            engineState,
            userId
        });
    }

    async getReconnectPayload(matchId, userId, lastKnownVersion = 0) {
        const access = await matchService.authorizeMatchAccess(matchId, userId);
        const replay = await this.getReplaySinceVersion(matchId, lastKnownVersion);
        if (!replay.snapshotRequired && replay.replay.length > 0) {
            return {
                mode: 'replay',
                viewerRole: access.viewerRole,
                replay: replay.replay
            };
        }

        return {
            mode: 'snapshot',
            viewerRole: access.viewerRole,
            snapshot: await this.getMatchSnapshot(matchId, userId, access.viewerRole)
        };
    }
}

module.exports = new ColorClashSnapshotService();
module.exports.ColorClashSnapshotService = ColorClashSnapshotService;
