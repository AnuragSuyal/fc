const mongoose = require('mongoose');
const dotenv = require('dotenv');
dotenv.config();

async function verifyDB() {
    await mongoose.connect(process.env.MONGODB_URI);
    const user = await mongoose.connection.db.collection('users').findOne({ username: 'testuser_postman' });
    if (user) {
        console.log('âœ… Found Postman Test User in MongoDB:', JSON.stringify({
            username: user.username,
            email: user.email,
            id: user._id
        }, null, 2));
    } else {
        console.log('âŒ Postman Test User not found in MongoDB');
    }
    await mongoose.disconnect();
}

verifyDB();






