const express = require('express');

const controller = require('../controllers/colorClashController');
const auth = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const {
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
} = require('../utils/colorClashValidation');

const router = express.Router();

router.use(auth);

router.get('/home', controller.getHome);
router.get('/tables', validateColorClash({ query: tablesQuerySchema }), controller.getTables);

router.post(
    '/rooms',
    idempotency({ keyPrefix: 'cc:rooms:create' }),
    validateColorClash({ body: createFriendRoomSchema }),
    controller.createRoom
);
router.post(
    '/rooms/:roomId/join',
    idempotency({ keyPrefix: 'cc:rooms:join' }),
    validateColorClash({ params: roomParamsSchema, body: joinFriendRoomSchema }),
    controller.joinRoom
);

router.post(
    '/matchmaking/join',
    idempotency({ keyPrefix: 'cc:mm:join' }),
    validateColorClash({ body: matchmakingJoinSchema }),
    controller.joinMatchmaking
);
router.post(
    '/matchmaking/leave',
    idempotency({ keyPrefix: 'cc:mm:leave' }),
    validateColorClash({ body: matchmakingLeaveSchema }),
    controller.leaveMatchmaking
);

router.post(
    '/rooms/:roomId/ready',
    idempotency({ keyPrefix: 'cc:rooms:ready' }),
    validateColorClash({ params: roomParamsSchema, body: readySchema }),
    controller.setReady
);
router.post(
    '/rooms/:roomId/cancel',
    idempotency({ keyPrefix: 'cc:rooms:cancel' }),
    validateColorClash({ params: roomParamsSchema, body: cancelRoomSchema }),
    controller.cancelRoom
);
router.get(
    '/rooms/:roomId/lobby',
    validateColorClash({ params: roomParamsSchema }),
    controller.getLobby
);

router.get(
    '/matches/:matchId/snapshot',
    validateColorClash({ params: matchParamsSchema }),
    controller.getMatchSnapshot
);
router.get(
    '/matches/:matchId/settlement',
    validateColorClash({ params: matchParamsSchema }),
    controller.getSettlementSummary
);
router.post(
    '/matches/:matchId/reconnect',
    idempotency({ keyPrefix: 'cc:matches:reconnect' }),
    validateColorClash({ params: matchParamsSchema, body: reconnectSchema }),
    controller.reconnectMatch
);
router.post(
    '/matches/:matchId/rematch',
    idempotency({ keyPrefix: 'cc:matches:rematch' }),
    validateColorClash({ params: matchParamsSchema, body: rematchSchema }),
    controller.voteRematch
);

router.get('/seasons/current', controller.getCurrentSeason);
router.get('/leaderboards', validateColorClash({ query: leaderboardQuerySchema }), controller.getLeaderboards);
router.post(
    '/themes/:themeId/equip',
    idempotency({ keyPrefix: 'cc:themes:equip' }),
    validateColorClash({ params: themeParamsSchema, body: themeEquipSchema }),
    controller.equipTheme
);
router.post(
    '/tutorial/complete',
    idempotency({ keyPrefix: 'cc:tutorial:complete' }),
    validateColorClash({ body: tutorialCompletionSchema }),
    controller.completeTutorial
);

module.exports = router;
