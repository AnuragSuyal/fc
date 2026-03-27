// Run with: node scripts/testRankings.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');
const rankingService = require('../src/services/rankingService');

async function testRankings() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… Connected to MongoDB');

        await rankingService.initialize();
        console.log('âœ… Ranking service initialized');

        const users = await User.find().limit(5);
        console.log(`\nðŸ‘¤ Found ${users.length} test users`);

        if (users.length < 2) {
            console.log('Not enough test users found. Skipping tests.');
            process.exit(0);
        }

        // Simulate gift sends
        console.log('\nðŸŽ Simulating gift sends...');
        for (let i = 0; i < 10; i++) {
            const sender = users[Math.floor(Math.random() * users.length)];
            const receiver = users[Math.floor(Math.random() * users.length)];
            const value = Math.floor(Math.random() * 100) + 50;

            await rankingService.updateGiftRanking(sender._id.toString(), value);
            await rankingService.updateCharmRanking(receiver._id.toString(), value);
        }
        console.log('âœ… Gift rankings updated');

        // Simulate game wins
        console.log('\nðŸŽ® Simulating game wins...');
        const games = ['werewolf', 'drawing', 'karaoke', 'uno'];
        for (let i = 0; i < 20; i++) {
            const user = users[Math.floor(Math.random() * users.length)];
            const game = games[Math.floor(Math.random() * games.length)];

            await rankingService.updateGameRanking(user._id.toString(), game, true);
        }
        console.log('âœ… Game rankings updated');

        // Get rankings
        console.log('\nðŸ“Š Gift Rankings (all-time):');
        const giftRankings = await rankingService.getRankings('gifts', 'alltime', 5);
        giftRankings.forEach(r => {
            console.log(`  #${r.rank} ${r.username}: ${r.score} gifts`);
        });

        console.log('\nðŸ“Š Charm Rankings (all-time):');
        const charmRankings = await rankingService.getRankings('charm', 'alltime', 5);
        charmRankings.forEach(r => {
            console.log(`  #${r.rank} ${r.username}: ${r.score} charm`);
        });

        console.log('\nðŸ“Š Werewolf Rankings (all-time):');
        const werewolfRankings = await rankingService.getRankings('game:werewolf', 'alltime', 5);
        werewolfRankings.forEach(r => {
            console.log(`  #${r.rank} ${r.username}: ${r.score} wins`);
        });

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testRankings();






