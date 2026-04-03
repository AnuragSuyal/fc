const stripe = process.env.STRIPE_SECRET_KEY
    ? require('stripe')(process.env.STRIPE_SECRET_KEY)
    : null;
const mongoose = require('mongoose');

const PaymentEvent = require('../models/PaymentEvent');
const PremiumEntitlement = require('../models/PremiumEntitlement');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const {
    getCoinTransferConfig
} = require('../config/coinTransferConfig');
const {
    emitDragonPacketUserUpdate,
    grantDragonPacketInventory,
    refundDragonPacketPurchaseByPaymentIntent
} = require('../services/dragonPacketService');
const {
    activatePremiumEntitlement,
    revokePremiumEntitlement,
    serializePremiumEntitlement
} = require('../services/premiumEntitlementService');

const emitCoinTransferUnlockUpdate = (app, entitlement, { unlocked, source }) => {
    const io = app?.get('io');
    if (!io || !entitlement?.userId) {
        return;
    }

    io.to(`user:${entitlement.userId.toString()}`).emit('coin_transfer:updated', {
        type: 'coin_transfer_unlock_updated',
        unlocked,
        source,
        entitlement: serializePremiumEntitlement(entitlement)
    });
};

const resolveWalletBalance = (user) => ({
    coins: Number(user?.coins || 0),
    gems: Number(user?.gems || 0)
});

const processWalletPurchaseSession = async ({ checkoutSession, mongoSession }) => {
    const userId = checkoutSession.metadata?.userId;
    const coins = Number.parseInt(checkoutSession.metadata?.coins, 10) || 0;
    const gems = Number.parseInt(checkoutSession.metadata?.gems, 10) || 0;

    const user = await User.findById(userId).session(mongoSession);
    if (!user) {
        throw new Error('User not found');
    }

    const balanceBefore = resolveWalletBalance(user);
    user.coins = Number(user.coins || 0) + coins;
    user.gems = Number(user.gems || 0) + gems;
    await user.save({ session: mongoSession });

    await Transaction.create([{
        userId,
        type: 'purchase',
        amount: { coins, gems },
        balanceBefore,
        balanceAfter: resolveWalletBalance(user),
        description: `Stripe Purchase: ${checkoutSession.amount_total / 100} ${checkoutSession.currency}`,
        status: 'completed',
        reference: {
            stripeSessionId: checkoutSession.id,
            paymentIntentId: checkoutSession.payment_intent || ''
        },
        paymentMethod: 'stripe',
        completedAt: new Date()
    }], { session: mongoSession });

    return {
        userId,
        postCommit: null
    };
};

const processCoinTransferUnlockSession = async ({ checkoutSession, mongoSession, app }) => {
    const config = getCoinTransferConfig();
    const userId = checkoutSession.metadata?.userId;
    const user = await User.findById(userId).select('coins gems').session(mongoSession);
    if (!user) {
        throw new Error('User not found');
    }

    const amountInr = Number.parseInt(
        checkoutSession.metadata?.purchaseAmountInr,
        10
    ) || Math.round(Number(checkoutSession.amount_total || 0) / 100);

    const entitlement = await activatePremiumEntitlement({
        userId,
        entitlementKey: config.unlockEntitlementKey,
        purchaseSource: 'stripe',
        purchaseAmountInr: amountInr,
        currency: String(checkoutSession.metadata?.currency || checkoutSession.currency || config.unlockCurrency).toUpperCase(),
        metadata: {
            stripeSessionId: checkoutSession.id,
            paymentIntentId: checkoutSession.payment_intent || '',
            productId: checkoutSession.metadata?.productId || config.unlockProductCode
        },
        session: mongoSession
    });

    await Transaction.create([{
        userId,
        type: 'coin_transfer_unlock_purchase',
        amount: {
            realMoney: amountInr
        },
        balanceBefore: resolveWalletBalance(user),
        balanceAfter: resolveWalletBalance(user),
        currencyType: 'real_money',
        description: 'Unlocked Coin Transfers',
        status: 'completed',
        reference: {
            stripeSessionId: checkoutSession.id,
            paymentIntentId: checkoutSession.payment_intent || '',
            entitlementKey: config.unlockEntitlementKey,
            productId: config.unlockProductCode
        },
        metadata: {
            currency: String(checkoutSession.currency || 'inr').toUpperCase(),
            purchaseSource: 'stripe'
        },
        paymentMethod: 'stripe',
        completedAt: new Date()
    }], { session: mongoSession });

    return {
        userId,
        postCommit: () => emitCoinTransferUnlockUpdate(app, entitlement, {
            unlocked: true,
            source: 'coin_transfer_unlock_purchase'
        })
    };
};

const processDragonPacketPurchaseSession = async ({ checkoutSession, mongoSession, app }) => {
    const userId = checkoutSession.metadata?.userId;
    const productSku = checkoutSession.metadata?.productSku;
    const user = await User.findById(userId).select('coins gems').session(mongoSession);
    if (!user) {
        throw new Error('User not found');
    }

    const inventoryItem = await grantDragonPacketInventory({
        userId,
        product: productSku,
        purchaseSource: 'stripe',
        paymentReference: {
            stripeSessionId: checkoutSession.id || '',
            checkoutSessionId: checkoutSession.id || '',
            paymentIntentId: checkoutSession.payment_intent || ''
        },
        metadata: {
            packetCoinAmount: Number.parseInt(checkoutSession.metadata?.packetCoinAmount, 10) || 0,
            purchaseAmountInr: Number.parseInt(checkoutSession.metadata?.purchaseAmountInr, 10) || 0,
            packageType: checkoutSession.metadata?.packageType || ''
        },
        session: mongoSession
    });

    return {
        userId,
        postCommit: () => emitDragonPacketUserUpdate({
            io: app?.get('io'),
            userId,
            type: 'inventory_updated',
            inventoryItemId: inventoryItem?._id?.toString?.() || ''
        })
    };
};

const processCheckoutSession = async ({ checkoutSession, eventId, app }) => {
    const mongoSession = await mongoose.startSession();
    try {
        let outcome = null;
        await mongoSession.withTransaction(async () => {
            const existingEvent = await PaymentEvent.findOne({ eventId }).session(mongoSession);
            if (existingEvent) {
                outcome = { duplicate: true, postCommit: null };
                return;
            }

            const orderType = String(checkoutSession.metadata?.orderType || '').trim().toLowerCase();
            if (orderType === 'coin_transfer_unlock') {
                outcome = await processCoinTransferUnlockSession({ checkoutSession, mongoSession, app });
            } else if (orderType === 'dragon_packet') {
                outcome = await processDragonPacketPurchaseSession({ checkoutSession, mongoSession, app });
            } else {
                outcome = await processWalletPurchaseSession({ checkoutSession, mongoSession });
            }

            await PaymentEvent.create([{
                eventId,
                type: 'checkout.session.completed',
                userId: outcome.userId || null,
                amount: checkoutSession.amount_total,
                currency: checkoutSession.currency,
                status: 'processed'
            }], { session: mongoSession });
        });

        if (outcome?.postCommit) {
            await outcome.postCommit();
        }
    } catch (error) {
        console.error(`Webhook checkout.session.completed failed for ${eventId}:`, error);
    } finally {
        await mongoSession.endSession();
    }
};

const processRefundEvent = async ({ charge, eventId, app }) => {
    const mongoSession = await mongoose.startSession();
    try {
        let outcome = null;
        await mongoSession.withTransaction(async () => {
            const existingEvent = await PaymentEvent.findOne({ eventId }).session(mongoSession);
            if (existingEvent) {
                outcome = { duplicate: true, postCommit: null };
                return;
            }

            const paymentIntentId = String(charge.payment_intent || '').trim();
            const refundedDragonItems = await refundDragonPacketPurchaseByPaymentIntent({
                paymentIntentId,
                chargeId: charge.id || '',
                session: mongoSession
            });

            if (refundedDragonItems.length > 0) {
                const userIds = [...new Set(refundedDragonItems
                    .map((item) => item.userId?.toString?.() || item.userId?.toString?.() || '')
                    .filter(Boolean))];
                const users = await User.find({
                    _id: { $in: userIds }
                }).select('coins gems').session(mongoSession);
                const usersById = new Map(users.map((user) => [user._id.toString(), user]));

                for (const item of refundedDragonItems) {
                    const userId = item.userId?.toString?.() || item.userId?.toString?.() || '';
                    const user = usersById.get(userId);
                    if (!user) {
                        continue;
                    }

                    await Transaction.create([{
                        userId,
                        type: 'dragon_packet_purchase_refund',
                        amount: {
                            realMoney: -Math.abs(Number(item.purchasePriceInr || 0))
                        },
                        balanceBefore: resolveWalletBalance(user),
                        balanceAfter: resolveWalletBalance(user),
                        currencyType: 'real_money',
                        description: `Refunded ${item.productSku || 'Golden Dragon'} purchase`,
                        status: 'completed',
                        reference: {
                            paymentIntentId,
                            dragonPacketInventoryId: item._id,
                            productId: item.productSku || ''
                        },
                        metadata: {
                            chargeId: charge.id || '',
                            currency: String(item.currency || charge.currency || 'INR').toUpperCase(),
                            inventoryStatus: item.inventoryStatus || ''
                        },
                        paymentMethod: 'stripe',
                        completedAt: new Date()
                    }], { session: mongoSession });
                }

                await PaymentEvent.create([{
                    eventId,
                    type: 'charge.refunded',
                    userId: refundedDragonItems[0]?.userId || null,
                    amount: charge.amount_refunded || charge.amount || 0,
                    currency: charge.currency,
                    status: 'processed'
                }], { session: mongoSession });

                outcome = {
                    postCommit: async () => {
                        await Promise.all(userIds.map((userId) => emitDragonPacketUserUpdate({
                            io: app?.get('io'),
                            userId,
                            type: 'inventory_updated'
                        })));
                    }
                };
                return;
            }

            const config = getCoinTransferConfig();
            const entitlement = await PremiumEntitlement.findOne({
                entitlementKey: config.unlockEntitlementKey,
                status: 'active',
                'metadata.paymentIntentId': paymentIntentId
            }).session(mongoSession);

            if (!entitlement) {
                await PaymentEvent.create([{
                    eventId,
                    type: 'charge.refunded',
                    amount: charge.amount_refunded || charge.amount || 0,
                    currency: charge.currency,
                    status: 'processed'
                }], { session: mongoSession });
                outcome = { postCommit: null };
                return;
            }

            const user = await User.findById(entitlement.userId).select('coins gems').session(mongoSession);
            const updatedEntitlement = await revokePremiumEntitlement({
                userId: entitlement.userId,
                entitlementKey: config.unlockEntitlementKey,
                status: 'refunded',
                metadata: {
                    paymentIntentId,
                    chargeId: charge.id || ''
                },
                session: mongoSession
            });

            if (user) {
                await Transaction.create([{
                    userId: entitlement.userId,
                    type: 'coin_transfer_unlock_refund',
                    amount: {
                        realMoney: -Math.round(Number(charge.amount_refunded || charge.amount || 0) / 100)
                    },
                    balanceBefore: resolveWalletBalance(user),
                    balanceAfter: resolveWalletBalance(user),
                    currencyType: 'real_money',
                    description: 'Coin Transfer unlock refunded',
                    status: 'completed',
                    reference: {
                        paymentIntentId,
                        entitlementKey: config.unlockEntitlementKey
                    },
                    metadata: {
                        chargeId: charge.id || '',
                        currency: String(charge.currency || '').toUpperCase()
                    },
                    paymentMethod: 'stripe',
                    completedAt: new Date()
                }], { session: mongoSession });
            }

            await PaymentEvent.create([{
                eventId,
                type: 'charge.refunded',
                userId: entitlement.userId,
                amount: charge.amount_refunded || charge.amount || 0,
                currency: charge.currency,
                status: 'processed'
            }], { session: mongoSession });

            outcome = {
                postCommit: () => emitCoinTransferUnlockUpdate(app, updatedEntitlement, {
                    unlocked: false,
                    source: 'coin_transfer_unlock_refund'
                })
            };
        });

        if (outcome?.postCommit) {
            await outcome.postCommit();
        }
    } catch (error) {
        console.error(`Webhook charge.refunded failed for ${eventId}:`, error);
    } finally {
        await mongoSession.endSession();
    }
};

// @desc    Handle Stripe Webhooks
// @route   POST /api/payments/webhook
// @access  Public (Stripe verified)
exports.handleWebhook = async (req, res) => {
    if (!stripe) {
        return res.status(503).json({ error: 'Stripe is not configured' });
    }

    const signature = req.headers['stripe-signature'];
    let event;

    try {
        event = stripe.webhooks.constructEvent(
            req.body,
            signature,
            process.env.STRIPE_WEBHOOK_SECRET
        );
    } catch (error) {
        console.error(`Webhook signature verification failed: ${error.message}`);
        return res.status(400).send(`Webhook Error: ${error.message}`);
    }

    if (event.type === 'checkout.session.completed') {
        await processCheckoutSession({
            checkoutSession: event.data.object,
            eventId: event.id,
            app: req.app
        });
    } else if (event.type === 'charge.refunded') {
        await processRefundEvent({
            charge: event.data.object,
            eventId: event.id,
            app: req.app
        });
    }

    return res.json({ received: true });
};
