const express = require('express');
const router  = express.Router();
const mc      = require('../controllers/messageController');
const auth    = require('../middleware/auth');
const validate = require('../middleware/validate');
const { sendDirectMessageSchema, sendRoomMessageSchema } = require('../utils/validation');

// Direct messages
router.get('/conversations',       auth, mc.getConversations);
router.get('/dm/:userId',          auth, mc.getDirectMessages);
router.post('/dm',                 auth, validate(sendDirectMessageSchema), mc.sendDirectMessage);
router.post('/dm/:userId/read',    auth, mc.markAsRead);
router.get('/unread-count',        auth, mc.getUnreadCount);

// Room messages
router.get('/room/:roomId',        auth, mc.getRoomMessages);
router.post('/room',               auth, validate(sendRoomMessageSchema), mc.sendRoomMessage);

// Group messages
router.get('/group/:groupId',      auth, mc.getGroupMessages);
router.post('/group',              auth, mc.sendGroupMessage);

// Reactions & deletion
router.post('/:messageId/react',   auth, mc.addReaction);
router.delete('/:messageId',       auth, mc.deleteMessage);

module.exports = router;


