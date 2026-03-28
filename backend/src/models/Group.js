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
    vibe: {
        type: String,
        default: 'Orbit'
    },
    announcement: {
        type: String,
        maxlength: 200,
        default: ''
    },

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
    invitations: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        invitedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        status: {
            type: String,
            enum: ['pending', 'accepted', 'rejected', 'cancelled'],
            default: 'pending'
        },
        invitedAt: {
            type: Date,
            default: Date.now
        },
        respondedAt: Date
    }],
    joinRequests: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        message: {
            type: String,
            maxlength: 120,
            default: ''
        },
        requestedAt: {
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
        totalMessages: {
            type: Number,
            default: 0
        },
        totalGifts: {
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
    linkedRoomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room',
        index: true
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
    },
    lastActivityAt: {
        type: Date,
        default: Date.now
    }
});

// Update timestamps and counts
groupSchema.pre('save', async function () {
    this.updatedAt = Date.now();
    this.memberCount = this.members.length;
    if (!this.lastActivityAt) {
        this.lastActivityAt = Date.now();
    }
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
groupSchema.index({ lastActivityAt: -1 });
groupSchema.index({ 'invitations.userId': 1, 'invitations.status': 1 });
groupSchema.index({ 'joinRequests.userId': 1 });

module.exports = mongoose.model('Group', groupSchema);




