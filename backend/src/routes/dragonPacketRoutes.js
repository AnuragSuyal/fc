const express = require('express');

const dragonPacketController = require('../controllers/dragonPacketController');
const auth = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const { dragonPacketLimiter } = require('../middleware/rateLimit');
const validate = require('../middleware/validate');
const {
    dragonPacketPurchaseSchema
} = require('../utils/validation');

const router = express.Router();

router.get('/products', auth, dragonPacketController.getProducts);
router.get('/inventory', auth, dragonPacketController.getInventory);
router.post(
    '/purchase',
    auth,
    dragonPacketLimiter,
    idempotency({ keyPrefix: 'dragon-packet:purchase' }),
    validate(dragonPacketPurchaseSchema),
    dragonPacketController.purchase
);
router.get('/history', auth, dragonPacketController.history);

module.exports = router;
