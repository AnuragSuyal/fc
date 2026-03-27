const express  = require('express');
const router   = express.Router();
const rc       = require('../controllers/rankingController');
const optionalAuth = require('../middleware/optionalAuth');

router.use(optionalAuth);

router.get('/gifts',       rc.getGiftRankings);
router.get('/charm',       rc.getCharmRankings);
router.get('/wealth',      rc.getWealthRankings);
router.get('/games/:gameType', rc.getGameRankings);
router.get('/overall',     rc.getOverallRankings);
router.get('/rooms/active', rc.getActiveRoomRankings);

module.exports = router;


