// Run with: node scripts/seedGifts.js
require('dotenv').config();
const mongoose = require('mongoose');
const Gift = require('../src/models/Gift');
const giftCatalog = require('../src/utils/giftCatalog');

mongoose.connect(process.env.MONGO_URI)
    .then(async () => {
        console.log('Connected to MongoDB');

        // Clear existing gifts
        await Gift.deleteMany({});
        console.log('Cleared existing gifts');

        // Insert new gifts
        await Gift.insertMany(giftCatalog);
        console.log(`Seeded ${giftCatalog.length} gifts`);

        process.exit(0);
    })
    .catch(err => {
        console.error('Error:', err);
        process.exit(1);
    });






