const redis = require('redis');
require('dotenv').config();

async function test() {
    try {
        const client = redis.createClient({ url: process.env.REDIS_URL });
        client.on('error', (err) => console.log('Redis Client Error', err));
        await client.connect();

        await client.del('test:zset'); // Clear first
        await client.zIncrBy('test:zset', 1, '67c5427ee6cfb96c35059770');
        let results;
        try {
            results = await client.zRangeWithScores('test:zset', 0, -1, { REV: true });
        } catch (err) {
            // Fallback for older Redis versions (e.g., 3.x)
            const raw = await client.sendCommand(['ZREVRANGE', 'test:zset', '0', '-1', 'WITHSCORES']);
            const parsed = [];
            for (let i = 0; i < raw.length; i += 2) {
                parsed.push({ value: raw[i], score: Number(raw[i + 1]) });
            }
            results = parsed;
        }
        console.log('Results:', JSON.stringify(results));

        await client.quit();
    } catch (err) {
        console.error('Test Error:', err);
    }
}

test();






