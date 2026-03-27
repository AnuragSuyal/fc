const express = require('express');
const router = express.Router();

const rc = require('../controllers/roomController');
const admin = require('../controllers/roomAdminController');
const mc = require('../controllers/messageController');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const { createRoomSchema, updateRoomSchema } = require('../utils/validation');
const optionalAuth = require('../middleware/optionalAuth');

// Discovery
router.get('/trending', optionalAuth, rc.getTrendingRooms);
router.get('/categories', optionalAuth, rc.getCategories);
router.get('/', optionalAuth, rc.getRooms);

// My rooms
router.get('/my-rooms', auth, rc.getMyRooms);

// Room details and chat history
router.get('/:id/messages', optionalAuth, (req, res, next) => {
  req.params.roomId = req.params.id;
  mc.getRoomMessages(req, res, next);
});
router.get('/:id', optionalAuth, rc.getRoomById);

// CRUD
router.post('/', auth, validate(createRoomSchema), rc.createRoom);
router.put('/:id', auth, validate(updateRoomSchema), rc.updateRoom);
router.delete('/:id', auth, rc.deleteRoom);

// Participation
router.post('/:id/join', auth, rc.joinRoom);
router.post('/:id/leave', auth, rc.leaveRoom);
router.post('/:id/token', auth, rc.getRoomToken);

// Seat management
router.post('/:id/seat', auth, rc.takeSeat);
router.delete('/:id/seat', auth, rc.leaveSeat);
router.post('/:id/seat/:seatIndex/lock', auth, admin.lockSeat);
router.post('/:id/seat/:seatIndex/unlock', auth, admin.unlockSeat);

// Moderation
router.post('/:id/mute/:userId', auth, rc.muteParticipant);
router.post('/:id/unmute/:userId', auth, rc.unmuteParticipant);
router.post('/:id/kick/:userId', auth, rc.kickParticipant);
router.post('/:id/ban/:userId', auth, admin.banParticipant);
router.delete('/:id/ban/:userId', auth, admin.unbanParticipant);
router.get('/:id/bans', auth, admin.getBans);
router.get('/:id/reports', auth, admin.getReports);

// Role management
router.post('/:id/promote/:userId', auth, admin.promoteParticipant);
router.post('/:id/demote/:userId', auth, admin.demoteParticipant);
router.post('/:id/cohost/:userId', auth, admin.assignCoHost);
router.delete('/:id/cohost/:userId', auth, admin.removeCoHost);
router.post('/:id/moderators/:userId', auth, admin.addModerator);
router.delete('/:id/moderators/:userId', auth, admin.removeModerator);
router.post('/:id/transfer-ownership/:userId', auth, admin.transferOwnership);

// Room features
router.post('/:id/announcement', auth, admin.setAnnouncement);
router.post('/:id/follow', auth, admin.followRoom);
router.delete('/:id/follow', auth, admin.unfollowRoom);
router.post('/:id/report', auth, admin.reportRoom);

module.exports = router;
