// Run with: node scripts/testMessages.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');
const Message = require('../src/models/Message');

async function testMessages() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… Connected to MongoDB');

        // Get or create test users
        const user1 = await User.findOneAndUpdate(
            { username: 'testuser' },
            { username: 'testuser', email: 'test1@test.com', password: 'password123' },
            { upsert: true, new: true }
        );
        const user2 = await User.findOneAndUpdate(
            { username: 'testuser2' },
            { username: 'testuser2', email: 'test2@test.com', password: 'password123' },
            { upsert: true, new: true }
        );

        console.log(`\nðŸ‘¤ Test users:`);
        console.log(`  User1: ${user1.username} (${user1._id})`);
        console.log(`  User2: ${user2.username} (${user2._id})`);

        // Send a test message
        console.log('\nðŸ“¨ Testing message creation...');

        const message = new Message({
            senderId: user1._id,
            recipientId: user2._id,
            content: 'Hello, this is a test message!'
        });

        try {
            await message.save();
            console.log('âœ… Test message created');
        } catch (saveErr) {
            console.log('âŒ Failed to save message:', saveErr.message);
            process.exit(1);
        }

        // Get conversation
        const messages = await Message.find({
            $or: [
                { senderId: user1._id, recipientId: user2._id },
                { senderId: user2._id, recipientId: user1._id }
            ]
        }).populate('senderId', 'username avatar');

        console.log(`\nðŸ’¬ Conversation (${messages.length} messages):`);
        messages.forEach(msg => {
            console.log(`  [${msg.senderId.username}]: ${msg.content}`);
        });

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testMessages();






