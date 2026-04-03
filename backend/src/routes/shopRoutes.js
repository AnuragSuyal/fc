const express = require('express');

const auth = require('../middleware/auth');
const idempotency = require('../middleware/idempotency');
const shopController = require('../controllers/shopController');

const router = express.Router();

router.use(auth);

router.get('/home', shopController.getShopHome);
router.get('/catalog', shopController.getCatalog);
router.get('/inventory', shopController.getInventory);

router.post(
    '/items/:itemId/purchase',
    idempotency({ keyPrefix: 'shop:purchase' }),
    shopController.purchaseItem
);
router.post(
    '/items/:itemId/use',
    idempotency({ keyPrefix: 'shop:use' }),
    shopController.useItem
);
router.post('/items/:itemId/equip', shopController.equipItem);
router.post('/items/:itemId/unequip', shopController.unequipItem);
router.post('/items/:itemId/wishlist', shopController.toggleWishlist);
router.post('/items/:itemId/view', shopController.viewItem);
router.post('/inventory/:itemId/favorite', shopController.favoriteInventoryItem);

module.exports = router;
