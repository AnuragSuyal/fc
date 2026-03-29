const mongoose = require('mongoose');

const colorClashTierSchema = new mongoose.Schema({
    id: {
        type: String,
        required: true,
        trim: true
    },
    name: {
        type: String,
        required: true,
        trim: true
    },
    order: {
        type: Number,
        required: true,
        min: 1
    },
    minRating: {
        type: Number,
        required: true,
        min: 0
    },
    maxRating: {
        type: Number,
        required: true,
        min: 0
    },
    divisions: {
        type: Number,
        default: 3,
        min: 1,
        max: 6
    },
    starsPerDivision: {
        type: Number,
        default: 4,
        min: 1,
        max: 10
    },
    rewardSnapshot: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    }
}, { _id: false });

const colorClashSeasonSchema = new mongoose.Schema({
    key: {
        type: String,
        required: true,
        unique: true,
        trim: true
    },
    name: {
        type: String,
        required: true,
        trim: true
    },
    status: {
        type: String,
        enum: ['upcoming', 'active', 'settling', 'archived'],
        default: 'upcoming',
        index: true
    },
    startsAt: {
        type: Date,
        required: true,
        index: true
    },
    endsAt: {
        type: Date,
        required: true,
        index: true
    },
    finalizeAt: {
        type: Date,
        required: true
    },
    placementMatches: {
        type: Number,
        default: 5,
        min: 0,
        max: 20
    },
    rankedEnabled: {
        type: Boolean,
        default: true
    },
    tiers: {
        type: [colorClashTierSchema],
        default: []
    },
    ratingConfig: {
        baseRating: {
            type: Number,
            default: 1000
        },
        kFactor: {
            type: Number,
            default: 32
        },
        streakBonus: {
            type: Number,
            default: 4
        },
        placementMultiplier: {
            type: Number,
            default: 1.5
        },
        inactivityDecay: {
            type: Number,
            default: 0
        }
    },
    rewardConfig: {
        seasonRewards: {
            type: [mongoose.Schema.Types.Mixed],
            default: []
        },
        leaderboardRewards: {
            type: [mongoose.Schema.Types.Mixed],
            default: []
        }
    },
    themeRotation: {
        type: [String],
        default: () => ['forest_picnic', 'neon_orbit', 'candy_carnival']
    },
    finalLeaderboard: {
        type: [{
            userId: {
                type: mongoose.Schema.Types.ObjectId,
                ref: 'User'
            },
            rank: Number,
            rating: Number
        }],
        default: []
    }
}, {
    timestamps: true
});

colorClashSeasonSchema.index({ status: 1, startsAt: 1, endsAt: 1 });
colorClashSeasonSchema.index({ endsAt: 1, finalizeAt: 1 });

module.exports = mongoose.model('ColorClashSeason', colorClashSeasonSchema);
