require('dotenv').config();
const { MongoClient } = require('mongodb');

async function run() {
    const uri = process.env.MONGODB_URI || process.env.MONGO_URI;
    const client = new MongoClient(uri);
    try {
        await client.connect();
        console.log('Connected to MongoDB');
        const db = client.db();
        const users = db.collection('users');

        const email = 'auth_17727376@test.com';
        const user = await users.findOne({ email });
        console.log('User raw:', user.username, 'Coins:', user.coins);

        await users.updateOne({ email }, { $set: { coins: 3333 } });
        console.log('Updated to 3333');

        const updated = await users.findOne({ email });
        console.log('Verified raw coins:', updated.coins);

        process.exit(0);
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
}

run();






