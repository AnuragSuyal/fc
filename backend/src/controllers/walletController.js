const User = require('../models/User');
const Transaction = require('../models/Transaction');

// @desc    Get user balance
exports.getBalance = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('coins gems tickets stars vipLevel');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json({
            coins: user.coins || 0,
            gems: user.gems || 0,
            tickets: user.tickets || 0,
            stars: user.stars || 0,
            vipLevel: user.vipLevel || 0
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get transaction history
exports.getTransactions = async (req, res, next) => {
    try {
        const { page = 1, limit = 20, type } = req.query;
        const query = { userId: req.userId };
        if (type) query.type = type;

        const transactions = await Transaction.find(query)
            .populate('reference.giftId', 'name icon')
            .populate('reference.recipientId', 'username avatar')
            .populate('reference.roomId', 'name')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Transaction.countDocuments(query);
        const grouped = {};
        transactions.forEach(t => {
            const date = t.createdAt.toISOString().slice(0, 10);
            if (!grouped[date]) grouped[date] = [];
            grouped[date].push(t);
        });

        res.json({
            transactions: grouped,
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get coin packs
exports.getCoinPacks = (req, res) => {
    res.json([
        { id: 'coins_small', name: 'Starter Pack', coins: 1000, price: 0.99, popular: false },
        { id: 'coins_medium', name: 'Popular Pack', coins: 5000, price: 4.99, popular: true },
        { id: 'coins_large', name: 'Value Pack', coins: 12000, price: 9.99, popular: false },
        { id: 'coins_xl', name: 'Mega Pack', coins: 25000, price: 19.99, popular: false },
        { id: 'coins_xxl', name: 'Ultra Pack', coins: 60000, price: 49.99, popular: false },
        { id: 'coins_legendary', name: 'Legendary Pack', coins: 150000, price: 99.99, popular: false },
    ]);
};

// @desc    Get gem packs
exports.getGemPacks = (req, res) => {
    res.json([
        { id: 'gems_small', name: 'Mini Gems', gems: 100, price: 1.99 },
        { id: 'gems_medium', name: 'Standard Gems', gems: 500, price: 8.99 },
        { id: 'gems_large', name: 'Deluxe Gems', gems: 1200, price: 19.99 },
        { id: 'gems_xl', name: 'Premium Gems', gems: 3000, price: 49.99 },
        { id: 'gems_xxl', name: 'Ultimate Gems', gems: 8000, price: 99.99 },
    ]);
};

// @desc    Purchase coins (mock)
exports.purchaseCoins = async (req, res, next) => {
    try {
        const { packId } = req.body;
        const idempotencyKey = req.idempotencyKey;
        const packs = {
            'coins_small': 1000, 'coins_medium': 5000, 'coins_large': 12000,
            'coins_xl': 25000, 'coins_xxl': 60000, 'coins_legendary': 150000
        };
        const coins = packs[packId];
        if (!coins) {
            const error = new Error('Invalid pack');
            error.status = 400;
            throw error;
        }

        if (idempotencyKey) {
            const existing = await Transaction.findOne({ userId: req.userId, idempotencyKey, type: 'purchase_coins' });
            if (existing) {
                return res.json({ success: true, newBalance: existing.balanceAfter, transactionId: existing.transactionId });
            }
        }

        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };
        user.coins = (user.coins || 0) + coins;
        await user.save();

        const transaction = new Transaction({
            userId: user._id,
            type: 'purchase_coins',
            amount: { coins },
            balanceBefore,
            balanceAfter: { coins: user.coins, gems: user.gems },
            description: `Purchased ${coins} coins`,
            reference: { productId: packId },
            paymentMethod: 'mock',
            idempotencyKey: idempotencyKey || undefined,
            status: 'completed',
            completedAt: new Date()
        });
        await transaction.save();

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${user._id}`).emit('balance_update', {
                coins: user.coins,
                gems: user.gems
            });
        }

        res.json({ success: true, newBalance: { coins: user.coins, gems: user.gems }, transactionId: transaction.transactionId });
    } catch (error) {
        next(error);
    }
};

// @desc    Purchase gems (mock)
exports.purchaseGems = async (req, res, next) => {
    try {
        const { packId } = req.body;
        const idempotencyKey = req.idempotencyKey;
        const packs = {
            'gems_small': 100, 'gems_medium': 500, 'gems_large': 1200,
            'gems_xl': 3000, 'gems_xxl': 8000
        };
        const gems = packs[packId];
        if (!gems) {
            const error = new Error('Invalid pack');
            error.status = 400;
            throw error;
        }

        if (idempotencyKey) {
            const existing = await Transaction.findOne({ userId: req.userId, idempotencyKey, type: 'purchase_gems' });
            if (existing) {
                return res.json({ success: true, newBalance: existing.balanceAfter, transactionId: existing.transactionId });
            }
        }

        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };
        user.gems = (user.gems || 0) + gems;
        await user.save();

        const transaction = new Transaction({
            userId: user._id,
            type: 'purchase_gems',
            amount: { gems },
            balanceBefore,
            balanceAfter: { coins: user.coins, gems: user.gems },
            description: `Purchased ${gems} gems`,
            reference: { productId: packId },
            paymentMethod: 'mock',
            idempotencyKey: idempotencyKey || undefined,
            status: 'completed',
            completedAt: new Date()
        });
        await transaction.save();

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${user._id}`).emit('balance_update', {
                coins: user.coins,
                gems: user.gems
            });
        }

        res.json({ success: true, newBalance: { coins: user.coins, gems: user.gems }, transactionId: transaction.transactionId });
    } catch (error) {
        next(error);
    }
};

// @desc    Convert coins to gems
exports.convertCoinsToGems = async (req, res, next) => {
    try {
        const { coins } = req.body;
        const idempotencyKey = req.idempotencyKey;
        if (!coins || coins < 100) {
            const error = new Error('Minimum 100 coins required');
            error.status = 400;
            throw error;
        }

        if (idempotencyKey) {
            const existing = await Transaction.findOne({ userId: req.userId, idempotencyKey, type: 'conversion' });
            if (existing) {
                return res.json({ success: true, newBalance: existing.balanceAfter, transactionId: existing.transactionId });
            }
        }

        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if ((user.coins || 0) < coins) {
            const error = new Error('Insufficient coins');
            error.status = 400;
            throw error;
        }

        const gems = Math.floor(coins / 100);
        const balanceBefore = { coins: user.coins || 0, gems: user.gems || 0 };

        user.coins -= coins;
        user.gems = (user.gems || 0) + gems;
        await user.save();

        const transaction = new Transaction({
            userId: user._id,
            type: 'conversion',
            amount: { coins: -coins, gems },
            balanceBefore,
            balanceAfter: { coins: user.coins, gems: user.gems },
            description: `Converted ${coins} coins to ${gems} gems`,
            paymentMethod: 'system',
            idempotencyKey: idempotencyKey || undefined,
            status: 'completed',
            completedAt: new Date()
        });
        await transaction.save();

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${user._id}`).emit('balance_update', {
                coins: user.coins,
                gems: user.gems
            });
        }

        res.json({ success: true, newBalance: { coins: user.coins, gems: user.gems }, transactionId: transaction.transactionId });
    } catch (error) {
        next(error);
    }
};

exports.getSpecialOffers = (req, res) => res.json([]);





