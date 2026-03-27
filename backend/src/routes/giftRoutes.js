const express = require('express');
const router = express.Router();
const giftController = require('../controllers/giftController');
const auth = require('../middleware/auth');
const validateGift = require('../middleware/validateGift');
const { giftLimiter } = require('../middleware/rateLimit');
const idempotency = require('../middleware/idempotency');
const optionalAuth = require('../middleware/optionalAuth');

// Public routes
router.get('/catalog', giftController.getGiftCatalog);
router.get('/leaderboard', optionalAuth, giftController.getGiftLeaderboard);

// Protected routes
router.post('/send', auth, giftLimiter, idempotency({ keyPrefix: 'gift:send' }), validateGift, giftController.sendGift);
router.get('/history', auth, giftController.getGiftHistory);
router.get('/achievements', auth, giftController.getGiftAchievements);

// Get by ID last
router.get('/:id', giftController.getGiftById);

// Admin route (one-time use)
router.post('/seed', auth, giftController.seedGifts); // TODO: Add admin middleware

module.exports = router;






