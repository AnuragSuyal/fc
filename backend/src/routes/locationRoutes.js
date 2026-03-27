const express = require('express');
const router = express.Router();
const locationController = require('../controllers/locationController');
const auth = require('../middleware/auth');

const validate = require('../middleware/validate');
const { updateLocationSchema } = require('../utils/validation');

// All location routes require authentication
router.use(auth);

router.post('/update', validate(updateLocationSchema), locationController.updateLocation);
router.get('/nearby', locationController.getNearbyUsers);
router.post('/disable', locationController.disableLocationSharing);
router.get('/status', locationController.getLocationStatus);

module.exports = router;






