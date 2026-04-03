const express = require('express');

const dragonPacketController = require('../controllers/dragonPacketController');
const auth = require('../middleware/auth');

const router = express.Router();

router.get('/history', auth, dragonPacketController.history);

module.exports = router;
