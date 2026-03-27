const mongoose = require('mongoose');
const User = require('./src/models/User');
const dotenv = require('dotenv');
dotenv.config();

async function repro() {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('Connected to DB');

    try {
        const user = await User.findOne({ email: 'tester1@test.com' });
        console.log('User found:', user ? user.username : 'null');
        if (user) {
            user.status.isOnline = true;
            await user.save();
            console.log('User saved');
        }
    } catch (err) {
        console.error('Error during repro:', err);
    } finally {
        await mongoose.disconnect();
    }
}

repro();






