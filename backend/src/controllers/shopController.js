const {
    buildInventory,
    buildShopHome,
    equipInventoryItem,
    purchaseCatalogItem,
    recordItemView,
    setInventoryFavorite,
    toggleWishlistItem,
    unequipInventoryItem,
    useInventoryItem
} = require('../services/shopInventoryService');

exports.getShopHome = async (req, res, next) => {
    try {
        res.json(await buildShopHome({ userId: req.userId }));
    } catch (error) {
        next(error);
    }
};

exports.getCatalog = async (req, res, next) => {
    try {
        const home = await buildShopHome({ userId: req.userId });
        const category = String(req.query.category || 'all').trim();
        const items = category === 'all'
            ? home.catalog
            : home.catalog.filter((item) => item.itemCategory === category);
        res.json({
            categories: home.categories,
            items
        });
    } catch (error) {
        next(error);
    }
};

exports.getInventory = async (req, res, next) => {
    try {
        res.json(await buildInventory({ userId: req.userId }));
    } catch (error) {
        next(error);
    }
};

exports.purchaseItem = async (req, res, next) => {
    try {
        res.json(await purchaseCatalogItem({
            userId: req.userId,
            itemId: req.params.itemId,
            idempotencyKey: req.idempotencyKey,
            io: req.app.get('io')
        }));
    } catch (error) {
        next(error);
    }
};

exports.useItem = async (req, res, next) => {
    try {
        res.json(await useInventoryItem({
            userId: req.userId,
            itemId: req.params.itemId,
            idempotencyKey: req.idempotencyKey,
            io: req.app.get('io')
        }));
    } catch (error) {
        next(error);
    }
};

exports.equipItem = async (req, res, next) => {
    try {
        res.json(await equipInventoryItem({
            userId: req.userId,
            itemId: req.params.itemId,
            io: req.app.get('io')
        }));
    } catch (error) {
        next(error);
    }
};

exports.unequipItem = async (req, res, next) => {
    try {
        res.json(await unequipInventoryItem({
            userId: req.userId,
            itemId: req.params.itemId,
            io: req.app.get('io')
        }));
    } catch (error) {
        next(error);
    }
};

exports.toggleWishlist = async (req, res, next) => {
    try {
        res.json(await toggleWishlistItem({
            userId: req.userId,
            itemId: req.params.itemId
        }));
    } catch (error) {
        next(error);
    }
};

exports.favoriteInventoryItem = async (req, res, next) => {
    try {
        res.json(await setInventoryFavorite({
            userId: req.userId,
            itemId: req.params.itemId,
            favorited: req.body?.favorited === true
        }));
    } catch (error) {
        next(error);
    }
};

exports.viewItem = async (req, res, next) => {
    try {
        res.json(await recordItemView({
            userId: req.userId,
            itemId: req.params.itemId
        }));
    } catch (error) {
        next(error);
    }
};
