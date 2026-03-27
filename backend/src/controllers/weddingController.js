const Wedding = require('../models/Wedding');
const User = require('../models/User');
const Transaction = require('../models/Transaction');

// Ring catalog, paid with coins.
const RINGS = [
    { id: 'silver', name: 'Silver Ring', icon: 'ring-silver', rarity: 'common', price: 500 },
    { id: 'gold', name: 'Gold Ring', icon: 'ring-gold', rarity: 'rare', price: 2000 },
    { id: 'diamond', name: 'Diamond Ring', icon: 'ring-diamond', rarity: 'epic', price: 10000 },
    { id: 'eternal', name: 'Eternal Ring', icon: 'ring-eternal', rarity: 'legendary', price: 50000 }
];

exports.getRings = (_req, res) => res.json(RINGS);

// @desc    Get my mingle status
exports.getMyWedding = async (req, res, next) => {
    try {
        const wedding = await Wedding.findOne({
            $or: [{ proposerId: req.userId }, { partnerId: req.userId }],
            status: { $in: ['pending', 'accepted', 'active'] }
        })
            .populate('proposerId', 'username avatar level vipLevel')
            .populate('partnerId', 'username avatar level vipLevel')
            .populate('ceremony.roomId', 'name roomId');

        if (!wedding) {
            return res.json({ married: false });
        }

        const partner = wedding.proposerId._id.toString() === req.userId
            ? wedding.partnerId
            : wedding.proposerId;

        res.json({ married: wedding.status === 'active', wedding, partner });
    } catch (error) {
        next(error);
    }
};

// @desc    Send a mingle invite
exports.propose = async (req, res, next) => {
    try {
        const { partnerId, ringId } = req.body;
        if (partnerId === req.userId) {
            const error = new Error('Cannot send a mingle invite to yourself');
            error.status = 400;
            throw error;
        }

        const ring = RINGS.find((entry) => entry.id === ringId);
        if (!ring) {
            const error = new Error('Invalid ring');
            error.status = 400;
            throw error;
        }

        const existing = await Wedding.findOne({
            $or: [{ proposerId: req.userId }, { partnerId: req.userId }],
            status: { $in: ['pending', 'active'] }
        });
        if (existing) {
            const error = new Error('You already have an active or pending mingle');
            error.status = 400;
            throw error;
        }

        const partnerBusy = await Wedding.findOne({
            $or: [{ proposerId: partnerId }, { partnerId }],
            status: { $in: ['pending', 'active'] }
        });
        if (partnerBusy) {
            const error = new Error('That person already has an active or pending mingle');
            error.status = 400;
            throw error;
        }

        const proposer = await User.findOneAndUpdate(
            { _id: req.userId, coins: { $gte: ring.price } },
            { $inc: { coins: -ring.price } },
            { new: true }
        );
        if (!proposer) {
            const error = new Error('Insufficient coins');
            error.status = 400;
            throw error;
        }

        const wedding = await Wedding.create({
            proposerId: req.userId,
            partnerId,
            ring: {
                name: ring.name,
                icon: ring.icon,
                rarity: ring.rarity,
                coinsSpent: ring.price
            }
        });

        await Transaction.create({
            userId: req.userId,
            type: 'wedding_ring',
            amount: { coins: -ring.price },
            balanceBefore: { coins: proposer.coins + ring.price, gems: proposer.gems },
            balanceAfter: { coins: proposer.coins, gems: proposer.gems },
            description: `Mingle ring: ${ring.name}`,
            status: 'completed',
            completedAt: new Date()
        });

        const io = req.app.get('io');
        if (io) {
            io.to(`user:${partnerId}`).emit('wedding:proposal', {
                from: { _id: proposer._id, username: proposer.username, avatar: proposer.avatar },
                ring: wedding.ring,
                weddingId: wedding._id
            });
            io.to(`user:${req.userId}`).emit('wedding:proposal_sent', {
                partnerId,
                ring: wedding.ring,
                weddingId: wedding._id
            });
            io.to(`user:${req.userId}`).emit('balance_update', {
                coins: proposer.coins,
                gems: proposer.gems
            });
        }

        res.status(201).json({
            success: true,
            wedding,
            message: `Mingle invite sent with ${ring.name}!`
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Accept a mingle invite
exports.acceptProposal = async (req, res, next) => {
    try {
        const { weddingId } = req.params;
        const wedding = await Wedding.findById(weddingId);
        if (!wedding) {
            const error = new Error('Mingle invite not found');
            error.status = 404;
            throw error;
        }
        if (wedding.partnerId.toString() !== req.userId) {
            const error = new Error('This invite is not for you');
            error.status = 403;
            throw error;
        }
        if (wedding.status !== 'pending') {
            const error = new Error('This mingle invite is no longer pending');
            error.status = 400;
            throw error;
        }

        wedding.status = 'active';
        wedding.marriedAt = new Date();
        await wedding.save();

        await wedding.populate([
            { path: 'proposerId', select: 'username avatar' },
            { path: 'partnerId', select: 'username avatar' }
        ]);

        const io = req.app.get('io');
        if (io) {
            const payload = {
                weddingId: wedding._id,
                proposer: wedding.proposerId,
                partner: wedding.partnerId
            };
            io.to(`user:${wedding.proposerId._id}`).emit('wedding:accepted', payload);
            io.to(`user:${req.userId}`).emit('wedding:accepted', payload);
        }

        res.json({
            success: true,
            wedding,
            message: 'Congratulations. Your mingle is now active.'
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Reject a mingle invite
exports.rejectProposal = async (req, res, next) => {
    try {
        const { weddingId } = req.params;
        const wedding = await Wedding.findById(weddingId);
        if (!wedding) {
            const error = new Error('Mingle invite not found');
            error.status = 404;
            throw error;
        }
        if (wedding.partnerId.toString() !== req.userId) {
            const error = new Error('This invite is not for you');
            error.status = 403;
            throw error;
        }

        wedding.status = 'expired';
        await wedding.save();

        const io = req.app.get('io');
        if (io) {
            const payload = { weddingId };
            io.to(`user:${wedding.proposerId}`).emit('wedding:rejected', payload);
            io.to(`user:${req.userId}`).emit('wedding:rejected', payload);
        }

        res.json({ success: true, message: 'Mingle invite rejected' });
    } catch (error) {
        next(error);
    }
};

// @desc    End an active mingle
exports.divorce = async (req, res, next) => {
    try {
        const wedding = await Wedding.findOne({
            $or: [{ proposerId: req.userId }, { partnerId: req.userId }],
            status: 'active'
        });
        if (!wedding) {
            const error = new Error('No active mingle found');
            error.status = 404;
            throw error;
        }

        const otherId = wedding.proposerId.toString() === req.userId
            ? wedding.partnerId
            : wedding.proposerId;
        wedding.status = 'divorced';
        wedding.divorcedAt = new Date();
        await wedding.save();

        const io = req.app.get('io');
        if (io) {
            const payload = { weddingId: wedding._id };
            io.to(`user:${otherId}`).emit('wedding:divorced', payload);
            io.to(`user:${req.userId}`).emit('wedding:divorced', payload);
        }

        res.json({ success: true, message: 'Mingle ended successfully' });
    } catch (error) {
        next(error);
    }
};

// @desc    Send a live vibe to an active mingle
exports.addBlessing = async (req, res, next) => {
    try {
        const { weddingId } = req.params;
        const { message } = req.body;
        const wedding = await Wedding.findById(weddingId);
        if (!wedding || wedding.status !== 'active') {
            const error = new Error('Mingle not found or not active');
            error.status = 404;
            throw error;
        }

        const user = await User.findById(req.userId).select('username avatar');
        wedding.ceremony.blessings.push({
            userId: req.userId,
            message: message || 'Sending good vibes.'
        });
        wedding.ceremony.guestCount++;
        wedding.stats.totalBlessings++;
        await wedding.save();

        const io = req.app.get('io');
        if (io) {
            const payload = { from: user, message, weddingId };
            [wedding.proposerId, wedding.partnerId].forEach((uid) => {
                io.to(`user:${uid}`).emit('wedding:blessing', payload);
            });
        }

        res.json({ success: true, message: 'Live vibe sent!' });
    } catch (error) {
        next(error);
    }
};

// @desc    Get mingle rankings
exports.getCoupleRankings = async (req, res, next) => {
    try {
        const couples = await Wedding.find({ status: 'active' })
            .populate('proposerId', 'username avatar vipLevel')
            .populate('partnerId', 'username avatar vipLevel')
            .sort({ 'stats.giftsExchanged': -1 })
            .limit(50);

        res.json(couples.map((couple, index) => ({
            rank: index + 1,
            ...couple.toObject()
        })));
    } catch (error) {
        next(error);
    }
};
