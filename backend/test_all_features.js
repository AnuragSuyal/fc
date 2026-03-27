const axios = require('axios');

const API_URL = 'http://localhost:5000/api';

async function runTests() {
    console.log('ðŸš€ Starting Comprehensive System Test...\n');
    let token1, token2, userId1, userId2;
    let roomId, giftId, postId, groupId;

    try {
        // --- 1. AUTHENTICATION ---
        console.log('--- Phase 1: Authentication ---');
        const user1 = { username: 'tester1', email: 'tester1@test.com', password: 'password123' };
        const user2 = { username: 'tester2', email: 'tester2@test.com', password: 'password123' };

        try { await axios.post(`${API_URL}/auth/register`, user1); } catch (e) { }
        try { await axios.post(`${API_URL}/auth/register`, user2); } catch (e) { }

        const login1 = await axios.post(`${API_URL}/auth/login`, { email: user1.email, password: user1.password });
        token1 = login1.data.token;
        userId1 = login1.data.user._id;
        console.log('âœ… User 1 logged in');

        const login2 = await axios.post(`${API_URL}/auth/login`, { email: user2.email, password: user2.password });
        token2 = login2.data.token;
        userId2 = login2.data.user._id;
        console.log('âœ… User 2 logged in');

        const headers1 = { Authorization: `Bearer ${token1}` };
        const headers2 = { Authorization: `Bearer ${token2}` };

        // --- PRE-TEST: FUND WALLETS ---
        await axios.post(`${API_URL}/wallet/purchase/coins`, { packId: 'coins_legendary' }, { headers: headers1 });
        await axios.post(`${API_URL}/wallet/purchase/coins`, { packId: 'coins_legendary' }, { headers: headers2 });
        console.log('âœ… Both users funded with coins');

        // --- 2. ROOMS ---
        console.log('\n--- Phase 2: Rooms ---');
        const createRoomRes = await axios.post(`${API_URL}/rooms`, {
            name: 'Test Party Room',
            description: 'Testing rooms system',
            type: 'voice',
            category: 'chat'
        }, { headers: headers1 });
        roomId = createRoomRes.data._id;
        console.log('âœ… Room created:', roomId);

        await axios.post(`${API_URL}/rooms/${roomId}/join`, {}, { headers: headers2 });
        console.log('âœ… User 2 joined User 1s room');

        const trendingRes = await axios.get(`${API_URL}/rooms/trending`);
        console.log('âœ… Trending rooms fetched. Count:', trendingRes.data.length);

        // --- 3. GIFTING & ECONOMY ---
        console.log('\n--- Phase 3: Gifting & Economy ---');
        let shopRes = await axios.get(`${API_URL}/gifts/catalog`);

        if (shopRes.data.length === 0 || (Object.keys(shopRes.data).length === 4 && shopRes.data.simple.length === 0)) {
            console.log('Seeding gifts...');
            await axios.post(`${API_URL}/gifts/seed`, {}, { headers: headers1 });
            shopRes = await axios.get(`${API_URL}/gifts/catalog`);
        }

        const categorized = shopRes.data;
        const allGifts = [...(categorized.simple || []), ...(categorized.premium || []), ...(categorized.luxury || []), ...(categorized.legendary || [])];

        if (allGifts.length === 0) throw new Error('Gift catalog is still empty after seeding');
        giftId = allGifts[0]._id;
        console.log('âœ… Gift shop fetched. Gift ID:', giftId);

        const sendGiftRes = await axios.post(`${API_URL}/gifts/send`, {
            toUserId: userId2,
            giftId: giftId,
            roomId: roomId
        }, { headers: headers1 });
        console.log('âœ… Gift sent! Transaction ID:', sendGiftRes.data.transactionId);

        const dailyRes = await axios.post(`${API_URL}/economy/daily-reward`, {}, { headers: headers1 });
        console.log('âœ… Daily reward claimed:', dailyRes.data.reward);

        // --- 4. VIP SYSTEM ---
        console.log('\n--- Phase 4: VIP System ---');
        const vipStatus = await axios.get(`${API_URL}/vip/status`, { headers: headers1 });
        console.log('âœ… VIP Status fetched. Level:', vipStatus.data.vipLevel);

        // --- 5. POSTS & FEED ---
        console.log('\n--- Phase 5: Posts & Feed ---');
        const createPostRes = await axios.post(`${API_URL}/posts`, {
            content: 'Hello world from testing script!'
        }, { headers: headers1 });
        postId = createPostRes.data._id;
        console.log('âœ… Post created:', postId);

        await axios.post(`${API_URL}/posts/${postId}/like`, {}, { headers: headers2 });
        console.log('âœ… Post liked by User 2');

        const feedRes = await axios.get(`${API_URL}/posts/feed`, { headers: headers2 });
        console.log('âœ… Feed fetched. Count:', feedRes.data.posts.length);

        // --- 6. GROUPS (CIRCLES) ---
        console.log('\n--- Phase 6: Groups (Circles) ---');
        const createGroupRes = await axios.post(`${API_URL}/groups`, {
            name: 'Master Circle ' + Date.now().toString().slice(-4),
            tag: 'MSTR' + Date.now().toString().slice(-4),
            description: 'Testing groups system'
        }, { headers: headers1 });
        groupId = createGroupRes.data._id;
        console.log('âœ… Group created:', groupId);

        await axios.post(`${API_URL}/groups/${groupId}/join`, {}, { headers: headers2 });
        console.log('âœ… User 2 joined Group');

        const groupTreasure = await axios.post(`${API_URL}/groups/${groupId}/treasure`, {}, { headers: headers1 });
        console.log('âœ… Group treasure claimed:', groupTreasure.data.message);

        console.log('\nâœ¨ ALL TESTS PASSED SUCCESSFULLY! âœ¨');

    } catch (error) {
        console.error('\nâŒ TEST FAILED!');
        if (error.response) {
            console.error('Status:', error.response.status);
            console.error('Data:', JSON.stringify(error.response.data, null, 2));
            console.error('URL:', error.config.url);
        } else {
            console.error('Error:', error.message);
        }
        process.exit(1);
    }
}

runTests();






