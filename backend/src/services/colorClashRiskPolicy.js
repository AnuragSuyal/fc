const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;

const COMPETITIVE_MATCH_LIMIT = 20;

const POLICY = Object.freeze({
    repeatedPairing: {
        windowMs: DAY_MS,
        mediumMatches: 8,
        highMatches: 12,
        dominantWinRate: 0.85,
        dominantSample: 10
    },
    sameIpPairing: {
        mediumPairMatches: 4,
        mediumOverlapMatches: 2,
        highPairMatches: 8,
        highOverlapMatches: 4
    },
    timeoutAbuse: {
        sampleSize: COMPETITIVE_MATCH_LIMIT,
        mediumSample: 10,
        mediumRate: 0.35,
        highSample: 12,
        highRate: 0.5
    },
    surrenderAbuse: {
        mediumSample: 10,
        mediumCount: 4,
        highSample: 12,
        highCount: 6
    },
    refundAbuse: {
        mediumWindowMs: HOUR_MS,
        mediumCount: 3,
        highWindowMs: 6 * HOUR_MS,
        highCount: 5
    },
    lowOpponentDiversity: {
        sampleSize: 12,
        mediumSample: 10,
        mediumMaxUniqueOpponents: 3,
        mediumMaxRatio: 0.4,
        highSample: 12,
        highMaxUniqueOpponents: 2,
        highMaxRatio: 0.25
    },
    walletCycleAnomaly: {
        windowMs: DAY_MS,
        mediumMinHolds: 6,
        mediumRefundRate: 0.5,
        highMinHolds: 10,
        highRefundRate: 0.65,
        highMaxSettled: 2
    }
});

const severityOrder = Object.freeze({
    none: 0,
    low: 1,
    medium: 2,
    high: 3,
    critical: 4
});

const getHigherSeverity = (left = 'none', right = 'none') => (
    severityOrder[left] >= severityOrder[right] ? left : right
);

const resolveAutoAction = ({ flagType, severity = 'low', scope = 'ranked' } = {}) => {
    if (!severity || severityOrder[severity] < severityOrder.high) {
        return 'none';
    }

    if (severity === 'critical') {
        return 'manual_review';
    }

    switch (flagType) {
    case 'refund_abuse':
    case 'wallet_cycle_anomaly':
        return scope === 'ranked' ? 'ranked_lock' : 'stake_lock';
    case 'same_ip_pairing':
        return 'manual_review';
    case 'repeated_pairing':
    case 'timeout_abuse':
    case 'surrender_abuse':
    case 'low_opponent_diversity':
        if (scope === 'ranked') return 'ranked_lock';
        if (scope === 'stake') return 'stake_lock';
        return 'manual_review';
    default:
        return 'none';
    }
};

module.exports = {
    DAY_MS,
    HOUR_MS,
    POLICY,
    COMPETITIVE_MATCH_LIMIT,
    severityOrder,
    getHigherSeverity,
    resolveAutoAction
};
