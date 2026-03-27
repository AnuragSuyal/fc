const axios = require('axios');
require('dotenv').config();

async function testConcurrency() {
    console.log('--- Starting Deep Audit Concurrency Test ---');

    try {
        const { MongoClient, ObjectId } = require('mongodb');
        const jwt = require('jsonwebtoken');
        const client = await MongoClient.connect('mongodb://127.0.0.1:27017/friendcircle');
        const db = client.db();

        // Register users directly in DB
        console.log('Registering users directly in DB...');
        const senderId = new ObjectId();
        const recipientId = new ObjectId();

        await db.collection('users').insertMany([
            { _id: senderId, username: `sender${Date.now()}`, email: `sender${Date.now()}@test.com`, password: 'mock', coins: 100, gems: 0 },
            { _id: recipientId, username: `recipient${Date.now()}`, email: `recipient${Date.now()}@test.com`, password: 'mock', coins: 0, gems: 0 }
        ]);

        // Generate JWT token directly
        const user1Token = jwt.sign({ userId: senderId.toString() }, process.env.JWT_SECRET, { expiresIn: '7d' });

        // Seed Redis session
        const { createClient } = require('redis');
        const redisClient = createClient({ url: process.env.REDIS_URL });
        await redisClient.connect();
        await redisClient.set(`session:${senderId.toString()}`, 'true', { EX: 3600 });
        await redisClient.disconnect();
        
        // Seed gift directly because there's no active admin ui setup
        await db.collection('gifts').updateOne(
            { _id: new ObjectId("65dfa2b25c35391cbedaa111") },
            { 
                $set: {
                    name: 'Rose',
                    category: 'simple',
                    icon: 'ðŸŒ¹',
                    price: { coins: 60, gems: 0 },
                    stats: { totalSent: 0 }
                } 
            },
            { upsert: true }
        );

        // Test Health
        const healthRes = await axios.get('http://localhost:5000/health');
        console.log('Health:', healthRes.data);

        // Spam requests securely using Idempotency Key!
        console.log('Firing 20 concurrent /send-gift transactions...');
        const promises = [];
        
        for (let i = 0; i < 20; i++) {
            const req = axios.post('http://localhost:5000/api/gifts/send', {
                giftId: '65dfa2b25c35391cbedaa111',
                toUserId: recipientId,
                roomId: null,
            }, {
                headers: {
                    'Authorization': `Bearer ${user1Token}`,
                    'x-idempotency-key': 'test_uuid_123'
                }
            }).then(res => res.data).catch(err => err.response?.data || err.message);
            promises.push(req);
        }

        const results = await Promise.all(promises);
        
        let successCount = 0;
        let duplicateCount = 0;
        let insuffCount = 0;
        let rateLimitCount = 0;

        results.forEach((res, index) => {
            if (res.success) successCount++;
            else if (res.error) {
                const errStr = typeof res.error === 'string' ? res.error : (res.error.message || JSON.stringify(res.error));
                if (errStr.includes('Duplicate')) duplicateCount++;
                else if (errStr.includes('Insufficient')) insuffCount++;
                else {
                    console.log(`Error in request ${index}:`, res.error);
                }
            }
            else if (res.message) {
                const msgStr = typeof res.message === 'string' ? res.message : (res.message.message || JSON.stringify(res.message));
                if (msgStr.includes('too quickly') || msgStr.includes('Slow down')) rateLimitCount++;
                else console.log('Unknown Message:', res.message);
            }
            else console.log('Unexpected Response Shape:', res);
        });

        const finalUser1 = await db.collection('users').findOne({ _id: new ObjectId(senderId) });

        console.log(`Transactions Created: ${successCount}`);
        console.log(`Duplicates Blocked by Idempotency Key: ${duplicateCount}`);
        console.log(`Insufficient Funds (Race Blocked): ${insuffCount}`);
        console.log(`Rate Limited by API: ${rateLimitCount}`);
        console.log(`Sender Remaining Wallet: ${finalUser1.coins}`);
        
        const explain = await db.collection('transactions').find({ 'reference.senderId': new ObjectId(senderId) }).explain('executionStats');
        console.log(`Transactions Index Used: ${explain.queryPlanner.winningPlan.inputStage.stage === 'IXSCAN' ? 'âœ… IXSCAN YES!' : 'âŒ COLLSCAN'}`);
        
        await client.close();

    } catch (err) {
        console.error('Test Failed:', err.response?.data || err.message);
    }
}

testConcurrency();






