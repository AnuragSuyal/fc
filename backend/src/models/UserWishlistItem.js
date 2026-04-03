const mongoose = require('mongoose');

const userWishlistItemSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    itemId: {
        type: String,
        required: true,
        index: true
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

userWishlistItemSchema.index({ userId: 1, itemId: 1 }, { unique: true });

module.exports = mongoose.model('UserWishlistItem', userWishlistItemSchema);
