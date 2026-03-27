const express = require('express');
const router  = express.Router();
const wc      = require('../controllers/weddingController');
const auth    = require('../middleware/auth');

router.get('/rings',            wc.getRings);
router.get('/rankings',         wc.getCoupleRankings);
router.get('/me',         auth, wc.getMyWedding);
router.post('/propose',   auth, wc.propose);
router.post('/:weddingId/accept', auth, wc.acceptProposal);
router.post('/:weddingId/reject', auth, wc.rejectProposal);
router.post('/:weddingId/bless',  auth, wc.addBlessing);
router.delete('/divorce',  auth, wc.divorce);

module.exports = router;


