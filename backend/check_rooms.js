require('dotenv').config();
const mongoose = require('mongoose');
const Room = require('./src/models/Room');

async function checkRooms() {
    await mongoose.connect(process.env.MONGODB_URI);
    const count = await Room.countDocuments({});
    const activeCount = await Room.countDocuments({ endedAt: null });
    const rooms = await Room.find({ endedAt: null }).limit(10);

    console.log(`Total Rooms: ${count}`);
    console.log(`Active Rooms: ${activeCount}`);
    console.log('Active Room Details:', JSON.stringify(rooms, null, 2));

    process.exit(0);
}

checkRooms().catch(err => {
    console.error(err);
    process.exit(1);
});






