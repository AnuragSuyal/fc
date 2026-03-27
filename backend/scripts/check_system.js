const mongoose = require('mongoose');
require('dotenv').config();
const { AccessToken } = require('livekit-server-sdk');

async function checkSystem() {
    console.log('ðŸš€ Starting Friend Circle System Diagnostic...\n');

    // 1. Database Check
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… MongoDB: Connected successfully.');
        await mongoose.disconnect();
    } catch (err) {
        console.error('âŒ MongoDB: Connection failed!', err.message);
    }

    // 2. LiveKit Config Check
    const apiKey = process.env.LIVEKIT_API_KEY;
    const apiSecret = process.env.LIVEKIT_API_SECRET;
    const url = process.env.LIVEKIT_URL;

    if (apiKey && apiSecret && url) {
        console.log('âœ… LiveKit: Config found.');
        try {
            const at = new AccessToken(apiKey, apiSecret, {
                identity: 'diagnostic_bot',
            });
            at.addGrant({ roomJoin: true, room: 'test_room' });
            const token = await at.toJwt();
            console.log('âœ… LiveKit: Token generation verified.');
        } catch (err) {
            console.error('âŒ LiveKit: Token generation failed!', err.message);
        }
    } else {
        console.warn('âš ï¸ LiveKit: Missing credentials in .env');
    }

    // 3. Port Check (Self-Ping)
    const axios = require('axios');
    try {
        const response = await axios.get(`http://localhost:${process.env.PORT || 5000}/api/health`).catch(() => null);
        if (response) {
            console.log('âœ… Server: API is online and responding.');
        } else {
            console.log('âš ï¸ Server: Local API is not running (This is okay if you haven\'t run npm start).');
        }
    } catch (err) {
        // Axios might throw if server is down, which is expected if not running
    }

    console.log('\nðŸ Diagnostic Complete.');
    process.exit(0);
}

checkSystem();






