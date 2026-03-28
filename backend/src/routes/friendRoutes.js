const express = require('express');
const router = express.Router();
const friendController = require('../controllers/friendController');
const auth = require('../middleware/auth');

// All friend routes require authentication
router.use(auth);

// Friend management
router.get('/', friendController.getFriends);
router.get('/requests', friendController.getFriendRequests);
router.get('/requests/overview', friendController.getFriendRequestOverview);
router.get('/suggestions', friendController.getFriendSuggestions);
router.get('/blocked', friendController.getBlockedUsers);

// Friend requests
router.post('/request/:userId', friendController.sendFriendRequest);
router.post('/accept/:userId', friendController.acceptFriendRequest);
router.post('/reject/:userId', friendController.rejectFriendRequest);
router.delete('/:userId', friendController.removeFriend);

// Block/unblock
router.post('/block/:userId', friendController.blockUser);
router.delete('/block/:userId', friendController.unblockUser);

module.exports = router;





