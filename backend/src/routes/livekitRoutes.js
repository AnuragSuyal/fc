const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const livekitController = require('../controllers/livekitController');

router.post('/token', auth, livekitController.generateToken);

module.exports = router;






