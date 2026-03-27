// Run with: node scripts/testFriends.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');

async function testFriends() {
    try {
        const mongoUri = process.env.MONGO_URI;
        if (!mongoUri) {
            throw new Error('MONGO_URI not found in environment variables');
        }
        await mongoose.connect(mongoUri);
        console.log('âœ… Connected to MongoDB');

        // Create test users
        const users = [
            { username: 'alice', email: 'alice@test.com' },
            { username: 'bob', email: 'bob@test.com' },
            { username: 'charlie', email: 'charlie@test.com' },
        ];

        for (const u of users) {
            await User.findOneAndUpdate(
                { username: u.username },
                {
                    username: u.username,
                    email: u.email,
                    password: 'password123',
                },
                { upsert: true, new: true }
            );
        }

        console.log('âœ… Test users created');

        const alice = await User.findOne({ username: 'alice' });
        const bob = await User.findOne({ username: 'bob' });
        const charlie = await User.findOne({ username: 'charlie' });

        // Test friend request flow
        console.log('\nðŸ“¨ Testing friend request flow...');

        // Bob sends request to Alice
        alice.friendRequests.push({
            from: bob._id,
            status: 'pending'
        });
        await alice.save();
        console.log('âœ… Friend request sent from Bob to Alice');

        // Alice accepts
        const request = alice.friendRequests.find(
            r => r.from.toString() === bob._id.toString()
        );
        request.status = 'accepted';
        alice.friends.push(bob._id);
        bob.friends.push(alice._id);

        await alice.save();
        await bob.save();
        console.log('âœ… Friend request accepted');

        // Verify friends
        const aliceFriends = await User.findById(alice._id).populate('friends');
        console.log(`âœ… Alice has ${aliceFriends.friends.length} friend(s)`);

        // Test block
        console.log('\nðŸš« Testing block feature...');
        alice.blockedUsers.push(charlie._id);
        await alice.save();
        console.log('âœ… Alice blocked Charlie');

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testFriends();






