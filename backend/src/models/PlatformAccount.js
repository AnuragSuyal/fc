const mongoose = require('mongoose');

const platformAccountSchema = new mongoose.Schema({
    key: {
        type: String,
        required: true,
        unique: true,
        index: true
    },
    label: {
        type: String,
        default: 'Platform Account'
    },
    balanceCoins: {
        type: Number,
        default: 0
    },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    }
}, {
    timestamps: true
});

module.exports = mongoose.model('PlatformAccount', platformAccountSchema);
