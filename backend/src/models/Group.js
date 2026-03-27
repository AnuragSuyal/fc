const mongoose = require('mongoose');

const groupSchema = new mongoose.Schema({
    // Basic Info
    name: {
        type: String,
        required: true,
        trim: true,
        minlength: 3,
        maxlength: 50
    },
    tag: {
        type: String,
        unique: true,
        required: true,
        uppercase: true,
        minlength: 3,
        maxlength: 8
    },
    description: {
        type: String,
        maxlength: 500,
        default: ''
    },
    motto: {
        type: String,
        maxlength: 100,
        default: ''
    },

    // Leadership
    leaderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },
    admins: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],

    // Members
    members: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        role: {
            type: String,
            enum: ['leader', 'admin', 'member'],
            default: 'member'
        },
        joinedAt: {
            type: Date,
            default: Date.now
        }
    }],
    memberCount: {
        type: Number,
        default: 0
    },
    maxMembers: {
        type: Number,
        default: 50
    },

    // Group Type
    type: {
        type: String,
        enum: ['small', 'large', 'epic'],
        default: 'small'
    },

    // Stats
    stats: {
        totalXp: {
            type: Number,
            default: 0
        },
        totalGames: {
            type: Number,
            default: 0
        },
        totalWins: {
            type: Number,
            default: 0
        },
        rank: {
            type: Number,
            default: 0
        }
    },

    // Economy
    coins: {
        type: Number,
        default: 0
    },
    treasureChest: {
        lastClaimed: {
            type: Date
        },
        available: {
            type: Boolean,
            default: false
        }
    },

    // Store
    store: [{
        itemId: {
            type: mongoose.Schema.Types.ObjectId
        },
        name: String,
        price: Number,
        available: {
            type: Boolean,
            default: true
        }
    }],

    // Appearance
    avatar: {
        type: String,
        default: ''
    },
    coverImage: {
        type: String,
        default: ''
    },

    // Privacy
    isPublic: {
        type: Boolean,
        default: true
    },
    approvalRequired: {
        type: Boolean,
        default: false
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

// Update timestamps and counts
groupSchema.pre('save', async function () {
    this.updatedAt = Date.now();
    this.memberCount = this.members.length;
});

// Generate unique tag from name
groupSchema.pre('validate', async function () {
    if (this.name && !this.tag) {
        // Generate tag from name (uppercase, max 8 chars)
        const baseTag = this.name
            .toString()
            .replace(/[^a-zA-Z0-9]/g, '')
            .toUpperCase()
            .substring(0, 5);
        const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
        this.tag = (baseTag + random).substring(0, 8);
    }
});

// Indexes
groupSchema.index({ 'stats.rank': 1 });
groupSchema.index({ memberCount: -1 });
groupSchema.index({ isPublic: 1, createdAt: -1 });

module.exports = mongoose.model('Group', groupSchema);






