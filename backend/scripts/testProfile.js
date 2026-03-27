// Run with: node scripts/testProfile.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');

async function testProfile() {
    try {
        const mongoUri = process.env.MONGO_URI;
        if (!mongoUri) {
            throw new Error('MONGO_URI not found in environment variables');
        }
        await mongoose.connect(mongoUri);
        console.log('âœ… Connected to MongoDB');

        const user1 = await User.findOne({ username: 'testuser' });
        const user2 = await User.findOne({ username: 'testuser2' });

        if (!user1 || !user2) {
            console.log('âŒ Test users not found');
            process.exit(1);
        }

        console.log(`\nðŸ‘¤ Testing profiles:`);
        console.log(`  User1: ${user1.username}`);
        console.log(`  User2: ${user2.username}`);

        // Test game stats update
        console.log('\nðŸŽ® Updating game stats...');
        if (!user1.gameStats) user1.gameStats = {};
        if (!user1.gameStats.werewolf) {
            user1.gameStats.werewolf = { played: 0, won: 0, level: 1 };
        }
        user1.gameStats.werewolf.played += 1;
        user1.gameStats.werewolf.won += 1;
        user1.gameStats.werewolf.level = Math.floor(user1.gameStats.werewolf.won / 10) + 1;
        await user1.save();
        console.log(`âœ… Updated werewolf stats for ${user1.username}`);

        // Test badge addition
        console.log('\nðŸ… Adding badge...');
        if (!user1.badges) user1.badges = [];
        user1.badges.push({
            id: 'welcome_badge',
            name: 'Welcome',
            description: 'Joined Friend Circle',
            icon: 'ðŸŽ‰',
            rarity: 'common',
            earnedAt: Date.now()
        });
        await user1.save();
        console.log(`âœ… Added badge to ${user1.username}`);

        // Test profile visit
        console.log('\nðŸ‘¥ Recording profile visit...');
        if (!user2.profileVisitors) user2.profileVisitors = [];
        user2.profileVisitors.unshift({
            userId: user1._id,
            visitedAt: Date.now(),
            message: 'Nice profile!'
        });
        await user2.save();
        console.log(`âœ… ${user1.username} visited ${user2.username}'s profile`);

        // Get profile data
        console.log('\nðŸ“Š Profile data:');
        console.log(`  ${user1.username} has ${user1.badges?.length || 0} badges`);
        console.log(`  ${user2.username} has ${user2.profileVisitors?.length || 0} visitors`);

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testProfile();






