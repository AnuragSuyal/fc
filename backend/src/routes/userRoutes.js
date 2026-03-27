const express = require('express');
const router = express.Router();
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const { updateUserSchema } = require('../utils/validation');
const userController = require('../controllers/userController');
const friendController = require('../controllers/friendController');

// All user routes require authentication
router.use(auth);

// Search
router.get('/search', userController.searchUsers);

// Profile
router.get('/:id', userController.getUserById);
router.put('/:id', validate(updateUserSchema), userController.updateUser);

// Friend actions
router.post('/:userId/friend', friendController.sendFriendRequest);

// Block actions
router.post('/:userId/block', friendController.blockUser);

module.exports = router;






