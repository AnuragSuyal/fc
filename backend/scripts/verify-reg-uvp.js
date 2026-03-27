const mongoose = require('mongoose');
require('dotenv').config({ path: '../.env' });

async function verifyRegistration() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/friendcircle');
        console.log('âœ… Connected to MongoDB');

        const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }));
        const user = await User.findOne({ email: 'uvp@test.com' });

        if (user) {
            console.log('ðŸ“Š Registration Verification:');
            console.log(`- Username: ${user.username}`);
            console.log(`- Email: ${user.email}`);
            console.log(`- Coins: ${user.coins} (Expected: 100)`);
            console.log(`- Password Hashed: ${user.password.startsWith('$2') ? 'YES' : 'NO'}`);
            console.log(`- CreatedAt: ${user.createdAt}`);

            if (user.coins === 100 && user.password.startsWith('$2')) {
                console.log('\nâœ… DATABASE VERIFICATION PASSED');
            } else {
                console.log('\nâŒ DATABASE VERIFICATION FAILED');
            }
        } else {
            console.log('âŒ User not found in database');
        }

        await mongoose.connection.close();
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

verifyRegistration();






