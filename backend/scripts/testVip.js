// Run with: node scripts/testVip.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');
const vipLevels = require('../src/config/vipLevels');

mongoose.connect(process.env.MONGODB_URI)
    .then(async () => {
        console.log('Connected to MongoDB');

        // Test VIP levels
        console.log('\n=== VIP LEVELS ===');
        vipLevels.forEach(level => {
            console.log(`Level ${level.level}: ${level.name} - Min spend: $${level.minSpend / 100}`);
            console.log(`  Benefits: ${level.benefits.length}`);
        });

        // Find a test user
        const user = await User.findOne({ username: 'testuser' });
        if (user) {
            console.log('\n=== TEST USER ===');
            console.log(`Username: ${user.username}`);
            console.log(`Current VIP Level: ${user.vipLevel}`);
            console.log(`Total Spent: $${(user.totalSpent || 0) / 100}`);

            // Calculate next level
            const currentLevel = vipLevels.find(l => l.level === user.vipLevel) || vipLevels[0];
            const nextLevel = vipLevels.find(l => l.level === user.vipLevel + 1);

            if (nextLevel) {
                const needed = nextLevel.minSpend - (user.totalSpent || 0);
                console.log(`Next Level: ${nextLevel.name} - Need $${needed / 100} more`);
            }
        } else {
            console.log('\n=== NO TEST USER FOUND ===');
            console.log('Will proceed testing VIP and Economy locally via integration tests anyway.\n');
        }

        process.exit(0);
    })
    .catch(err => {
        console.error('Error:', err);
        process.exit(1);
    });






