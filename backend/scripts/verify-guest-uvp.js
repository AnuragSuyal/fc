const mongoose = require('mongoose');
require('dotenv').config({ path: '../.env' });

async function verifyGuestUser() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/friendcircle');
        console.log('âœ… Connected to MongoDB');

        const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }));
        const user = await User.findOne({ username: /^Guest_/ });

        if (user) {
            console.log('ðŸ“Š Guest Verification:');
            console.log(`- Username: ${user.username}`);
            console.log(`- Coins: ${user.coins} (Expected: 50)`);

            if (user.username.startsWith('Guest_') && user.coins === 50) {
                console.log('\nâœ… DATABASE VERIFICATION PASSED');
            } else {
                console.log('\nâŒ DATABASE VERIFICATION FAILED');
            }
        } else {
            console.log('âŒ Guest user not found in database');
        }

        await mongoose.connection.close();
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

verifyGuestUser();






