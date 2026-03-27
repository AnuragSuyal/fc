const mongoose = require('mongoose');

const paymentEventSchema = new mongoose.Schema({
    eventId: {
        type: String,
        required: true,
        unique: true, // Critical for idempotency
        index: true
    },
    type: String,
    status: {
        type: String,
        enum: ['processed', 'failed'],
        default: 'processed'
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },
    amount: Number,
    currency: String,
    error: String,
    createdAt: {
        type: Date,
        default: Date.now,
        expires: '30d' // Keep records for 30 days
    }
});

module.exports = mongoose.model('PaymentEvent', paymentEventSchema);






