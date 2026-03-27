const express = require('express');
const router = express.Router();
const paymentController = require('../controllers/paymentController');
const livekitController = require('../controllers/livekitController');
const webhookController = require('../controllers/webhookController');

router.post('/stripe', paymentController.handleWebhook);
router.post('/cloudinary', webhookController.cloudinaryWebhook);
router.post('/livekit', livekitController.handleWebhook);

module.exports = router;






