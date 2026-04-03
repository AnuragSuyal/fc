const express = require('express');
const router  = express.Router();
const vipController = require('../controllers/vipController');
const auth    = require('../middleware/auth');
const validate = require('../middleware/validate');
const { purchaseVipSchema } = require('../utils/validation');

router.get('/levels',           vipController.getVipLevels);
router.get('/status',     auth,  vipController.getVipStatus);
router.post('/purchase',  auth,  validate(purchaseVipSchema), vipController.purchaseVip);
router.post('/cancel',    auth,  vipController.cancelVip);
router.post('/restore',   auth,  vipController.restoreVip);
router.post('/monthly-reward', auth, vipController.claimVipMonthlyReward);
router.post('/daily-bonus', auth, vipController.claimVipDailyBonus);

module.exports = router;

