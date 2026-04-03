const mongoose = require('mongoose');

const Transaction = require('../models/Transaction');
const User = require('../models/User');
const VipEntitlementHistory = require('../models/VipEntitlementHistory');
const { awardSpendXp } = require('../services/spendXpService');
const {
    buildProgressPayload,
    buildRealtimeIdentityPayload,
    emitLevelDrivenRealtime
} = require('../services/levelProgressionService');
const {
    buildVipCatalog,
    buildVipMembershipSnapshot,
    calculateVipUpgradeCredit,
    getVipPlanConfig,
    getVipTierConfig,
    normalizeVipTierId,
    resolveMonthlyRewardState,
    serializeVipTier,
    syncVipMembershipState
} = require('../services/vipMembershipService');
const {
    VIP_TIER_ORDER,
    VIP_TIER_BY_ID
} = require('../config/vipMembershipConfig');

const withSession = (query, session) => (session ? query.session(session) : query);

const runWithOptionalTransaction = async (work) => {
    const session = await mongoose.startSession();
    try {
        session.startTransaction();
        const result = await work(session);
        await session.commitTransaction();
        return result;
    } catch (error) {
        await session.abortTransaction();
        if (error?.message?.includes('Transaction numbers are only allowed')) {
            return work(null);
        }
        throw error;
    } finally {
        await session.endSession();
    }
};

const buildVipStatusResponse = (user, { selectedTierId = '' } = {}) => {
    const membership = buildVipMembershipSnapshot(user, { selectedTierId });
    const currentTierIndex = membership.activeTierId
        ? VIP_TIER_ORDER.indexOf(membership.activeTierId)
        : -1;
    const nextTier = currentTierIndex >= 0 && currentTierIndex < VIP_TIER_ORDER.length - 1
        ? serializeVipTier(VIP_TIER_BY_ID[VIP_TIER_ORDER[currentTierIndex + 1]], {
            currentTierId: membership.activeTierId,
            selectedTierId
        })
        : null;

    return {
        membership,
        currentLevel: membership.currentTier,
        nextLevel: nextTier,
        comparison: buildVipCatalog({
            currentTierId: membership.activeTierId,
            selectedTierId
        }).comparison,
        totalSpent: Number(user.totalCoinsSpent || user.stats?.totalSpent || 0)
    };
};

const emitVipIdentityUpdate = async (req, user, {
    xpProgress = null,
    source = 'vip_update',
    extra = {}
} = {}) => {
    const io = req.app.get('io');
    if (!io || !user?._id) return;

    const userId = user._id.toString();
    const progressPayload = buildProgressPayload(user, {
        xpGained: xpProgress?.xpGained || 0,
        source,
        ...extra
    });
    io.to(`user:${userId}`).emit('balance_update', progressPayload);
    io.to(`user:${userId}`).emit('vip_activated', {
        ...progressPayload,
        membership: buildVipMembershipSnapshot(user)
    });
    io.to(`user:${userId}`).emit('profile:updated', {
        userId,
        timestamp: new Date().toISOString(),
        user: buildRealtimeIdentityPayload(user),
        fields: {
            vipLevel: user.vipLevel,
            vipMembership: buildVipMembershipSnapshot(user)
        }
    });

    if (xpProgress) {
        await emitLevelDrivenRealtime(io, user, xpProgress, { source });
    }
};

const readIdempotencyKey = (req, fallbackPrefix = 'vip') => {
    const headerKey = req.get('X-Idempotency-Key');
    const bodyKey = req.body?.idempotencyKey;
    const key = String(headerKey || bodyKey || '').trim();
    if (key) return key;
    return `${fallbackPrefix}:${req.userId}:${Date.now()}`;
};

const resolveRequestedPlanDuration = (body = {}) => {
    if (body.planDuration) return body.planDuration;
    if (body.period === 'annual') return 'yearly';
    return body.period || 'monthly';
};

const buildPurchaseResponse = ({
    user,
    tier,
    plan,
    payableCoins,
    creditCoins = 0,
    startedAt,
    expireAt,
    transactionId = ''
}) => ({
    success: true,
    message: payableCoins > 0
        ? `${tier.displayName} activated successfully.`
        : `${tier.displayName} activated using your existing membership credit.`,
    membership: buildVipMembershipSnapshot(user),
    tier: serializeVipTier(tier, {
        currentTierId: tier.tierId,
        selectedTierId: tier.tierId
    }),
    plan: {
        planDuration: plan.planDuration,
        label: plan.label,
        durationDays: plan.durationDays
    },
    charge: {
        originalCoins: Number(tier.pricing?.[plan.planDuration]?.coins || 0),
        creditCoins: Number(creditCoins || 0),
        payableCoins: Number(payableCoins || 0)
    },
    startedAt: startedAt?.toISOString() || null,
    expireAt: expireAt?.toISOString() || null,
    transactionId,
    newBalance: buildProgressPayload(user, {
        source: 'vip_purchase'
    })
});

exports.getVipLevels = (req, res) => {
    const selectedTierId = normalizeVipTierId(req.query?.tierId);
    res.json(buildVipCatalog({ selectedTierId }));
};

exports.getVipStatus = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('coins gems xp level totalCoinsSpent stats.totalSpent vipTier vipStatus vipStartAt vipExpireAt vipAutoRenew vipPlanDuration vipPurchaseSource monthlyRewardLastClaimedAt vipLastUpdatedAt vipLevel vipExpiry vipPurchasedAt shopProfile badges status gameStats avatar coverPhoto bio region username uid');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        syncVipMembershipState(user);
        if (user.isModified()) {
            await user.save();
        }

        res.json(buildVipStatusResponse(user));
    } catch (error) {
        next(error);
    }
};

exports.purchaseVip = async (req, res, next) => {
    try {
        const tierId = normalizeVipTierId(req.body?.tierId || req.body?.level);
        const tier = getVipTierConfig(tierId);
        if (!tier) {
            const error = new Error('Invalid VIP tier');
            error.status = 400;
            throw error;
        }

        const plan = getVipPlanConfig(resolveRequestedPlanDuration(req.body));
        const idempotencyKey = readIdempotencyKey(req, 'vip-purchase');
        const existingTransaction = await Transaction.findOne({
            userId: req.userId,
            idempotencyKey
        }).sort({ createdAt: -1 });

        if (existingTransaction) {
            const existingUser = await User.findById(req.userId);
            if (!existingUser) {
                const error = new Error('User not found');
                error.status = 404;
                throw error;
            }
            syncVipMembershipState(existingUser);
            if (existingUser.isModified()) {
                await existingUser.save();
            }

            return res.json(buildPurchaseResponse({
                user: existingUser,
                tier,
                plan,
                payableCoins: existingTransaction.amount?.coins
                    ? Math.abs(Number(existingTransaction.amount.coins))
                    : 0,
                creditCoins: existingTransaction.metadata?.creditCoins || 0,
                startedAt: existingUser.vipStartAt,
                expireAt: existingUser.vipExpireAt,
                transactionId: existingTransaction.transactionId
            }));
        }

        const purchaseSource = String(req.body?.purchaseSource || 'coins').trim() || 'coins';

        const purchaseResult = await runWithOptionalTransaction(async (session) => {
            const user = await withSession(User.findById(req.userId), session);
            if (!user) {
                const error = new Error('User not found');
                error.status = 404;
                throw error;
            }

            syncVipMembershipState(user);

            const now = new Date();
            const currentActiveTierId = user.vipLevel > 0 ? normalizeVipTierId(user.vipTier || user.vipLevel) : '';
            const currentActiveTier = getVipTierConfig(currentActiveTierId);
            const isDowngradeWhileActive = currentActiveTier &&
                currentActiveTier.tierId !== tier.tierId &&
                currentActiveTier.level > tier.level;

            if (isDowngradeWhileActive) {
                const error = new Error('Downgrades apply after your current membership expires. Upgrade or renew instead.');
                error.status = 409;
                throw error;
            }

            const priceCoins = Number(tier.pricing?.[plan.planDuration]?.coins || 0);
            const creditCoins = currentActiveTier &&
                currentActiveTier.tierId !== tier.tierId &&
                tier.level > currentActiveTier.level
                ? calculateVipUpgradeCredit({
                    currentTierId: currentActiveTier.tierId,
                    currentPlanDuration: user.vipPlanDuration,
                    currentExpireAt: user.vipExpireAt,
                    now
                })
                : 0;
            const payableCoins = Math.max(0, priceCoins - creditCoins);

            if (purchaseSource === 'coins' && Number(user.coins || 0) < payableCoins) {
                const error = new Error('Insufficient coins for this membership plan');
                error.status = 400;
                throw error;
            }

            const renewsCurrentTier = currentActiveTier?.tierId === tier.tierId;
            const startedAt = renewsCurrentTier && user.vipExpireAt && user.vipExpireAt > now
                ? new Date(user.vipExpireAt)
                : now;
            const expireAt = new Date(startedAt.getTime() + (plan.durationDays * 24 * 60 * 60 * 1000));

            const previousTier = user.vipTier || '';
            const previousStatus = user.vipStatus || 'inactive';
            const balanceBefore = {
                coins: Number(user.coins || 0),
                gems: Number(user.gems || 0)
            };

            if (purchaseSource === 'coins' && payableCoins > 0) {
                user.coins = Math.max(0, Number(user.coins || 0) - payableCoins);
            }

            user.vipTier = tier.tierId;
            user.vipStatus = 'active';
            user.vipStartAt = renewsCurrentTier && user.vipStartAt ? user.vipStartAt : now;
            user.vipExpireAt = expireAt;
            user.vipAutoRenew = req.body?.autoRenew === true;
            user.vipPlanDuration = plan.planDuration;
            user.vipPurchaseSource = purchaseSource;
            user.vipLastUpdatedAt = now;
            user.vipPurchasedAt = now;
            syncVipMembershipState(user, { now });

            await user.save(session ? { session } : undefined);

            const transaction = new Transaction({
                userId: user._id,
                type: 'vip_purchase',
                amount: { coins: -payableCoins, gems: 0 },
                balanceBefore,
                balanceAfter: {
                    coins: Number(user.coins || 0),
                    gems: Number(user.gems || 0)
                },
                currencyType: 'coins',
                quantityPurchased: 1,
                reference: {
                    productId: `${tier.tierId}_${plan.planDuration}`
                },
                metadata: {
                    tierId: tier.tierId,
                    planDuration: plan.planDuration,
                    purchaseSource,
                    creditCoins,
                    startedAt: startedAt.toISOString(),
                    expireAt: expireAt.toISOString()
                },
                idempotencyKey,
                paymentMethod: purchaseSource === 'coins' ? 'system' : 'mock',
                status: 'completed',
                description: `${tier.displayName} ${plan.label} membership`,
                completedAt: now
            });
            await transaction.save(session ? { session } : undefined);

            await VipEntitlementHistory.create(session ? [{
                userId: user._id,
                oldTier: previousTier,
                newTier: tier.tierId,
                oldStatus: previousStatus,
                newStatus: user.vipStatus,
                changedAt: now,
                source: 'purchase',
                transactionReference: transaction.transactionId,
                metadata: {
                    planDuration: plan.planDuration,
                    creditCoins,
                    payableCoins
                }
            }] : {
                userId: user._id,
                oldTier: previousTier,
                newTier: tier.tierId,
                oldStatus: previousStatus,
                newStatus: user.vipStatus,
                changedAt: now,
                source: 'purchase',
                transactionReference: transaction.transactionId,
                metadata: {
                    planDuration: plan.planDuration,
                    creditCoins,
                    payableCoins
                }
            }, session ? { session } : undefined);

            return {
                user,
                tier,
                plan,
                payableCoins,
                creditCoins,
                startedAt,
                expireAt,
                transaction
            };
        });

        const xpProgress = await awardSpendXp({
            user: purchaseResult.user,
            coins: purchaseResult.payableCoins,
            sourceType: 'vip_purchase',
            sourceReferenceId: `${purchaseResult.tier.tierId}_${purchaseResult.plan.planDuration}`,
            sourceReferenceType: 'membership_plan',
            dedupeKey: idempotencyKey,
            metadata: {
                tierId: purchaseResult.tier.tierId,
                planDuration: purchaseResult.plan.planDuration
            },
            redis: req.app.get('redis')
        });
        const progressedUser = xpProgress?.user || purchaseResult.user;

        await emitVipIdentityUpdate(req, progressedUser, {
            xpProgress,
            source: 'vip_purchase',
            extra: {
                tierId: purchaseResult.tier.tierId,
                planDuration: purchaseResult.plan.planDuration
            }
        });

        res.json(buildPurchaseResponse({
            user: progressedUser,
            tier: purchaseResult.tier,
            plan: purchaseResult.plan,
            payableCoins: purchaseResult.payableCoins,
            creditCoins: purchaseResult.creditCoins,
            startedAt: purchaseResult.startedAt,
            expireAt: purchaseResult.expireAt,
            transactionId: purchaseResult.transaction.transactionId
        }));
    } catch (error) {
        if (error?.code === 11000) {
            try {
                const user = await User.findById(req.userId);
                if (user) {
                    syncVipMembershipState(user);
                    if (user.isModified()) {
                        await user.save();
                    }
                    return res.json(buildVipStatusResponse(user));
                }
            } catch (_) {}
        }
        next(error);
    }
};

exports.cancelVip = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        syncVipMembershipState(user);
        if (!user.vipTier) {
            return res.json({
                success: true,
                message: 'No active membership to manage.',
                membership: buildVipMembershipSnapshot(user)
            });
        }

        const previousStatus = user.vipStatus;
        user.vipAutoRenew = false;
        user.vipStatus = user.vipLevel > 0 ? 'active' : 'expired';
        user.vipLastUpdatedAt = new Date();
        await user.save();

        await VipEntitlementHistory.create({
            userId: user._id,
            oldTier: user.vipTier,
            newTier: user.vipTier,
            oldStatus: previousStatus,
            newStatus: user.vipStatus,
            changedAt: new Date(),
            source: 'cancel_auto_renew',
            metadata: {
                autoRenew: false
            }
        });

        res.json({
            success: true,
            message: 'Auto-renew turned off. Your membership stays active until expiry.',
            membership: buildVipMembershipSnapshot(user)
        });
    } catch (error) {
        next(error);
    }
};

exports.restoreVip = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        syncVipMembershipState(user);
        if (user.isModified()) {
            await user.save();
        }

        await VipEntitlementHistory.create({
            userId: user._id,
            oldTier: user.vipTier || '',
            newTier: user.vipTier || '',
            oldStatus: user.vipStatus || 'inactive',
            newStatus: user.vipStatus || 'inactive',
            changedAt: new Date(),
            source: 'restore',
            metadata: {
                restored: true
            }
        });

        await emitVipIdentityUpdate(req, user, {
            source: 'vip_restore'
        });

        res.json({
            success: true,
            message: user.vipLevel > 0
                ? 'Membership restored from the server state.'
                : 'No active membership was found to restore.',
            membership: buildVipMembershipSnapshot(user)
        });
    } catch (error) {
        next(error);
    }
};

exports.claimVipMonthlyReward = async (req, res, next) => {
    try {
        const idempotencyKey = readIdempotencyKey(req, 'vip-reward');
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        syncVipMembershipState(user);
        const tier = getVipTierConfig(user.vipTier || user.vipLevel);
        if (!tier || user.vipLevel <= 0) {
            const error = new Error('Active VIP membership required');
            error.status = 403;
            throw error;
        }

        const rewardState = resolveMonthlyRewardState({
            startAt: user.vipStartAt,
            lastClaimedAt: user.monthlyRewardLastClaimedAt,
            active: true
        });
        if (!rewardState.eligible) {
            return res.json({
                success: true,
                alreadyClaimed: true,
                membership: buildVipMembershipSnapshot(user),
                monthlyCoins: Number(tier.monthlyCoinReward || 0)
            });
        }

        const existingTransaction = await Transaction.findOne({
            userId: req.userId,
            idempotencyKey
        }).sort({ createdAt: -1 });
        if (existingTransaction) {
            syncVipMembershipState(user);
            if (user.isModified()) {
                await user.save();
            }
            return res.json({
                success: true,
                monthlyCoins: Number(tier.monthlyCoinReward || 0),
                membership: buildVipMembershipSnapshot(user),
                newBalance: buildProgressPayload(user, {
                    source: 'vip_monthly_reward'
                })
            });
        }

        const rewardCoins = Number(tier.monthlyCoinReward || 0);
        const balanceBefore = {
            coins: Number(user.coins || 0),
            gems: Number(user.gems || 0)
        };
        user.coins = balanceBefore.coins + rewardCoins;
        user.monthlyRewardLastClaimedAt = new Date();
        user.vipLastUpdatedAt = new Date();
        await user.save();

        const transaction = await Transaction.create({
            userId: user._id,
            type: 'vip_monthly_reward',
            amount: { coins: rewardCoins, gems: 0 },
            balanceBefore,
            balanceAfter: {
                coins: Number(user.coins || 0),
                gems: Number(user.gems || 0)
            },
            currencyType: 'coins',
            description: `${tier.displayName} monthly reward`,
            idempotencyKey,
            metadata: {
                tierId: tier.tierId,
                rewardCycle: rewardState.currentCycle
            },
            status: 'completed',
            completedAt: new Date()
        });

        await emitVipIdentityUpdate(req, user, {
            source: 'vip_monthly_reward',
            extra: {
                rewardCoins
            }
        });

        res.json({
            success: true,
            monthlyCoins: rewardCoins,
            membership: buildVipMembershipSnapshot(user),
            transactionId: transaction.transactionId,
            newBalance: buildProgressPayload(user, {
                source: 'vip_monthly_reward',
                rewardCoins
            })
        });
    } catch (error) {
        next(error);
    }
};

exports.claimVipDailyBonus = exports.claimVipMonthlyReward;
