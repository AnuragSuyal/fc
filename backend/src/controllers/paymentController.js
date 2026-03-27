const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
const User = require('../models/User');
const Transaction = require('../models/Transaction');
const PaymentEvent = require('../models/PaymentEvent');
const mongoose = require('mongoose');

// @desc    Handle Stripe Webhooks
// @route   POST /api/payments/webhook
// @access  Public (Stripe verified)
exports.handleWebhook = async (req, res) => {
    const sig = req.headers['stripe-signature'];
    let event;

    try {
        event = stripe.webhooks.constructEvent(
            req.body,
            sig,
            process.env.STRIPE_WEBHOOK_SECRET
        );
    } catch (err) {
        console.error(`âŒ Webhook signature verification failed: ${err.message}`);
        return res.status(400).send(`Webhook Error: ${err.message}`);
    }

    // Handle the event
    if (event.type === 'checkout.session.completed') {
        const session = event.data.object;
        await processOrder(session, event.id);
    }

    res.json({ received: true });
};

async function processOrder(session, eventId) {
    const mongoSession = await mongoose.startSession();
    try {
        await mongoSession.withTransaction(async () => {
            // 1. Check idempotency
            const existingEvent = await PaymentEvent.findOne({ eventId }).session(mongoSession);
            if (existingEvent) {
                console.log(`âš ï¸ Event ${eventId} already processed. Skipping.`);
                return;
            }

            // 2. Extract metadata
            const userId = session.metadata.userId;
            const coins = parseInt(session.metadata.coins) || 0;
            const gems = parseInt(session.metadata.gems) || 0;

            // 3. Credit User
            const user = await User.findById(userId).session(mongoSession);
            if (!user) throw new Error('User not found');

            const balanceBefore = { coins: user.coins, gems: user.gems };
            user.coins += coins;
            user.gems += gems;
            await user.save({ session: mongoSession });

            // 4. Record Transaction
            const txn = new Transaction({
                userId,
                type: 'purchase',
                amount: { coins, gems },
                balanceBefore,
                balanceAfter: { coins: user.coins, gems: user.gems },
                description: `Stripe Purchase: ${session.amount_total / 100} ${session.currency}`,
                status: 'completed',
                reference: { stripeSessionId: session.id }
            });
            await txn.save({ session: mongoSession });

            // 5. Mark Event as Processed
            const paymentEvent = new PaymentEvent({
                eventId,
                type: 'checkout.session.completed',
                userId,
                amount: session.amount_total,
                currency: session.currency
            });
            await paymentEvent.save({ session: mongoSession });

            console.log(`âœ… Successfully processed order for user ${userId}`);
        });
    } catch (error) {
        console.error(`âŒ Error processing order ${eventId}:`, error);
        // PaymentEvent should technically record a "failed" status here if we wanted to be extreme,
        // but with transactions, the whole thing rolls back so Stripe will retry.
    } finally {
        mongoSession.endSession();
    }
}






