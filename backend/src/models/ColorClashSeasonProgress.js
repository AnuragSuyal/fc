const mongoose = require('mongoose');

const colorClashSeasonProgressSchema = new mongoose.Schema({
    seasonId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashSeason',
        required: true,
        index: true
    },
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    rating: {
        type: Number,
        default: 1000
    },
    peakRating: {
        type: Number,
        default: 1000
    },
    tierId: {
        type: String,
        default: ''
    },
    division: {
        type: Number,
        default: 1
    },
    stars: {
        type: Number,
        default: 0
    },
    placementMatchesRemaining: {
        type: Number,
        default: 0
    },
    wins: {
        type: Number,
        default: 0
    },
    losses: {
        type: Number,
        default: 0
    },
    currentStreak: {
        type: Number,
        default: 0
    },
    bestStreak: {
        type: Number,
        default: 0
    },
    timeoutLosses: {
        type: Number,
        default: 0
    },
    forfeitLosses: {
        type: Number,
        default: 0
    },
    opponentDiversityScore: {
        type: Number,
        default: 100
    },
    smurfWatch: {
        type: Boolean,
        default: false
    },
    leaderboardScore: {
        type: Number,
        default: 1000
    },
    finalRank: {
        type: Number,
        default: null
    },
    rewardStatus: {
        type: String,
        enum: ['pending', 'granted', 'claimed', 'withheld'],
        default: 'pending'
    },
    lastMatchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        default: null
    },
    recentOpponentIds: {
        type: [{
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        }],
        default: []
    }
}, {
    timestamps: true
});

colorClashSeasonProgressSchema.index({ seasonId: 1, userId: 1 }, { unique: true });
colorClashSeasonProgressSchema.index({ seasonId: 1, rating: -1, updatedAt: 1 });
colorClashSeasonProgressSchema.index({ seasonId: 1, leaderboardScore: -1, updatedAt: 1 });

module.exports = mongoose.model('ColorClashSeasonProgress', colorClashSeasonProgressSchema);
