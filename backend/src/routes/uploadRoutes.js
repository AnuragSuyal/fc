const express = require('express');
const router = express.Router();
const uploadController = require('../controllers/uploadController');
const auth = require('../middleware/auth');

// Serve uploaded files (public)
router.get('/:filename', uploadController.serveFile);

// Upload routes (protected)
router.post('/image', auth, uploadController.uploadImage);
router.post('/avatar', auth, uploadController.uploadAvatar);
router.post('/audio', auth, uploadController.uploadAudio);

module.exports = router;





