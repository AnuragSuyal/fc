require('dotenv').config({ path: __dirname + '/../.env' });
const mongoose = require('mongoose');
const User = require('../src/models/User');
const Room = require('../src/models/Room');
const Gift = require('../src/models/Gift');

async function verifyAll() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… MongoDB Connected');

        const userCount = await User.countDocuments();
        console.log(`ðŸ“Š Users: ${userCount}`);

        const roomCount = await Room.countDocuments();
        console.log(`ðŸ“Š Rooms: ${roomCount}`);

        const giftCount = await Gift.countDocuments();
        console.log(`ðŸ“Š Gifts: ${giftCount}`);

        if (giftCount === 0) {
            console.log('âš ï¸ No gifts found. Seeding...');
            require('./seedGifts');
        }

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

verifyAll();






