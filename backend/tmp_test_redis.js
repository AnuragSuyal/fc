const redis = require('redis');
require('dotenv').config();

async function test() {
    const client = redis.createClient({ url: process.env.REDIS_URL });
    await client.connect();

    await client.zIncrBy('test:zset', 1, '69a6863da63594f083428af4');
    const results = await client.zRangeWithScores('test:zset', 0, -1, { REV: true });
    console.log('Results:', JSON.stringify(results));

    await client.quit();
}

test();






