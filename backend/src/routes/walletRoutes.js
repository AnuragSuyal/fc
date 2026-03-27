const express = require('express');
const router = express.Router();
const walletController = require('../controllers/walletController');
const auth = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');

// Shop routes (public)
router.get('/shop/coins', walletController.getCoinPacks);
router.get('/shop/gems', walletController.getGemPacks);
router.get('/shop/offers', walletController.getSpecialOffers);

// Protected routes
router.get('/balance', auth, walletController.getBalance);
router.get('/transactions', auth, walletController.getTransactions);
router.post('/purchase/coins', auth, idempotency({ keyPrefix: 'wallet:purchase:coins' }), walletController.purchaseCoins);
router.post('/purchase/gems', auth, idempotency({ keyPrefix: 'wallet:purchase:gems' }), walletController.purchaseGems);
router.post('/convert', auth, idempotency({ keyPrefix: 'wallet:convert' }), walletController.convertCoinsToGems);

module.exports = router;






