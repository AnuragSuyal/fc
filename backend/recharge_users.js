const mongoose = require('mongoose');
const dotenv = require('dotenv');
const User = require('./src/models/User');

dotenv.config();

async function recharge() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('Connected to MongoDB');

        const result = await User.updateMany(
            { username: { $in: ['tester1', 'tester2'] } },
            { $set: { coins: 10000, gems: 1000 } }
        );

        console.log(`Recharged ${result.modifiedCount} users.`);
        process.exit(0);
    } catch (error) {
        console.error('Error recharging users:', error);
        process.exit(1);
    }
}

recharge();






