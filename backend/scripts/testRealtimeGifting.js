const { io } = require('socket.io-client');
const axios = require('axios');
const mongoose = require('mongoose');
const jwt = require('jsonwebtoken');
require('dotenv').config();

const User = require('../src/models/User');
const Room = require('../src/models/Room');
const Gift = require('../src/models/Gift');
const connectDB = require('../src/config/db');

async function runTest() {
    console.log('ðŸš€ Connecting to Database...');
    await connectDB();

    try {
        console.log('ðŸ” Fetching test data...');
        const user = await User.findOne();
        const room = await Room.findOne();
        const gift = await Gift.findOne();
        const recipient = await User.findOne({ _id: { $ne: user._id } }) || user;

        if (!user || !room || !gift) {
            throw new Error('Required test data (user, room, or gift) not found');
        }

        // Emergency Recharge
        user.coins = 100000;
        user.gems = 100000;
        await user.save();
        console.log(`âœ… Recharged ${user.username} (ID: ${user._id}) to 100k coins/gems`);

        const token = jwt.sign({ userId: user._id }, process.env.JWT_SECRET);

        console.log(`âœ… Test Data Ready:`);
        console.log(`   - User: ${user.username}`);
        console.log(`   - Room: ${room.name}`);
        console.log(`   - Gift: ${gift.name}`);

        const socket = io('http://localhost:5000', {
            auth: { token },
            transports: ['websocket']
        });

        socket.on('connect', () => {
            console.log('âœ… Socket connected');
            console.log(`ðŸ  Joining room: ${room._id}`);
            socket.emit('join_room', room._id.toString());

            setTimeout(async () => {
                try {
                    console.log('ðŸ’¸ Sending gift via API...');
                    const res = await axios.post('http://localhost:5000/api/gifts/send', {
                        toUserId: recipient._id,
                        giftId: gift._id,
                        roomId: room._id,
                        broadcast: true
                    }, {
                        headers: { Authorization: `Bearer ${token}` }
                    });
                    console.log('âœ… API Request successful');
                } catch (e) {
                    console.error('âŒ API Error:', e.response?.data || e.message);
                }
            }, 1000);
        });

        socket.on('receive_gift', (data) => {
            console.log('ðŸŽ RECEIVED REAL-TIME GIFT EVENT:');
            console.log(`   - From: ${data.fromUsername}`);
            console.log(`   - Gift: ${data.giftName} ${data.giftIcon}`);
            console.log('ðŸŽ‰ VERIFICATION SUCCESSFUL!');
            process.exit(0);
        });

        setTimeout(() => {
            console.error('âŒ Timeout: No gift event received after 10 seconds');
            process.exit(1);
        }, 10000);

    } catch (e) {
        console.error('âŒ Error during test:', e.message);
        console.error(e.stack);
        process.exit(1);
    }
}

runTest();






