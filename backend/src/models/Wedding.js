const mongoose = require('mongoose');

const weddingSchema = new mongoose.Schema({
    // Couple
    proposerId:  { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    partnerId:   { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    // Status
    status: {
        type: String,
        enum: ['pending', 'accepted', 'active', 'divorced', 'expired'],
        default: 'pending'
    },

    // Ring that was used for proposal
    ring: {
        name:      String,
        icon:      { type: String, default: '💍' },
        rarity:    { type: String, enum: ['common', 'rare', 'epic', 'legendary'], default: 'common' },
        coinsSpent: { type: Number, default: 0 }
    },

    // Ceremony
    ceremony: {
        roomId:    { type: mongoose.Schema.Types.ObjectId, ref: 'Room' },
        date:      Date,
        guestCount: { type: Number, default: 0 },
        blessings:  [{ userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' }, message: String, createdAt: { type: Date, default: Date.now } }]
    },

    // Anniversary
    marriedAt:  { type: Date },
    expiresAt:  { type: Date },   // null = permanent
    divorcedAt: { type: Date },

    // Stats
    stats: {
        giftsExchanged: { type: Number, default: 0 },
        roomsVisited:   { type: Number, default: 0 },
        totalBlessings: { type: Number, default: 0 }
    },

    createdAt: { type: Date, default: Date.now },
    updatedAt: { type: Date, default: Date.now }
});

weddingSchema.pre('save', function() { this.updatedAt = Date.now(); });
weddingSchema.index({ proposerId: 1 });
weddingSchema.index({ partnerId:  1 });
weddingSchema.index({ status: 1 });

module.exports = mongoose.model('Wedding', weddingSchema);


