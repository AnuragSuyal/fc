const mongoose = require('mongoose');
require('dotenv').config({ path: '../.env' });

async function verifyOTPUser() {
    try {
        await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/friendcircle');
        console.log('âœ… Connected to MongoDB');

        const User = mongoose.model('User', new mongoose.Schema({}, { strict: false }));
        const user = await User.findOne({ phone: '+919876543210' });

        if (user) {
            console.log('ðŸ“Š OTP Verification:');
            console.log(`- Username: ${user.username}`);
            console.log(`- Phone: ${user.phone}`);
            console.log(`- Is Verified: ${user.isVerified}`);
            console.log(`- Is Guest: ${user.isGuest}`);

            if (user.isVerified === true) {
                console.log('\nâœ… DATABASE VERIFICATION PASSED');
            } else {
                console.log('\nâŒ DATABASE VERIFICATION FAILED (isVerified not true)');
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

verifyOTPUser();






