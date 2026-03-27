require('dotenv').config();
const mongoose = require('mongoose');
const Room = require('./src/models/Room');

async function checkRoomCategories() {
    await mongoose.connect(process.env.MONGODB_URI);
    const result = await Room.aggregate([
        { $match: { endedAt: null } },
        { $group: { _id: "$category", count: { $sum: 1 } } }
    ]);

    console.log('Room Category Counts:', JSON.stringify(result, null, 2));
    process.exit(0);
}

checkRoomCategories().catch(err => {
    console.error(err);
    process.exit(1);
});






