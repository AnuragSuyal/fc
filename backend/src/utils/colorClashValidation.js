const { z } = require('zod');

const GAME_ID = 'color_clash';
const DEFAULT_THEME_PACK_ID = 'forest_picnic';
const DEFAULT_REGION = 'Global';
const RANKED_MIN_LEVEL = 3;
const THEME_PACK_IDS = ['forest_picnic', 'neon_orbit', 'candy_carnival'];
const ROOM_VISIBILITIES = ['public', 'private', 'invite_only'];
const ROOM_TABLE_MODES = ['friend_room', 'gold_stake', 'custom_chaos'];
const MATCHMAKING_MODES = ['casual_free', 'gold_stake', 'ranked'];
const LEADERBOARD_PERIODS = ['daily', 'weekly', 'monthly', 'alltime'];

const objectIdSchema = z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid identifier');
const trimmedString = (max) => z.string().trim().min(1).max(max);
const stakePayoutSchema = z.object({
    place: z.number().int().min(1),
    bps: z.number().int().min(1).max(10000)
});

const createFriendRoomSchema = z.object({
    name: z.string().trim().min(3).max(50).optional(),
    description: z.string().trim().max(200).optional(),
    visibility: z.enum(ROOM_VISIBILITIES).default('invite_only'),
    allowSpectators: z.boolean().default(true),
    maxPlayers: z.number().int().min(2).max(8).default(4),
    minPlayersToStart: z.number().int().min(2).max(8).optional(),
    countdownSec: z.number().int().min(3).max(30).optional(),
    turnTimeoutSec: z.number().int().min(5).max(90).optional(),
    themePackId: z.enum(THEME_PACK_IDS).default(DEFAULT_THEME_PACK_ID),
    tableMode: z.enum(ROOM_TABLE_MODES).default('friend_room'),
    stakeEntryFee: z.number().int().min(0).default(0),
    stakePayouts: z.array(stakePayoutSchema).min(1).max(8).optional(),
    houseFeeBps: z.number().int().min(0).max(10000).optional(),
    sinkFeeBps: z.number().int().min(0).max(10000).optional(),
    invitedUserIds: z.array(objectIdSchema).max(24).default([]),
    customCards: z.object({
        shield: z.boolean().optional(),
        echo: z.boolean().optional(),
        swap: z.boolean().optional()
    }).default({})
}).superRefine((value, ctx) => {
    const minPlayers = value.minPlayersToStart || 2;
    if (minPlayers > value.maxPlayers) {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['minPlayersToStart'],
            message: 'Minimum players cannot exceed maxPlayers'
        });
    }
    if (value.stakeEntryFee > 0 && value.tableMode === 'friend_room') {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['tableMode'],
            message: 'Stake rooms must use gold_stake or custom_chaos mode'
        });
    }
    if (value.stakeEntryFee === 0 && (value.stakePayouts?.length || value.houseFeeBps || value.sinkFeeBps)) {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['stakeEntryFee'],
            message: 'Stake payout settings require a positive stakeEntryFee'
        });
    }
    if (value.stakePayouts?.length) {
        const uniquePlaces = new Set(value.stakePayouts.map((entry) => entry.place));
        if (uniquePlaces.size !== value.stakePayouts.length) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                path: ['stakePayouts'],
                message: 'Stake payout places must be unique'
            });
        }
        const totalBps = value.stakePayouts.reduce((total, entry) => total + entry.bps, 0);
        if (totalBps !== 10000) {
            ctx.addIssue({
                code: z.ZodIssueCode.custom,
                path: ['stakePayouts'],
                message: 'Stake payout shares must total 10000 bps'
            });
        }
    }
});

const joinFriendRoomSchema = z.object({
    spectator: z.boolean().default(false)
});

const matchmakingJoinSchema = z.object({
    mode: z.enum(MATCHMAKING_MODES),
    stakeAmount: z.number().int().min(0).optional(),
    region: trimmedString(40).optional(),
    themePackId: z.enum(THEME_PACK_IDS).optional()
}).superRefine((value, ctx) => {
    if (value.mode === 'gold_stake' && (!value.stakeAmount || value.stakeAmount <= 0)) {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['stakeAmount'],
            message: 'Gold stake matchmaking requires a positive stakeAmount'
        });
    }
    if (value.mode !== 'gold_stake' && value.stakeAmount && value.stakeAmount > 0) {
        ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: ['stakeAmount'],
            message: 'stakeAmount is only supported for gold_stake matchmaking'
        });
    }
});

const matchmakingLeaveSchema = z.object({
    queueTicketId: z.string().trim().min(1).optional()
});

const readySchema = z.object({
    ready: z.boolean(),
    seatIndex: z.number().int().min(0).max(7).optional()
});

const cancelRoomSchema = z.object({
    reason: z.string().trim().max(120).optional()
});

const reconnectSchema = z.object({
    lastKnownVersion: z.number().int().min(0).default(0)
});

const rematchSchema = z.object({
    vote: z.boolean()
});

const tablesQuerySchema = z.object({
    mode: z.enum(MATCHMAKING_MODES).optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20)
});

const leaderboardQuerySchema = z.object({
    period: z.enum(LEADERBOARD_PERIODS).default('alltime'),
    limit: z.coerce.number().int().min(1).max(100).default(50),
    offset: z.coerce.number().int().min(0).max(1000).default(0)
});

const themeEquipSchema = z.object({
    slot: z.literal('table').default('table')
});

const tutorialCompletionSchema = z.object({
    version: trimmedString(32)
});

const roomParamsSchema = z.object({
    roomId: objectIdSchema
});

const matchParamsSchema = z.object({
    matchId: objectIdSchema
});

const themeParamsSchema = z.object({
    themeId: z.enum(THEME_PACK_IDS)
});

const buildValidationError = (issues = []) => {
    const error = new Error('Validation failed');
    error.status = 400;
    error.code = 'VALIDATION_FAILED';
    error.details = issues.map((issue) => ({
        path: Array.isArray(issue.path) ? issue.path.join('.') : String(issue.path || ''),
        message: issue.message
    }));
    return error;
};

const validateColorClash = ({ body, params, query } = {}) => (req, _res, next) => {
    try {
        req.colorClashInput = {
            body: body ? body.parse(req.body || {}) : {},
            params: params ? params.parse(req.params || {}) : {},
            query: query ? query.parse(req.query || {}) : {}
        };
        next();
    } catch (error) {
        next(buildValidationError(error.issues || error.errors || []));
    }
};

module.exports = {
    GAME_ID,
    DEFAULT_REGION,
    DEFAULT_THEME_PACK_ID,
    LEADERBOARD_PERIODS,
    MATCHMAKING_MODES,
    RANKED_MIN_LEVEL,
    ROOM_TABLE_MODES,
    ROOM_VISIBILITIES,
    THEME_PACK_IDS,
    cancelRoomSchema,
    createFriendRoomSchema,
    joinFriendRoomSchema,
    leaderboardQuerySchema,
    matchmakingJoinSchema,
    matchmakingLeaveSchema,
    matchParamsSchema,
    readySchema,
    reconnectSchema,
    rematchSchema,
    roomParamsSchema,
    tablesQuerySchema,
    themeEquipSchema,
    themeParamsSchema,
    tutorialCompletionSchema,
    validateColorClash
};
