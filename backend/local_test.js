const http = require('http');

async function testApi() {
    console.log('--- Testing Friend Circle API ---');

    // Login first to get a token
    console.log('1. Logging in to get token...');
    const loginRes = await fetch('http://localhost:5000/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: 'john@example.com', password: 'password123' })
    });

    const loginData = await loginRes.json();
    if (!loginData.token) {
        console.error('Login failed, creating john if needed...');
        const createRes = await fetch('http://localhost:5000/api/auth/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username: 'johntester', email: 'john@example.com', password: 'password123' })
        });
        const createData = await createRes.json();
        if (!createData.token) {
            console.error('Creation failed. Aborting.', createData);
            return;
        }
        console.log('âœ… Created John and logged in');
        token = createData.token;
    } else {
        token = loginData.token;
        console.log('âœ… Login successful');
    }

    // Test 1: Daily Reward
    console.log('\n2. Testing Daily Reward POST...');
    const rewardRes = await fetch('http://localhost:5000/api/economy/daily-reward', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        }
    });

    const rewardData = await rewardRes.json();
    console.log('Daily Reward Status:', rewardRes.status);
    console.log('Daily Reward Response:', rewardData);

    // Test 2: VIP Purchase
    console.log('\n3. Testing VIP Purchase POST...');
    const vipRes = await fetch('http://localhost:5000/api/vip/purchase', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ level: 1, period: 'monthly' })
    });

    const vipData = await vipRes.json();
    console.log('VIP Purchase Status:', vipRes.status);
    console.log('VIP Purchase Response:', vipData);

    // Test 3: VIP Status
    console.log('\n4. Testing VIP Status GET...');
    const statusRes = await fetch('http://localhost:5000/api/vip/status', {
        method: 'GET',
        headers: {
            'Authorization': `Bearer ${token}`
        }
    });

    const statusData = await statusRes.json();
    console.log('VIP Status Code:', statusRes.status);
    console.log('VIP Status Response:', statusData);
}

testApi().catch(console.error);






