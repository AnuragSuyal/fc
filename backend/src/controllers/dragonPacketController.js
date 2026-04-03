const stripe = process.env.STRIPE_SECRET_KEY
    ? require('stripe')(process.env.STRIPE_SECRET_KEY)
    : null;

const User = require('../models/User');
const {
    buildPublicDragonPacketConfig,
    getDragonPacketConfig,
    getDragonPacketProductBySku
} = require('../config/dragonPacketConfig');
const {
    activateDragonPacketEvent,
    emitDragonPacketUserUpdate,
    getActiveDragonEvent,
    getDragonEventHistory,
    getDragonEventResult,
    getDragonPacketInventoryPayload,
    getDragonPacketProductsPayload,
    grantDragonPacketInventory,
    serializeDragonPacketInventory
} = require('../services/dragonPacketService');

exports.getProducts = async (req, res, next) => {
    try {
        const payload = await getDragonPacketProductsPayload(req.userId);
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.getInventory = async (req, res, next) => {
    try {
        const payload = await getDragonPacketInventoryPayload(req.userId);
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.purchase = async (req, res, next) => {
    try {
        const config = getDragonPacketConfig();
        if (!config.featureEnabled) {
            const error = new Error('Golden Dragon is temporarily unavailable.');
            error.code = 'DRAGON_DISABLED';
            error.status = 403;
            throw error;
        }

        const product = getDragonPacketProductBySku(req.body?.productSku);
        if (!product) {
            const error = new Error('Select a valid Golden Dragon packet.');
            error.code = 'INVALID_PRODUCT';
            error.status = 400;
            throw error;
        }

        const user = await User.findById(req.userId).select('coins gems');
        if (!user) {
            const error = new Error('User not found.');
            error.status = 404;
            throw error;
        }

        const requestedSource = String(req.body?.purchaseSource || '').trim().toLowerCase();
        const allowMockPurchase = config.allowMockPurchases === true &&
            (!stripe || requestedSource === 'mock');

        if (allowMockPurchase) {
            const inventoryItem = await grantDragonPacketInventory({
                userId: req.userId,
                product,
                purchaseSource: 'mock',
                metadata: {
                    simulated: true
                }
            });

            await emitDragonPacketUserUpdate({
                io: req.app.get('io'),
                userId: req.userId,
                type: 'inventory_updated'
            });

            return res.json({
                success: true,
                pendingCheckout: false,
                inventoryItem: serializeDragonPacketInventory(inventoryItem, product),
                config: buildPublicDragonPacketConfig()
            });
        }

        if (!stripe) {
            const error = new Error('Purchases are not configured yet.');
            error.code = 'PURCHASE_NOT_CONFIGURED';
            error.status = 503;
            throw error;
        }

        const successUrlBase = process.env.DRAGON_PACKET_SUCCESS_URL
            || process.env.FRONTEND_URL
            || 'https://friendcircle.local/golden-dragon';
        const cancelUrlBase = process.env.DRAGON_PACKET_CANCEL_URL
            || successUrlBase;

        const checkoutSession = await stripe.checkout.sessions.create({
            mode: 'payment',
            payment_method_types: ['card'],
            line_items: [
                {
                    quantity: 1,
                    price_data: {
                        currency: 'inr',
                        unit_amount: Number(product.priceInr || 0) * 100,
                        product_data: {
                            name: product.name,
                            description: `Golden Dragon packet with ${product.packetCoinAmount} coins`
                        }
                    }
                }
            ],
            success_url: `${successUrlBase}${successUrlBase.includes('?') ? '&' : '?'}goldenDragon=success&session_id={CHECKOUT_SESSION_ID}`,
            cancel_url: `${cancelUrlBase}${cancelUrlBase.includes('?') ? '&' : '?'}goldenDragon=cancelled`,
            metadata: {
                orderType: 'dragon_packet',
                userId: req.userId,
                productSku: product.sku,
                packageType: product.packageType,
                packetCoinAmount: String(product.packetCoinAmount),
                purchaseAmountInr: String(product.priceInr),
                currency: product.currency || 'INR'
            }
        });

        res.json({
            success: true,
            pendingCheckout: true,
            checkoutUrl: checkoutSession.url,
            checkoutSessionId: checkoutSession.id,
            product,
            config: buildPublicDragonPacketConfig()
        });
    } catch (error) {
        next(error);
    }
};

exports.activate = async (req, res, next) => {
    try {
        const result = await activateDragonPacketEvent({
            roomId: req.params.roomId || req.params.id,
            activatorUserId: req.userId,
            purchaseInventoryId: req.body?.purchaseInventoryId || '',
            productSku: req.body?.productSku || '',
            req,
            io: req.app.get('io'),
            redis: req.app.get('redis')
        });

        res.json(result);
    } catch (error) {
        next(error);
    }
};

exports.getActiveEvent = async (req, res, next) => {
    try {
        const payload = await getActiveDragonEvent({
            roomId: req.params.roomId || req.params.id,
            viewerUserId: req.userId
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.getResult = async (req, res, next) => {
    try {
        const payload = await getDragonEventResult({
            roomId: req.params.roomId || req.params.id,
            eventId: req.params.eventId,
            viewerUserId: req.userId
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};

exports.history = async (req, res, next) => {
    try {
        const payload = await getDragonEventHistory({
            userId: req.userId,
            view: req.query.view || 'all',
            roomId: req.query.roomId || req.query.room_id || '',
            status: req.query.status || '',
            dateFrom: req.query.dateFrom || req.query.date_from || '',
            dateTo: req.query.dateTo || req.query.date_to || '',
            page: req.query.page,
            limit: req.query.limit
        });
        res.json(payload);
    } catch (error) {
        next(error);
    }
};
