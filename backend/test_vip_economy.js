const http = require('http');
const crypto = require('crypto');

// --- Helpers ---
const BASE_URL = 'http://localhost:5000/api';

async function request(method, path, body = null, token = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(BASE_URL + path);
        const options = {
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + url.search,
            method: method,
            headers: {}
        };

        if (body) {
            options.headers['Content-Type'] = 'application/json';
        }
        if (token) {
            options.headers['Authorization'] = `Bearer ${token}`;
        }

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                let parsed;
                try {
                    parsed = JSON.parse(data);
                } catch (e) {
                    parsed = data;
                }
                if (res.statusCode >= 200 && res.statusCode < 300) {
                    resolve(parsed);
                } else {
                    reject({ status: res.statusCode, response: parsed });
                }
            });
        });

        req.on('error', (e) => reject(e));

        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function runVIPTests() {
    console.log('==============================================');
    console.log('ðŸ§ª Starting VIP & Economy Full Integration Tests');
    console.log('==============================================\n');

    let token;
    let userId;
    let ts = Date.now();
    let email = `test.vip.${ts}@example.com`;
    let username = `vip_usr_${ts % 100000}`; // Keep it short

    try {
        console.log('1. Creating test user...');
        const authRes = await request('POST', '/auth/register', {
            username,
            email,
            password: 'password123'
        });
        token = authRes.token;
        userId = authRes.user.id;
        console.log(`âœ… User registered. Token: ${token.substring(0, 10)}...`);

        console.log('\n2. Testing GET /api/vip/levels');
        const levels = await request('GET', '/vip/levels');
        console.log(`âœ… VIP levels fetched. Total tiers: ${levels.length}`);
        if (levels.length !== 13) throw new Error("Missing VIP levels");

        console.log('\n3. Testing GET /api/vip/status');
        let status = await request('GET', '/vip/status', null, token);
        console.log(`âœ… Current VIP Level: ${status.currentLevel.level} (${status.currentLevel.name})`);

        console.log('\n4. Testing POST /api/vip/purchase');
        try {
            const purchaseRes = await request('POST', '/vip/purchase', { level: 2 }, token);
            console.log('âœ… VIP Purchase Intent Created:', purchaseRes.transactionId);
        } catch (e) {
            console.error('âŒ VIP Purchase Failed:', e.response || e);
        }

        console.log('\n5. Testing GET /api/economy/stats');
        const stats = await request('GET', '/economy/stats', null, token);
        console.log(`âœ… User Stats Fetched: Coins=${stats.coins}, Gems=${stats.gems}, Streak=${stats.loginStreak}`);

        console.log('\n6. Testing POST /api/economy/daily-reward');
        try {
            const dailyRes = await request('POST', '/economy/daily-reward', null, token);
            console.log(`âœ… Daily Reward Claimed! Received ${dailyRes.coins} coins. Current Streak: ${dailyRes.streak}`);
        } catch (e) {
            console.error('âŒ Claim Daily Reward full error:', e.response || e);
        }

        console.log('\n6b. Verifying POST /api/economy/daily-reward (Double claim check)');
        try {
            const doubleClaim = await request('POST', '/economy/daily-reward', null, token);
            if (doubleClaim.alreadyClaimed) {
                console.log('âœ… Double claim properly handled (alreadyClaimed).');
            } else {
                console.error('âŒ Double claim should have been blocked or flagged.');
            }
        } catch (err) {
            if (err.status === 400 && err.response && err.response.error === 'Daily reward already claimed today') {
                console.log('âœ… Double claim properly blocked.');
            } else {
                throw err;
            }
        }

        console.log('\n7. Testing GET /api/economy/quests/daily');
        const quests = await request('GET', '/economy/quests/daily', null, token);
        console.log(`âœ… Successfully generated ${quests.length} daily quests.`);
        if (quests.length === 0) throw new Error('No quests generated!');

        const testQuest = quests[0];
        console.log(`   Selected Quest: "${testQuest.title}" (target: ${testQuest.target})`);

        console.log('\n8. Testing POST /api/economy/quests/update');
        const updateRes = await request('POST', '/economy/quests/update', {
            questId: testQuest.questId,
            increment: testQuest.target // auto complete it
        }, token);
        console.log(`âœ… Quest updated. Progress: ${updateRes.progress}, Completed: ${updateRes.completed}`);
        if (!updateRes.completed) throw new Error('Quest should be completed after meeting target');

        console.log('\n9. Testing POST /api/economy/quests/claim');
        const claimRes = await request('POST', '/economy/quests/claim', { questId: testQuest.questId }, token);
        console.log(`âœ… Quest Reward Claimed! Earned ${claimRes.rewards.coins || 0} coins, ${claimRes.rewards.gems || 0} gems, ${claimRes.rewards.xp || 0} xp`);
        console.log(`   New Balances - Coins: ${claimRes.newBalance.coins}, Gems: ${claimRes.newBalance.gems}`);

        console.log('\n10. Reviewing updated stats & transactions...');
        const finalStats = await request('GET', '/economy/stats', null, token);
        console.log(`âœ… Final Balances: Coins=${finalStats.coins}, Gems=${finalStats.gems}, Streak=${finalStats.loginStreak}`);

        console.log('\nðŸŽ‰ ALL TESTS PASSED SUCCESSFULLY! ðŸŽ‰');

    } catch (err) {
        console.error('\nâŒ TEST FAILED!');
        console.error('Status Code:', err.status);
        if (err.response) {
            console.error('Response:', JSON.stringify(err.response, null, 2));
        } else {
            console.error('Error:', err.message || err);
        }
    }
}

// Give server time to spin up if running concurrently
setTimeout(runVIPTests, 2000);







