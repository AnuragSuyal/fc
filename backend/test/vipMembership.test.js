const test = require('node:test');
const assert = require('node:assert/strict');

const {
    buildVipCatalog,
    buildVipMembershipSnapshot,
    calculateVipUpgradeCredit,
    normalizeVipTierId,
    resolveMonthlyRewardState
} = require('../src/services/vipMembershipService');

test('normalizeVipTierId resolves numeric and formatted tier inputs', () => {
    assert.equal(normalizeVipTierId(1), 'vip1');
    assert.equal(normalizeVipTierId('VIP 8'), 'vip8');
    assert.equal(normalizeVipTierId('vip-10'), 'vip10');
    assert.equal(normalizeVipTierId('legend'), 'legend');
    assert.equal(normalizeVipTierId('unknown'), '');
});

test('buildVipCatalog returns all supported tiers and comparison rows', () => {
    const catalog = buildVipCatalog({
        currentTierId: 'vip4',
        selectedTierId: 'diamond'
    });

    assert.equal(catalog.tiers.length, 13);
    assert.ok(catalog.comparison.rows.length > 0);
    assert.equal(catalog.tiers[3].tierId, 'vip4');
    assert.equal(catalog.tiers[3].isCurrent, true);
    assert.equal(
        catalog.tiers.find((tier) => tier.tierId === 'diamond')?.isSelected,
        true
    );
});

test('buildVipMembershipSnapshot marks active memberships and monthly rewards correctly', () => {
    const now = new Date('2026-03-30T00:00:00.000Z');
    const user = {
        vipTier: 'vip7',
        vipStatus: 'active',
        vipStartAt: new Date('2026-03-01T00:00:00.000Z'),
        vipExpireAt: new Date('2026-04-15T00:00:00.000Z'),
        vipAutoRenew: true,
        vipPlanDuration: 'quarterly',
        vipPurchaseSource: 'coins',
        monthlyRewardLastClaimedAt: null
    };

    const snapshot = buildVipMembershipSnapshot(user, { now });

    assert.equal(snapshot.status, 'active');
    assert.equal(snapshot.isActive, true);
    assert.equal(snapshot.activeTierId, 'vip7');
    assert.equal(snapshot.currentTier.displayName, 'VIP 7');
    assert.equal(snapshot.autoRenew, true);
    assert.equal(snapshot.planDuration, 'quarterly');
    assert.equal(snapshot.monthlyRewardAmount, 2650);
    assert.equal(snapshot.canClaimMonthlyReward, true);
    assert.ok(snapshot.daysRemaining > 0);
});

test('buildVipMembershipSnapshot preserves expired tier identity but removes active entitlement', () => {
    const now = new Date('2026-03-30T00:00:00.000Z');
    const user = {
        vipTier: 'diamond',
        vipStatus: 'active',
        vipStartAt: new Date('2025-12-01T00:00:00.000Z'),
        vipExpireAt: new Date('2026-03-01T00:00:00.000Z'),
        vipAutoRenew: true,
        vipPlanDuration: 'yearly',
        vipPurchaseSource: 'coins',
        monthlyRewardLastClaimedAt: new Date('2026-02-15T00:00:00.000Z')
    };

    const snapshot = buildVipMembershipSnapshot(user, { now });

    assert.equal(snapshot.status, 'expired');
    assert.equal(snapshot.isActive, false);
    assert.equal(snapshot.activeTierId, '');
    assert.equal(snapshot.currentTierId, 'diamond');
    assert.equal(snapshot.currentTier.displayName, 'Diamond');
    assert.equal(snapshot.vipLevel, 0);
    assert.equal(snapshot.canClaimMonthlyReward, false);
});

test('resolveMonthlyRewardState and calculateVipUpgradeCredit handle cycle timing and proration', () => {
    const now = new Date('2026-03-30T00:00:00.000Z');
    const rewardState = resolveMonthlyRewardState({
        startAt: new Date('2026-01-01T00:00:00.000Z'),
        lastClaimedAt: new Date('2026-02-10T00:00:00.000Z'),
        active: true,
        now
    });

    const credit = calculateVipUpgradeCredit({
        currentTierId: 'vip5',
        currentPlanDuration: 'quarterly',
        currentExpireAt: new Date('2026-05-15T00:00:00.000Z'),
        now
    });

    assert.equal(rewardState.eligible, true);
    assert.equal(rewardState.currentCycle, 2);
    assert.equal(rewardState.lastClaimedCycle, 1);
    assert.ok(credit > 0);
});
