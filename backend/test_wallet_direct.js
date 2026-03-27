require('dotenv').config();
const mongoose = require('mongoose');
const User = require('./src/models/User');
const Transaction = require('./src/models/Transaction');
const connectDB = require('./src/config/db');

async function run() {
    try {
        await connectDB();
        console.log('Connected to DB');

        const email = 'auth_17727376@test.com';
        const user = await User.findOne({ email });

        let workingUser = user;
        if (!workingUser) {
            console.log('User not found, creating test user...');
            workingUser = new User({
                username: 'auth_17727376',
                email,
                password: 'password123'
            });
            await workingUser.save();
        }

        console.log('User:', workingUser.username, 'Current Coins:', workingUser.coins);

        const coinsToAdd = 1000;
        workingUser.coins = (workingUser.coins || 0) + coinsToAdd;

        console.log('Attempting to update user with coins using updateOne...');
        await User.updateOne({ _id: workingUser._id }, { $set: { coins: workingUser.coins } });
        console.log('User updated successfully');

        const updatedUser = await User.findById(workingUser._id);
        console.log('Verified coins in DB (after updateOne):', updatedUser.coins);

        const tx = new Transaction({
            userId: workingUser._id,
            type: 'purchase_coins',
            amount: { coins: coinsToAdd },
            balanceBefore: { coins: workingUser.coins - coinsToAdd, gems: workingUser.gems },
            balanceAfter: { coins: workingUser.coins, gems: workingUser.gems },
            status: 'completed'
        });
        await tx.save();
        console.log('Transaction saved successfully, ID:', tx._id);

        const txCheck = await Transaction.findById(tx._id);
        console.log('Verified transaction in DB:', txCheck ? 'Found' : 'NOT FOUND');

        process.exit(0);
    } catch (e) {
        console.error('Error:', e);
        process.exit(1);
    }
}

run();






