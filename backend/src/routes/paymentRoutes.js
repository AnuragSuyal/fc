const express = require('express');
const router = express.Router();
const paymentController = require('../controllers/paymentController');
const auth = require('../middleware/auth');

// Note: webhook does NOT use auth middleware because it's called by Stripe
router.post('/webhook', paymentController.handleWebhook);

// Add routes for creating checkout sessions here
// router.post('/create-checkout-session', auth, paymentController.createCheckoutSession);

module.exports = router;






