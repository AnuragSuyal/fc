const mongoose = require('mongoose');
const User = require('../src/models/User');
const dotenv = require('dotenv');
dotenv.config();

async function verify() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/friendcircle');
        console.log('âœ… Connected to MongoDB');

        const count = await User.countDocuments();
        console.log(`ðŸ“Š User Count: ${count}`);

        const latestUser = await User.findOne().sort({ createdAt: -1 });
        if (latestUser) {
            console.log('ðŸ“„ Latest User:', JSON.stringify({
                username: latestUser.username,
                email: latestUser.email,
                coins: latestUser.coins
            }, null, 2));
        } else {
            console.log('âŒ No users found');
        }

        await mongoose.disconnect();
    } catch (err) {
        console.error('âŒ Verification failed:', err);
        process.exit(1);
    }
}

verify();






