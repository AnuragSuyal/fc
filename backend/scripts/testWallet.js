// Run with: node scripts/testWallet.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');
const Transaction = require('../src/models/Transaction');

async function testWallet() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… Connected to MongoDB');

        let user = await User.findOne({ username: 'testuser' });
        if (!user) {
            console.log('Test user not found, creating one...');
            user = await User.create({
                username: 'testuser',
                email: 'testuser@example.com',
                password: 'password123',
                coins: 0,
                gems: 0
            });
        }

        console.log(`\nðŸ‘¤ Test user: ${user.username}`);
        console.log(`ðŸ’° Initial balance: ${user.coins} coins, ${user.gems} gems`);

        // Test purchase
        console.log('\nðŸ’³ Testing coin purchase...');
        user.coins += 1000;
        await user.save();

        const transaction = new Transaction({
            userId: user._id,
            type: 'purchase_coins',
            amount: { coins: 1000 },
            balanceBefore: { coins: user.coins - 1000, gems: user.gems },
            balanceAfter: { coins: user.coins, gems: user.gems },
            description: 'Test purchase',
            status: 'completed',
            completedAt: Date.now()
        });
        await transaction.save();

        console.log(`âœ… New balance: ${user.coins} coins`);

        // Get transactions
        const transactions = await Transaction.find({ userId: user._id })
            .sort({ createdAt: -1 })
            .limit(5);

        console.log(`\nðŸ“‹ Last ${transactions.length} transactions:`);
        transactions.forEach(t => {
            console.log(`  [${t.type}] ${t.description}: ${t.amount.coins} coins`);
        });

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testWallet();






