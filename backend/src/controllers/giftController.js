const mongoose = require('mongoose');
const Gift = require('../models/Gift');
const Message = require('../models/Message');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const Room = require('../models/Room');
const rankingService = require('../services/rankingService');
const { awardRoomGiftXp } = require('../services/roomProgressionService');
const { awardSpendXp, buildProgressPayload } = require('../services/spendXpService');
const economyController = require('./economyController');
const { canUseRoomGifts, getParticipant } = require('../utils/roomPermissions');

const resolveIdempotencyKey = (req) => {
    return req.idempotencyKey
        || req.get('Idempotency-Key')
        || req.get('X-Idempotency-Key')
        || req.get('idempotency-key')
        || req.get('x-idempotency-key')
        || req.headers['idempotency-key']
        || req.headers['x-idempotency-key'];
};

const populateRealtimeRoom = async (roomId) => Room.findById(roomId)
    .populate('hostId', 'username avatar level vipLevel')
    .populate('coHosts', 'username avatar level vipLevel')
    .populate('moderators', 'username avatar level vipLevel')
    .populate('participants.userId', 'username avatar level vipLevel status.isOnline')
    .populate('bans.userId', 'username avatar');

// @desc    Get all gifts (catalog)
exports.getGiftCatalog = async (req, res, next) => {
    try {
        const { category, tier, minLevel, sort = 'popular' } = req.query;
        const query = { active: true };
        const redisClient = req.app.get('redis');

        const cacheKey = `cache:gifts:catalog:${category || 'all'}:${tier || 'all'}:${minLevel || 'all'}:${sort}`;
        if (redisClient && redisClient.isReady) {
            const cached = await redisClient.get(cacheKey);
            if (cached) {
                return res.json(JSON.parse(cached));
            }
        }

        if (category) query.category = category;
        if (tier) query.tier = parseInt(tier);
        if (minLevel) query['requirements.minLevel'] = { $lte: parseInt(minLevel) };

        const now = new Date();
        query.$or = [
            { 'availability.limited': false },
            {
                'availability.limited': true,
                $and: [
                    { $or: [{ 'availability.startDate': { $exists: false } }, { 'availability.startDate': null }, { 'availability.startDate': { $lte: now } }] },
                    { $or: [{ 'availability.endDate': { $exists: false } }, { 'availability.endDate': null }, { 'availability.endDate': { $gte: now } }] },
                    { $expr: { $or: [{ $eq: ['$availability.totalAvailable', 0] }, { $lt: ['$availability.sold', '$availability.totalAvailable'] }] } }
                ]
            }
        ];

        let sortOption = {};
        switch (sort) {
            case 'popular': sortOption = { 'stats.totalSent': -1 }; break;
            case 'price_low': sortOption = { 'price.coins': 1, 'price.gems': 1 }; break;
            case 'price_high': sortOption = { 'price.coins': -1, 'price.gems': -1 }; break;
            default: sortOption = { tier: 1, 'stats.totalSent': -1 };
        }

        const gifts = await Gift.find(query).sort(sortOption);
        const categorized = {
            simple: gifts.filter(g => g.category === 'simple'),
            premium: gifts.filter(g => g.category === 'premium'),
            luxury: gifts.filter(g => g.category === 'luxury'),
            legendary: gifts.filter(g => g.category === 'legendary')
        };

        if (redisClient && redisClient.isReady) {
            await redisClient.set(cacheKey, JSON.stringify(categorized), { EX: 3600 });
        }
        res.json(categorized);
    } catch (error) {
        next(error);
    }
};

exports.getGiftById = async (req, res, next) => {
    try {
        const gift = await Gift.findById(req.params.id);
        if (!gift) {
            const error = new Error('Gift not found');
            error.status = 404;
            throw error;
        }
        res.json(gift);
    } catch (error) {
        next(error);
    }
};

// @desc    Send gift to user
exports.sendGift = async (req, res, next) => {
    try {
        const { toUserId, giftId, roomId, message: giftNote } = req.body;
        const fromUserId = req.userId;
        const idempotencyKey = resolveIdempotencyKey(req);
        if (idempotencyKey && !req.idempotencyKey) {
            req.idempotencyKey = idempotencyKey;
        }

        if (idempotencyKey) {
            const existingTxn = await Transaction.findOne({ userId: fromUserId, idempotencyKey, type: 'gift_sent' })
                .populate('reference.giftId', 'name icon animation')
                .select('transactionId balanceAfter reference');
            if (existingTxn) {
                return res.json({
                    success: true,
                    gift: existingTxn.reference?.giftId || null,
                    transactionId: existingTxn.transactionId,
                    newBalance: existingTxn.balanceAfter
                });
            }
        }

        // Idempotency: prevent rapid duplicate sends
        const redisClient = req.app.get('redis');
        const redisReady = !!redisClient && (redisClient.isReady ?? redisClient.isOpen);
        if (!idempotencyKey && redisReady) {
            const exists = await redisClient.set(`gift_lock:${fromUserId}:${giftId}:${toUserId}`, "1", { EX: 2, NX: true });
            if (!exists) return res.status(429).json({ error: 'Sending gifts too quickly, please wait' });
        }

        let room = null;
        if (roomId) {
            room = await Room.findById(roomId);
            if (!room) {
                const error = new Error('Room not found');
                error.status = 404;
                throw error;
            }

            if (!getParticipant(room, fromUserId) || !getParticipant(room, toUserId)) {
                const error = new Error('Both users need to be inside the room for room gifting');
                error.status = 403;
                throw error;
            }

            if (!canUseRoomGifts(room, fromUserId)) {
                const error = new Error('Gifting is currently disabled in this room');
                error.status = 403;
                throw error;
            }
        }

        const gift = await Gift.findById(giftId);
        if (!gift) throw new Error('Gift not found');

        const [originalSender, originalRecipient] = await Promise.all([
            User.findById(fromUserId),
            User.findById(toUserId)
        ]);

        if (!originalSender) throw new Error('Sender not found');
        if (!originalRecipient) throw new Error('Recipient not found');

        if (!roomId) {
            const isFriend = (originalSender.friends || [])
                .some(friendId => friendId.toString() === toUserId);
            if (!isFriend) {
                const error = new Error('You can only send direct gifts to friends from chat');
                error.status = 403;
                throw error;
            }
        }

        if (originalSender.coins < gift.price.coins || originalSender.gems < gift.price.gems) {
            const error = new Error('Insufficient funds');
            error.status = 400;
            throw error;
        }

        const balanceBeforeSender = { coins: originalSender.coins, gems: originalSender.gems };
        const balanceBeforeRecipient = { coins: originalRecipient.coins, gems: originalRecipient.gems };

        // Atomic Deduction (Solves Wallet Race Condition)
        const sender = await User.findOneAndUpdate(
            { _id: fromUserId, coins: { $gte: gift.price.coins }, gems: { $gte: gift.price.gems } },
            { 
                $inc: { 
                    coins: -gift.price.coins, 
                    gems: -gift.price.gems, 
                    'stats.giftsSent': 1, 
                    'stats.totalSpent': gift.price.coins 
                } 
            },
            { new: true }
        );

        if (!sender) {
            const error = new Error('Transaction failed: Insufficient funds or concurrent update');
            error.status = 409;
            throw error;
        }

        const payoutCoins = Math.floor(gift.price.coins * 0.8);
        const payoutGems = Math.floor(gift.price.gems * 0.8);

        // Atomic Increment
        const recipient = await User.findByIdAndUpdate(
            toUserId,
            { 
                $inc: { 
                    coins: payoutCoins, 
                    gems: payoutGems, 
                    'stats.giftsReceived': 1 
                } 
            },
            { new: true }
        );

        const senderTxn = new Transaction({
            userId: fromUserId,
            type: 'gift_sent',
            amount: { coins: -gift.price.coins, gems: -gift.price.gems },
            balanceBefore: balanceBeforeSender,
            balanceAfter: { coins: sender.coins, gems: sender.gems },
            reference: { giftId, recipientId: toUserId, roomId },
            idempotencyKey: idempotencyKey || undefined,
            status: 'completed',
            completedAt: new Date()
        });

        const recipientTxn = new Transaction({
            userId: toUserId,
            type: 'gift_received',
            amount: { coins: payoutCoins, gems: payoutGems },
            balanceBefore: balanceBeforeRecipient,
            balanceAfter: { coins: recipient.coins, gems: recipient.gems },
            reference: { giftId, senderId: fromUserId, roomId },
            status: 'completed',
            completedAt: new Date()
        });

        await Promise.all([senderTxn.save(), recipientTxn.save()]);

        let roomProgress = null;
        let populatedRoom = null;
        if (roomId) {
            const roomForProgress = await Room.findById(roomId);
            if (roomForProgress) {
                if (!roomForProgress.metrics) {
                    roomForProgress.metrics = {};
                }
                if (!roomForProgress.economy) {
                    roomForProgress.economy = {};
                }
                roomForProgress.metrics.totalGifts =
                    Number(roomForProgress.metrics?.totalGifts || 0) + 1;
                roomForProgress.economy.totalEarned =
                    Number(roomForProgress.economy?.totalEarned || 0) + Number(gift.price.coins || 0);
                roomForProgress.economy.todayEarned =
                    Number(roomForProgress.economy?.todayEarned || 0) + Number(gift.price.coins || 0);

                if (!Array.isArray(roomForProgress.economy.topContributors)) {
                    roomForProgress.economy.topContributors = [];
                }

                const contributor = roomForProgress.economy.topContributors.find(
                    entry => entry?.userId?.toString() === fromUserId
                );
                if (contributor) {
                    contributor.gifts = Number(contributor.gifts || 0) + 1;
                    contributor.amount = Number(contributor.amount || 0) + Number(gift.price.coins || 0);
                } else {
                    roomForProgress.economy.topContributors.push({
                        userId: fromUserId,
                        amount: Number(gift.price.coins || 0),
                        gifts: 1
                    });
                }

                roomProgress = awardRoomGiftXp({
                    room: roomForProgress,
                    coins: gift.price.coins,
                    gems: gift.price.gems
                });
                await roomForProgress.save();
                populatedRoom = await populateRealtimeRoom(roomId);
            }
        }

        gift.stats.totalSent = (gift.stats.totalSent || 0) + 1;
        await gift.save();

        const recipientProgress = await awardSpendXp({
            user: recipient,
            coins: gift.price.coins,
            gems: gift.price.gems,
            baseXp: gift.effects?.recipient?.xp || gift.effects?.sender?.xp
        });
        const progressedRecipient = recipientProgress?.user || recipient;

        let directGiftMessage = null;
        if (!roomId) {
            const trimmedNote = typeof giftNote === 'string' ? giftNote.trim() : '';
            const content = trimmedNote
                ? `Sent ${gift.name}: ${trimmedNote}`
                : `Sent ${gift.name}`;

            directGiftMessage = new Message({
                senderId: fromUserId,
                recipientId: toUserId,
                content,
                type: 'gift',
                giftId: gift._id,
                giftAnimation: typeof gift.animation === 'string'
                    ? gift.animation
                    : gift.animation?.type || '',
                metadata: {
                    giftName: gift.name,
                    giftIcon: gift.icon,
                    giftTier: gift.tier,
                    giftNote: trimmedNote || '',
                    recipientXpGained: recipientProgress?.xpGained || 0,
                    recipientLevel: progressedRecipient.level,
                    recipientLeveledUp: recipientProgress?.leveledUp === true
                }
            });
            await directGiftMessage.save();
            await directGiftMessage.populate([
                { path: 'senderId', select: 'username avatar level' }
            ]);
        }

        const result = {
            sender,
            recipient: progressedRecipient,
            gift,
            senderTxn,
            message: giftNote,
            roomId,
            directGiftMessage,
            recipientProgress
        };

        // Background updates
        rankingService.updateGiftRanking(fromUserId, result.gift.price.coins, result.roomId).catch(console.error);
        rankingService.updateCharmRanking(toUserId, result.gift.price.coins).catch(console.error);

        const io = req.app.get('io');
        if (io) {
            const giftData = {
                giftId: result.gift._id,
                giftName: result.gift.name,
                giftIcon: result.gift.icon,
                animation: result.gift.animation,
                sender: {
                    userId: result.sender._id,
                    username: result.sender.username,
                    avatar: result.sender.avatar,
                    newBalance: buildProgressPayload(result.sender, {
                        xpGained: 0,
                        source: 'gift_sent'
                    })
                },
                recipient: {
                    userId: result.recipient._id,
                    username: result.recipient.username,
                    avatar: result.recipient.avatar,
                    newBalance: buildProgressPayload(result.recipient, {
                        xpGained: recipientProgress?.xpGained || 0,
                        source: 'gift_received'
                    })
                },
                message: result.message,
                roomId: result.roomId,
                room: roomProgress
                    ? {
                        id: result.roomId,
                        level: roomProgress.newLevel,
                        exp: roomProgress.room.exp,
                        expToday: roomProgress.room.expToday,
                        xpGained: roomProgress.xpGained,
                        leveledUp: roomProgress.leveledUp
                    }
                    : null
            };
            io.to(`user:${fromUserId}`).emit('balance_update', giftData.sender.newBalance);
            io.to(`user:${toUserId}`).emit('balance_update', giftData.recipient.newBalance);
            if (recipientProgress?.leveledUp) {
                io.to(`user:${toUserId}`).emit('level_up', {
                    newLevel: result.recipient.level,
                    xp: result.recipient.xp,
                    xpGained: recipientProgress.xpGained,
                    source: 'gift_received'
                });
            }
            if (result.roomId) {
                io.to(`room:${result.roomId}`).emit('receive_gift', giftData);
                if (populatedRoom) {
                    io.to(`room:${result.roomId}`).emit('room:updated', populatedRoom);
                    io.emit('room:lobby:update', {
                        roomId: populatedRoom._id?.toString() || result.roomId,
                        action: 'gift_progress',
                        name: populatedRoom.name,
                        category: populatedRoom.category,
                        type: populatedRoom.type,
                        hostAvatar: populatedRoom.hostId?.avatar || '',
                        coverImage: populatedRoom.theme?.coverImage || '',
                        participantCount:
                            populatedRoom.participantCount ?? populatedRoom.participants?.length ?? 0,
                        onlineCount: populatedRoom.onlineCount ?? 0,
                        rallyActive: populatedRoom.rallyActive === true &&
                            (!populatedRoom.rallyExpiresAt ||
                                new Date(populatedRoom.rallyExpiresAt) > new Date()),
                        rallyExpiresAt: populatedRoom.rallyExpiresAt || null,
                        endedAt: populatedRoom.endedAt || null,
                        updatedAt: new Date().toISOString()
                    });
                }
            } else if (result.directGiftMessage) {
                const dmPayload = {
                    message: result.directGiftMessage,
                    from: { id: req.userId, username: sender.username }
                };
                io.to(`user:${toUserId}`).emit('dm:received', dmPayload);
                io.to(`user:${fromUserId}`).emit('dm:received', dmPayload);
            }
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'send_gift', 1).catch(() => {});
        economyController._progressQuest(redis, req.userId, 'weekly_gift', 1).catch(() => {});

        res.json({
            success: true,
            gift: result.gift,
            transactionId: result.senderTxn.transactionId,
            newBalance: buildProgressPayload(result.sender, {
                xpGained: 0,
                source: 'gift_sent'
            })
        });
    } catch (error) {
        next(error);
    }
};

exports.getGiftHistory = async (req, res, next) => {
    try {
        const { page = 1, limit = 20, type } = req.query;
        const query = { userId: req.userId };
        if (type === 'sent') query.type = 'gift_sent';
        else if (type === 'received') query.type = 'gift_received';
        else query.type = { $in: ['gift_sent', 'gift_received'] };

        const history = await Transaction.find(query)
            .populate('reference.giftId', 'name icon animation')
            .populate('reference.senderId', 'username avatar')
            .populate('reference.recipientId', 'username avatar')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Transaction.countDocuments(query);
        res.json({
            transactions: history,
            history,
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

exports.getGiftLeaderboard = async (req, res, next) => {
    try {
        const { period = 'daily', roomId } = req.query;
        const leaderboardRaw = await rankingService.getRankings('gifts', period, 100, roomId);
        const leaderboard = leaderboardRaw.map(entry => ({
            ...entry,
            count: entry.score
        }));
        let userRank = null;
        if (req.userId) {
            userRank = await rankingService.getUserRank(req.userId, 'gifts', period);
        }
        res.json({ leaderboard, userRank, period });
    } catch (error) {
        next(error);
    }
};

exports.getGiftAchievements = async (req, res, next) => {
    try {
        // Placeholder for achievements logic
        res.json({
            success: true,
            achievements: [],
            specialTitles: [],
            stats: { giftsSent: 0, giftsReceived: 0 }
        });
    } catch (error) {
        next(error);
    }
};

exports.seedGifts = async (req, res, next) => {
    try {
        // Simple seed logic
        const count = await Gift.countDocuments();
        if (count > 0) return res.json({ message: 'Gifts already seeded' });

        const baseGifts = [
            { name: 'Rose', icon: 'ðŸŒ¹', price: { coins: 10, gems: 0 }, tier: 1, category: 'simple', animation: 'rose_scatter' },
            { name: 'Heart', icon: 'â¤ï¸', price: { coins: 50, gems: 0 }, tier: 1, category: 'simple', animation: 'heart_pop' },
            { name: 'Diamond', icon: 'ðŸ’Ž', price: { coins: 0, gems: 10 }, tier: 2, category: 'premium', animation: 'diamond_sparkle' }
        ];

        await Gift.insertMany(baseGifts);
        res.json({ success: true, message: 'Gifts seeded successfully' });
    } catch (error) {
        next(error);
    }
};
