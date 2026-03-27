const mongoose = require('mongoose');

const giftSchema = new mongoose.Schema({
    // Basic Info
    name: {
        type: String,
        required: true,
        trim: true
    },
    description: {
        type: String,
        maxlength: 200
    },
    icon: {
        type: String,
        required: true
    }, // Emoji or image URL

    // Pricing
    price: {
        coins: {
            type: Number,
            default: 0,
            min: 0
        },
        gems: {
            type: Number,
            default: 0,
            min: 0
        }
    },

    // Categorization
    category: {
        type: String,
        enum: ['simple', 'premium', 'luxury', 'legendary'],
        default: 'simple',
        required: true,
        index: true
    },
    tier: {
        type: Number,
        enum: [1, 2, 3, 4],
        default: 1,
        index: true
    },

    // Animation
    animation: {
        type: {
            type: String,
            enum: ['float', 'explode', 'screen', 'avatar', 'fly'],
            default: 'float'
        },
        duration: {
            type: Number,
            default: 3 // seconds
        },
        sound: String, // URL to sound file
        color: String, // Hex color for effect
        particleCount: {
            type: Number,
            default: 50
        },
        scale: {
            type: Number,
            default: 1.0
        }
    },

    // Effects
    effects: {
        sender: {
            xp: {
                type: Number,
                default: 10
            },
            badge: String,
            emote: String
        },
        recipient: {
            effect: String,
            duration: {
                type: Number,
                default: 5 // seconds
            },
            message: String
        },
        room: {
            background: String, // Temporary background change
            duration: {
                type: Number,
                default: 10 // seconds
            }
        }
    },

    // Availability
    availability: {
        limited: {
            type: Boolean,
            default: false
        },
        totalAvailable: {
            type: Number,
            default: 0
        },
        sold: {
            type: Number,
            default: 0
        },
        startDate: Date,
        endDate: Date
    },

    // Requirements
    requirements: {
        minLevel: {
            type: Number,
            default: 0
        },
        requiredVip: {
            type: Number,
            default: 0
        },
        achievement: String
    },

    // Stats
    stats: {
        totalSent: {
            type: Number,
            default: 0,
            index: true
        },
        uniqueSenders: {
            type: Number,
            default: 0
        },
        uniqueRecipients: {
            type: Number,
            default: 0
        },
        popularityRank: {
            type: Number,
            default: 0
        }
    },

    // Status
    active: {
        type: Boolean,
        default: true,
        index: true
    },

    // Timestamps
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

// Update timestamp on save
giftSchema.pre('save', async function () {
    this.updatedAt = Date.now();
});

// Indexes
giftSchema.index({ category: 1, tier: 1 });
giftSchema.index({ 'price.coins': 1 });
giftSchema.index({ 'stats.totalSent': -1 });
giftSchema.index({ active: 1, 'availability.endDate': 1 });

module.exports = mongoose.model('Gift', giftSchema);






