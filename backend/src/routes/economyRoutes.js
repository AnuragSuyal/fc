const express = require('express');
const router  = express.Router();
const ec      = require('../controllers/economyController');
const auth    = require('../middleware/auth');

router.get('/stats',           auth, ec.getUserStats);
router.get('/balance',         auth, ec.getBalance);
router.get('/conversion-rates', ec.getConversionRates);
router.get('/quests/daily',    auth, (req, res, next) => {
    req.query = { ...req.query, type: 'daily' };
    ec.getDailyQuests(req, res, next);
});
router.get('/quests/weekly',   auth, (req, res, next) => {
    req.query = { ...req.query, type: 'weekly' };
    ec.getDailyQuests(req, res, next);
});
router.get('/quests',          auth, ec.getDailyQuests);
router.post('/quests/progress', auth, ec.updateQuestProgress);
router.post('/quests/update',  auth, ec.updateQuestProgress);
router.post('/quests/claim',   auth, ec.claimQuestReward);
router.post('/daily-reward',   auth, ec.claimDailyReward);
router.post('/purchase',       auth, ec.purchase);
router.get('/transactions',    auth, ec.getTransactions);

module.exports = router;

