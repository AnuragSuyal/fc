const mongoose = require('mongoose');

const colorClashPlayerSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    seatIndex: {
        type: Number,
        required: true
    },
    usernameSnapshot: String,
    avatarSnapshot: String,
    status: {
        type: String,
        enum: ['joined', 'ready', 'active', 'disconnected', 'spectator', 'forfeited', 'finished'],
        default: 'active'
    }
}, { _id: false });

const colorClashPlayerContextSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    ipHash: {
        type: String,
        default: null
    },
    deviceHash: {
        type: String,
        default: null
    },
    region: {
        type: String,
        default: ''
    }
}, { _id: false });

const colorClashMatchSchema = new mongoose.Schema({
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        required: true
    },
    gameId: {
        type: String,
        default: 'color_clash',
        index: true
    },
    status: {
        type: String,
        enum: ['pending', 'countdown', 'dealing', 'active', 'round_end', 'completed', 'cancelled', 'invalidated'],
        default: 'pending',
        index: true
    },
    tableMode: {
        type: String,
        enum: ['casual_free', 'gold_stake', 'friend_room', 'ranked', 'custom_chaos'],
        default: 'friend_room'
    },
    seasonId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashSeason',
        default: null
    },
    configSnapshot: {
        type: mongoose.Schema.Types.Mixed,
        default: {}
    },
    players: {
        type: [colorClashPlayerSchema],
        default: []
    },
    playerContexts: {
        type: [colorClashPlayerContextSchema],
        default: []
    },
    currentRoundNumber: {
        type: Number,
        default: 1
    },
    version: {
        type: Number,
        default: 1
    },
    publicState: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    roundResult: {
        type: mongoose.Schema.Types.Mixed,
        default: null
    },
    settlement: {
        status: {
            type: String,
            enum: ['none', 'holds_created', 'locked', 'refund_pending', 'refunded', 'settling', 'settled', 'failed', 'skipped'],
            default: 'none'
        },
        settlementKey: {
            type: String,
            default: null
        },
        currency: {
            type: String,
            enum: ['none', 'coins'],
            default: 'none'
        },
        entryFee: {
            type: Number,
            default: 0
        },
        totalEscrowed: {
            type: Number,
            default: 0
        },
        grossPool: {
            type: Number,
            default: 0
        },
        houseFee: {
            type: Number,
            default: 0
        },
        sinkAmount: {
            type: Number,
            default: 0
        },
        totalPaidOut: {
            type: Number,
            default: 0
        },
        refundedAmount: {
            type: Number,
            default: 0
        },
        payouts: {
            type: [{
                userId: {
                    type: mongoose.Schema.Types.ObjectId,
                    ref: 'User'
                },
                place: Number,
                amount: Number,
                transactionId: {
                    type: mongoose.Schema.Types.ObjectId,
                    ref: 'Transaction'
                }
            }],
            default: []
        },
        error: {
            type: String,
            default: null
        },
        lockedAt: Date,
        settledAt: Date,
        refundedAt: Date
    },
    profileStatsAppliedAt: {
        type: Date,
        default: null
    },
    rankProgression: {
        status: {
            type: String,
            enum: ['pending', 'applied', 'failed', 'skipped'],
            default: 'pending'
        },
        seasonId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'ColorClashSeason',
            default: null
        },
        appliedAt: Date,
        leaderboardSyncedAt: Date,
        leaderboardSyncError: {
            type: String,
            default: null
        },
        error: {
            type: String,
            default: null
        },
        results: {
            type: [{
                userId: {
                    type: mongoose.Schema.Types.ObjectId,
                    ref: 'User'
                },
                placement: Number,
                ratingBefore: Number,
                ratingAfter: Number,
                ratingDelta: Number,
                tierId: String,
                division: Number,
                stars: Number
            }],
            default: []
        }
    },
    riskEvaluation: {
        matchSignalsAppliedAt: {
            type: Date,
            default: null
        },
        refundSignalsAppliedAt: {
            type: Date,
            default: null
        },
        lastProcessedAt: {
            type: Date,
            default: null
        },
        error: {
            type: String,
            default: null
        }
    },
    validStartedAt: Date,
    startedAt: Date,
    endedAt: Date,
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

colorClashMatchSchema.pre('save', function preSave() {
    this.updatedAt = new Date();
});

colorClashMatchSchema.index({ roomId: 1 });
colorClashMatchSchema.index({ seasonId: 1, createdAt: -1 });
colorClashMatchSchema.index(
    { roomId: 1, status: 1 },
    {
        unique: true,
        partialFilterExpression: {
            status: { $in: ['pending', 'countdown', 'dealing', 'active', 'round_end'] }
        }
    }
);
colorClashMatchSchema.index({ 'players.userId': 1, createdAt: -1 });
colorClashMatchSchema.index({ createdAt: -1 });
colorClashMatchSchema.index(
    { 'settlement.settlementKey': 1 },
    {
        unique: true,
        partialFilterExpression: {
            'settlement.settlementKey': { $type: 'string' }
        }
    }
);

module.exports = mongoose.model('ColorClashMatch', colorClashMatchSchema);
