const { MongoClient } = require('mongodb');

async function main() {
    const uri = "mongodb://localhost:27017";
    const client = new MongoClient(uri);

    try {
        await client.connect();
        const database = client.db('friendcircle');
        const users = database.collection('users');

        const result = await users.updateMany(
            {},
            {
                $set: {
                    loginStreak: 0,
                    longestStreak: 0,
                    dailyRewardDay: 1,
                    totalSpent: 0,
                    vipLevel: 0
                }
            }
        );

        console.log(`Matched ${result.matchedCount} documents and updated ${result.modifiedCount} documents.`);
    } finally {
        await client.close();
    }
}

main().catch(console.dir);






