// Run with: node scripts/testLocation.js
require('dotenv').config();
const mongoose = require('mongoose');
const User = require('../src/models/User');

async function testLocation() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('âœ… Connected to MongoDB');

        // Create test users with different locations
        const users = [
            { username: 'user1', lat: 40.7128, lng: -74.0060 }, // NYC
            { username: 'user2', lat: 40.7580, lng: -73.9855 }, // NYC (close)
            { username: 'user3', lat: 34.0522, lng: -118.2437 }, // LA (far)
            { username: 'user4', lat: 40.7129, lng: -74.0061 }, // NYC (very close)
        ];

        for (const u of users) {
            await User.findOneAndUpdate(
                { username: u.username },
                {
                    username: u.username,
                    email: `${u.username}@test.com`,
                    password: 'password123',
                    location: {
                        type: 'Point',
                        coordinates: [u.lng, u.lat]
                    },
                    locationSharing: true
                },
                { upsert: true, new: true }
            );
        }

        console.log('âœ… Test users created with locations');

        // Test nearby query for user1
        const user1 = await User.findOne({ username: 'user1' });

        const nearby = await User.aggregate([
            {
                $geoNear: {
                    near: {
                        type: 'Point',
                        coordinates: user1.location.coordinates
                    },
                    distanceField: 'distance',
                    maxDistance: 5000, // 5km
                    spherical: true,
                    query: {
                        username: { $ne: 'user1' },
                        locationSharing: true
                    }
                }
            },
            { $project: { username: 1, distance: 1 } }
        ]);

        console.log('\nðŸ“ Nearby users within 5km:');
        nearby.forEach(u => {
            console.log(`  ${u.username} - ${(u.distance / 1000).toFixed(2)}km away`);
        });

        process.exit(0);
    } catch (error) {
        console.error('âŒ Error:', error);
        process.exit(1);
    }
}

testLocation();






