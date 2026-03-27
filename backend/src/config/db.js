const mongoose = require('mongoose');

const connectDB = async () => {
  try {
    const uri = process.env.MONGO_URI || process.env.MONGODB_URI;
    const conn = await mongoose.connect(uri);
    console.log(`âœ… MongoDB Connected: ${conn.connection.host}`);
  } catch (error) {
    console.error(`âŒ MongoDB Connection Error: ${error.message}`);
    process.exit(1);
  }
};

module.exports = connectDB;






