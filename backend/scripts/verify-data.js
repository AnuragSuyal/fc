const mongoose = require('mongoose');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

async function verifyData() {
    try {
        const mongoUri = process.env.MONGO_URI;
        if (!mongoUri) {
            throw new Error('MONGO_URI not found in environment variables');
        }

        await mongoose.connect(mongoUri);
        console.log('âœ… Connected to MongoDB');

        // Check collections
        const collections = await mongoose.connection.db.listCollections().toArray();
        console.log('\nðŸ“š Collections found:');
        collections.forEach(c => console.log(`  â€¢ ${c.name}`));

        // Count documents
        const User = require('../src/models/User');
        const Room = require('../src/models/Room');
        const Gift = require('../src/models/Gift');
        const Transaction = require('../src/models/Transaction');

        const userCount = await User.countDocuments();
        const roomCount = await Room.countDocuments();
        const giftCount = await Gift.countDocuments();
        const txCount = await Transaction.countDocuments();

        console.log('\nðŸ“Š Document counts:');
        console.log(`  Users: ${userCount}`);
        console.log(`  Rooms: ${roomCount}`);
        console.log(`  Gifts: ${giftCount}`);
        console.log(`  Transactions: ${txCount}`);

        if (giftCount === 0) {
            console.log('\nâš ï¸ No gifts found! You may need to run seeding.');
        }

        // Check for duplicate daily rewards today
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const tomorrow = new Date(today);
        tomorrow.setDate(tomorrow.getDate() + 1);

        const todayTx = await Transaction.countDocuments({
            type: 'daily_bonus',
            createdAt: { $gte: today, $lt: tomorrow }
        });

        console.log(`\nðŸ“… Daily rewards today: ${todayTx}`);

        // Check for users with multiple daily rewards today
        const duplicates = await Transaction.aggregate([
            {
                $match: {
                    type: 'daily_bonus',
                    createdAt: { $gte: today, $lt: tomorrow }
                }
            },
            {
                $group: {
                    _id: '$userId',
                    count: { $sum: 1 }
                }
            },
            {
                $match: {
                    count: { $gt: 1 }
                }
            }
        ]);

        if (duplicates.length > 0) {
            console.log('âŒ ALERT: Found', duplicates.length, 'users with duplicate rewards today!');
        } else {
            console.log('âœ… No duplicate rewards found for any user today.');
        }

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error.message);
        process.exit(1);
    }
}

verifyData();






