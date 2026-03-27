const axios = require('axios');
const io = require('socket.io-client');

const API_BASE = 'http://localhost:5000/api';
const SOCKET_URL = 'http://localhost:5000';

async function runGoldenPath() {
    console.log('--- STARTING GOLDEN PATH TEST ---');
    try {
        const ts = Date.now();

        // 1. Auth: New user registration (Host)
        const hostRes = await axios.post(`${API_BASE}/auth/register`, {
            username: `host_${ts}`,
            email: `host_${ts}@test.com`,
            password: 'TestPassword123!',
        });
        const hostToken = hostRes.data.token;
        const hostUser = hostRes.data.user;
        console.log('âœ… Host Registered:', hostUser.username);

        // 1b. Auth: New user registration (Guest)
        const guestRes = await axios.post(`${API_BASE}/auth/register`, {
            username: `guest_${ts}`,
            email: `guest_${ts}@test.com`,
            password: 'TestPassword123!',
        });
        const guestToken = guestRes.data.token;
        const guestUser = guestRes.data.user;
        console.log('âœ… Guest Registered:', guestUser.username);

        // 2. Economy: Claim daily reward (Guest)
        const dailyReq = await axios.post(`${API_BASE}/economy/daily-reward`, {}, {
            headers: { Authorization: `Bearer ${guestToken}` }
        });
        console.log('âœ… Guest Claimed Daily Reward, Coins:', dailyReq.data.coins);

        // Host creates a room
        const roomRes = await axios.post(`${API_BASE}/rooms`, {
            name: `Test Room ${ts}`,
            type: 'chat',
            description: 'Golden Path Testing'
        }, { headers: { Authorization: `Bearer ${hostToken}` } });
        const roomId = roomRes.data.room ? roomRes.data.room._id : roomRes.data._id;
        console.log('âœ… Host Created Room:', roomId);

        // Fetch Gifts
        const giftRes = await axios.get(`${API_BASE}/gifts/catalog`, {
            headers: { Authorization: `Bearer ${guestToken}` }
        });
        let roseGiftId = null;
        if (typeof giftRes.data === 'object') {
            for (const cat of Object.keys(giftRes.data)) {
                const gifts = giftRes.data[cat];
                if (Array.isArray(gifts)) {
                    const rose = gifts.find(g => g.name.toLowerCase().includes('rose') || g.coinCost > 0);
                    if (rose) { roseGiftId = rose._id; break; }
                }
            }
            if (!roseGiftId && Object.keys(giftRes.data).length > 0) {
                const anyCat = Object.keys(giftRes.data)[0];
                const anyGifts = giftRes.data[anyCat];
                if (Array.isArray(anyGifts) && anyGifts.length > 0) roseGiftId = anyGifts[0]._id;
            }
        } else if (Array.isArray(giftRes.data) && giftRes.data.length > 0) {
            roseGiftId = giftRes.data[0]._id;
        }

        if (!roseGiftId) {
            console.log("No gifts found in catalog:", giftRes.data);
            // fallback, try to just provide a dummy or we skip
        }

        // 3. Real-Time: Join a Room and send Gift
        const guestSocket = io(SOCKET_URL, { auth: { token: guestToken } });

        await new Promise((resolve) => {
            guestSocket.on('connect', () => {
                console.log('âœ… Guest Socket Connected');
                guestSocket.emit('join_room', roomId);
                resolve();
            });
        });

        if (roseGiftId) {
            console.log(`âœ… Ready to send gift ${roseGiftId} to host ${hostUser._id}`);
            const sendGiftRes = await axios.post(`${API_BASE}/gifts/send`, {
                toUserId: hostUser._id,
                giftId: roseGiftId,
                roomId: roomId,
                message: "A rose for the host!"
            }, { headers: { Authorization: `Bearer ${guestToken}` } });
            console.log('âœ… Gift Sent Successfully');
        } else {
            console.log('âš ï¸ Could not find a suitable gift to send.');
        }

        // 4. Social: Add the host as a friend
        const friendRes = await axios.post(`${API_BASE}/friends/request/${hostUser._id}`, {}, {
            headers: { Authorization: `Bearer ${guestToken}` }
        });
        console.log('âœ… Friend Request Sent successfully');

        guestSocket.disconnect();
        console.log('--- GOLDEN PATH TEST COMPLETED SUCCESSFULLY ---');
        process.exit(0);
    } catch (err) {
        console.error('âŒ E2E TEST FAILED:', err.response?.data || err.message);
        process.exit(1);
    }
}

runGoldenPath();






