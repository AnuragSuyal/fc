const test = require('node:test');
const assert = require('node:assert/strict');

const rankingService = require('../src/services/rankingService');

test('zRangeWithScoresDesc falls back to the reverse raw Redis command when REV syntax is unsupported', async () => {
    const previousClient = rankingService.redisClient;
    const previousOwnership = rankingService.ownsRedisClient;
    let sendCommandCalled = false;
    let zRangeWithScoresCalled = false;

    rankingService.configure({
        redisClient: {
            isReady: true,
            sendCommand: async (args) => {
                sendCommandCalled = true;
                assert.deepEqual(args, [
                    'ZREVRANGE',
                    'ranking:test',
                    '0',
                    '1',
                    'WITHSCORES'
                ]);
                return ['user-2', '1400', 'user-1', '1200'];
            },
            zRangeWithScores: async () => {
                zRangeWithScoresCalled = true;
                throw new Error('ERR syntax error');
            }
        }
    });

    try {
        const results = await rankingService.zRangeWithScoresDesc('ranking:test', 0, 1);

        assert.equal(sendCommandCalled, true);
        assert.equal(zRangeWithScoresCalled, false);
        assert.deepEqual(results, [
            { value: 'user-2', score: 1400 },
            { value: 'user-1', score: 1200 }
        ]);
    } finally {
        rankingService.redisClient = previousClient;
        rankingService.ownsRedisClient = previousOwnership;
    }
});
