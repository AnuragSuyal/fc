async function testGifting() {
    const baseUrl = 'http://localhost:5000/api';

    async function api(method, endpoint, body = null, token = null) {
        const headers = { 'Content-Type': 'application/json' };
        if (token) headers['Authorization'] = `Bearer ${token}`;

        const res = await fetch(`${baseUrl}${endpoint}`, {
            method,
            headers,
            body: body ? JSON.stringify(body) : null
        });

        const data = await res.json();
        if (!res.ok) {
            require('fs').writeFileSync('error_output.json', JSON.stringify(data, null, 2));
            console.error('\nAPI ERROR details saved to error_output.json');
            throw new Error(`${endpoint} failed`);
        }
        return data;
    }

    try {
        console.log('--- Registering Users ---');
        const ts = Date.now().toString().slice(-6); // Shorter timestamp
        const user1Data = await api('POST', '/auth/register', {
            username: `snd_${ts}`,
            email: `snd_${ts}@test.com`,
            password: 'password123'
        });
        console.log('User 1 Registered:', user1Data.user.username);

        const user2Data = await api('POST', '/auth/register', {
            username: `rcv_${ts}`,
            email: `rcv_${ts}@test.com`,
            password: 'password123'
        });
        console.log('User 2 Registered:', user2Data.user.username);

        const token1 = user1Data.token;

        console.log('\n--- Seeding Gift Catalog ---');
        const seedRes = await api('POST', '/gifts/seed', {}, token1);
        console.log('Seed Success:', seedRes.success, 'Count:', seedRes.count);

        console.log('\n--- Testing GET /catalog ---');
        const catalog = await api('GET', '/gifts/catalog');
        const allGifts = Object.values(catalog).flat();
        console.log('Total gifts in catalog:', allGifts.length);

        if (allGifts.length < 50) throw new Error(`Catalog too small: ${allGifts.length}`);

        const gift = allGifts.find(g => g.price.coins > 0 && g.price.coins <= 100);
        if (!gift) throw new Error('Could not find affordable gift for testing');
        console.log(`Using gift: ${gift.name} (Price: ${gift.price.coins} coins)`);

        console.log('\n--- Testing GET /:id ---');
        const giftDetails = await api('GET', `/gifts/${gift._id}`);
        if (!giftDetails || giftDetails.name !== gift.name) throw new Error('GET /:id failed');
        console.log('Gift Details:', giftDetails.name);

        console.log('\n--- Testing POST /send ---');
        const sendRes = await api('POST', '/gifts/send', {
            toUserId: user2Data.user._id,
            giftId: gift._id,
            message: 'Hello!'
        }, token1);
        console.log('Send Success:', sendRes.success);
        console.log('New Balance:', sendRes.newBalance);

        console.log('\n--- Testing GET /history ---');
        const history = await api('GET', '/gifts/history', null, token1);
        console.log('History count:', history.transactions.length);

        console.log('\n--- Testing GET /leaderboard ---');
        const lb = await api('GET', '/gifts/leaderboard');
        console.log('Leaderboard entries:', lb.leaderboard.length);
        const topUser = lb.leaderboard.find(u => u.userId === user1Data.user._id);
        console.log('Sender in leaderboard:', topUser ? 'Yes, score: ' + topUser.count : 'No');

        console.log('\n--- Testing GET /achievements ---');
        const ach = await api('GET', '/gifts/achievements', null, token1);
        console.log('Achievements count:', ach.achievements.length);
        const started = ach.achievements.find(a => a.id === 'gift_starter');
        console.log('Gift Starter completed:', started?.completed);

        console.log('\n--- VERIFICATION PASSED ---');
        console.log('All criteria met.');

    } catch (error) {
        console.error('\n!!! VERIFICATION FAILED !!!');
        console.error(error.message);
    }
}

testGifting();






