const express = require('express');
const router = express.Router();
const profileController = require('../controllers/profileController');
const auth = require('../middleware/auth');

const validate = require('../middleware/validate');
const { updateProfileSchema } = require('../utils/validation');

// Public routes
router.get('/me', auth, profileController.getMyProfile);
router.get('/:userId', profileController.getProfile);
router.get('/:userId/badges', profileController.getBadges);
router.get('/:userId/game-stats', profileController.getGameStats);
router.get('/:userId/visitors', profileController.getVisitors);

// Protected routes
router.put('/', auth, validate(updateProfileSchema), profileController.updateProfile);
router.post('/:userId/visit', auth, profileController.addVisitor);
router.post('/game-stats/update', auth, profileController.updateGameStats);
router.post('/badges/add', auth, profileController.addBadge);

module.exports = router;






