const express = require('express');
const router = express.Router();
const settingsController = require('../controllers/settingsController');
const auth = require('../middleware/auth');

// All settings routes require authentication
router.use(auth);

// Get settings
router.get('/', settingsController.getSettings);

// Update various settings
router.put('/notifications', settingsController.updateNotifications);
router.put('/privacy', settingsController.updatePrivacy);
router.put('/quiet-hours', settingsController.updateQuietHours);
router.put('/language', settingsController.updateLanguage);
router.put('/profile', settingsController.updateProfile);
router.post('/change-password', settingsController.changePassword);
router.delete('/account', settingsController.deleteAccount);

module.exports = router;






