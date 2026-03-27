const express = require('express');
const router = express.Router();
const groupController = require('../controllers/groupController');
const auth = require('../middleware/auth');

const validate = require('../middleware/validate');
const { createGroupSchema } = require('../utils/validation');

// Protected routes
router.get('/my-groups', auth, groupController.getMyGroups);
router.get('/discover', auth, groupController.getDiscoverGroups);
router.post('/', auth, validate(createGroupSchema), groupController.createGroup);

// Public routes
router.get('/leaderboard', groupController.getLeaderboard);
router.get('/:id', groupController.getGroupById);

// Member actions
router.post('/:id/join', auth, groupController.joinGroup);
router.post('/:id/leave', auth, groupController.leaveGroup);
router.post('/:id/treasure', auth, groupController.claimTreasure);
router.put('/:id', auth, validate(createGroupSchema.partial()), groupController.updateGroup);
router.delete('/:id', auth, groupController.deleteGroup);

module.exports = router;






