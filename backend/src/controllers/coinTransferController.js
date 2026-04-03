const stripe = process.env.STRIPE_SECRET_KEY
    ? require('stripe')(process.env.STRIPE_SECRET_KEY)
    : null;

const Transaction = require('../models/Transaction');
const User = require('../models/User');
const {
    buildPublicCoinTransferConfig,
    getCoinTransferConfig
} = require('../config/coinTransferConfig');
const {
    executeCoinTransfer,
    getCoinTransferEligibility,
    getCoinTransferHistory,
    previewCoinTransfer
} = require('../services/coinTransferService');
const {
    activatePremiumEntitlement,
    getPremiumEntitlement,
    isPremiumEntitlementActive,
    serializePremiumEntitlement
} = require('../services/premiumEntitlementService');

const emitUnlockUpdate = (req, entitlement, { unlocked = true, source = 'coin_transfer_unlock' } = {}) => {
    const io = req.app.get('io');
    if (!io || !entitlement?.userId) {
        return;
    }

    io.to(`user:${entitlement.userId.toString()}`).emit('coin_transfer:updated', {
        type: 'coin_transfer_unlock_updated',
        source,
        unlocked,
        entitlement: serializePremiumEntitlement(entitlement),
        config: buildPublicCoinTransferConfig()
    });
};

exports.getEligibility = async (req, res, next) => {
    try {
        const eligibility = await getCoinTransferEligibility({
            senderUserId: req.userId,
            receiverUserId: req.query.receiverUserId || req.query.receiver_user_id || null,
            chatId: req.query.chatId || req.query.chat_id || ''
        });

        res.json(eligibility);
    } catch (error) {
        next(error);
    }
};

exports.purchaseUnlock = async (req, res, next) => {
    try {
        const config = getCoinTransferConfig();
        if (!config.featureEnabled) {
            const error = new Error('Coin transfers are temporarily unavailable.');
            error.code = 'FEATURE_DISABLED';
            error.status = 403;
            throw error;
        }

        const existingEntitlement = await getPremiumEntitlement({
            userId: req.userId,
            entitlementKey: config.unlockEntitlementKey
        });
        if (isPremiumEntitlementActive(existingEntitlement)) {
            return res.json({
                success: true,
                unlocked: true,
                entitlement: serializePremiumEntitlement(existingEntitlement),
                config: buildPublicCoinTransferConfig()
            });
        }

        const user = await User.findById(req.userId).select('coins gems');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const requestedSource = String(req.body?.purchaseSource || '').trim().toLowerCase();
        const allowMockPurchase = config.allowMockUnlockPurchases === true &&
            (!stripe || requestedSource === 'mock');

        if (allowMockPurchase) {
            const entitlement = await activatePremiumEntitlement({
                userId: req.userId,
                entitlementKey: config.unlockEntitlementKey,
                purchaseSource: 'mock',
                purchaseAmountInr: config.unlockPriceInr,
                currency: config.unlockCurrency,
                metadata: {
                    productCode: config.unlockProductCode,
                    simulated: true
                }
            });

            await Transaction.create({
                userId: req.userId,
                type: 'coin_transfer_unlock_purchase',
                amount: {
                    realMoney: config.unlockPriceInr
                },
                balanceBefore: {
                    coins: Number(user.coins || 0),
                    gems: Number(user.gems || 0)
                },
                balanceAfter: {
                    coins: Number(user.coins || 0),
                    gems: Number(user.gems || 0)
                },
                currencyType: 'real_money',
                reference: {
                    entitlementKey: config.unlockEntitlementKey,
                    productId: config.unlockProductCode
                },
                metadata: {
                    currency: config.unlockCurrency,
                    purchaseSource: 'mock'
                },
                paymentMethod: 'mock',
                status: 'completed',
                description: 'Unlocked Coin Transfers',
                completedAt: new Date()
            });

            emitUnlockUpdate(req, entitlement, {
                unlocked: true,
                source: 'coin_transfer_unlock_purchase'
            });

            return res.json({
                success: true,
                unlocked: true,
                mockActivated: true,
                entitlement: serializePremiumEntitlement(entitlement),
                config: buildPublicCoinTransferConfig()
            });
        }

        if (!stripe) {
            const error = new Error('Purchases are not configured yet.');
            error.code = 'UNLOCK_PAYMENT_NOT_CONFIGURED';
            error.status = 503;
            throw error;
        }

        const successUrlBase = process.env.COIN_TRANSFER_UNLOCK_SUCCESS_URL
            || process.env.FRONTEND_URL
            || 'https://friendcircle.local/coin-transfer-unlock';
        const cancelUrlBase = process.env.COIN_TRANSFER_UNLOCK_CANCEL_URL
            || successUrlBase;

        const checkoutSession = await stripe.checkout.sessions.create({
            mode: 'payment',
            payment_method_types: ['card'],
            line_items: [
                {
                    quantity: 1,
                    price_data: {
                        currency: 'inr',
                        unit_amount: Number(config.unlockPriceInr || 0) * 100,
                        product_data: {
                            name: 'Unlock Coin Transfers',
                            description: 'Send coins directly to friends in private chat'
                        }
                    }
                }
            ],
            success_url: `${successUrlBase}${successUrlBase.includes('?') ? '&' : '?'}coinTransferUnlock=success&session_id={CHECKOUT_SESSION_ID}`,
            cancel_url: `${cancelUrlBase}${cancelUrlBase.includes('?') ? '&' : '?'}coinTransferUnlock=cancelled`,
            metadata: {
                orderType: 'coin_transfer_unlock',
                userId: req.userId,
                entitlementKey: config.unlockEntitlementKey,
                productId: config.unlockProductCode,
                purchaseAmountInr: String(config.unlockPriceInr),
                currency: config.unlockCurrency
            }
        });

        res.json({
            success: true,
            unlocked: false,
            pendingCheckout: true,
            checkoutUrl: checkoutSession.url,
            checkoutSessionId: checkoutSession.id,
            config: buildPublicCoinTransferConfig()
        });
    } catch (error) {
        next(error);
    }
};

exports.preview = async (req, res, next) => {
    try {
        const preview = await previewCoinTransfer({
            senderUserId: req.userId,
            receiverUserId: req.body.receiverUserId,
            chatId: req.body.chatId || '',
            amount: req.body.amount
        });

        res.json(preview);
    } catch (error) {
        next(error);
    }
};

exports.send = async (req, res, next) => {
    try {
        const result = await executeCoinTransfer({
            senderUserId: req.userId,
            receiverUserId: req.body.receiverUserId,
            chatId: req.body.chatId || '',
            amount: req.body.amount,
            idempotencyKey: req.idempotencyKey || req.body?.idempotencyKey || '',
            req,
            io: req.app.get('io'),
            redis: req.app.get('redis')
        });

        res.json(result);
    } catch (error) {
        next(error);
    }
};

exports.history = async (req, res, next) => {
    try {
        const history = await getCoinTransferHistory({
            userId: req.userId,
            view: req.query.view || req.query.type || 'all',
            status: req.query.status || '',
            chatId: req.query.chatId || req.query.chat_id || '',
            dateFrom: req.query.dateFrom || req.query.date_from || '',
            dateTo: req.query.dateTo || req.query.date_to || '',
            page: req.query.page,
            limit: req.query.limit
        });

        res.json(history);
    } catch (error) {
        next(error);
    }
};
