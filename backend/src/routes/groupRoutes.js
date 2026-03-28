const express = require('express');
const router = express.Router();
const groupController = require('../controllers/groupController');
const auth = require('../middleware/auth');
const optionalAuth = require('../middleware/optionalAuth');

const validate = require('../middleware/validate');
const { createGroupSchema } = require('../utils/validation');

// Protected routes
router.get('/my-groups', auth, groupController.getMyGroups);
router.get('/invites', auth, groupController.getMyInvites);
router.get('/discover', auth, groupController.getDiscoverGroups);
router.post('/', auth, validate(createGroupSchema), groupController.createGroup);

// Public routes
router.get('/leaderboard', groupController.getLeaderboard);
router.get('/:id', optionalAuth, groupController.getGroupById);

// Member actions
router.post('/:id/join', auth, groupController.joinGroup);
router.post('/:id/leave', auth, groupController.leaveGroup);
router.post('/:id/treasure', auth, groupController.claimTreasure);
router.post('/:id/invite', auth, groupController.inviteFriends);
router.post('/:id/invitations/accept', auth, groupController.acceptInvite);
router.post('/:id/invitations/reject', auth, groupController.rejectInvite);
router.post('/:id/requests/:userId/approve', auth, groupController.approveJoinRequest);
router.post('/:id/requests/:userId/reject', auth, groupController.rejectJoinRequest);
router.put('/:id/members/:userId/role', auth, groupController.updateMemberRole);
router.delete('/:id/members/:userId', auth, groupController.removeMember);
router.put('/:id', auth, validate(createGroupSchema.partial()), groupController.updateGroup);
router.delete('/:id', auth, groupController.deleteGroup);

module.exports = router;




