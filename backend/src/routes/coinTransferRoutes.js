const express = require('express');

const coinTransferController = require('../controllers/coinTransferController');
const auth = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const { coinTransferLimiter } = require('../middleware/rateLimit');
const validate = require('../middleware/validate');
const {
    coinTransferPreviewSchema,
    coinTransferSendSchema,
    coinTransferUnlockPurchaseSchema
} = require('../utils/validation');

const router = express.Router();

router.get('/eligibility', auth, coinTransferController.getEligibility);
router.post(
    '/unlock/purchase',
    auth,
    coinTransferLimiter,
    idempotency({ keyPrefix: 'coin-transfer:unlock:purchase' }),
    validate(coinTransferUnlockPurchaseSchema),
    coinTransferController.purchaseUnlock
);
router.post(
    '/preview',
    auth,
    coinTransferLimiter,
    validate(coinTransferPreviewSchema),
    coinTransferController.preview
);
router.post(
    '/send',
    auth,
    coinTransferLimiter,
    idempotency({ keyPrefix: 'coin-transfer:send' }),
    validate(coinTransferSendSchema),
    coinTransferController.send
);
router.get('/history', auth, coinTransferController.history);

module.exports = router;
