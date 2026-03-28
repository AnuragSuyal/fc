const mongoose = require('mongoose');

const roomSchema = new mongoose.Schema({
    // Basic Info
    name: {
        type: String,
        required: true,
        trim: true,
        minlength: 3,
        maxlength: 50
    },
    description: {
        type: String,
        maxlength: 200,
        default: ''
    },
    roomId: {
        type: String,
        required: true
    }, // Display ID like "1698332" - auto-generated
    groupId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Group',
        index: true
    },
    showInExplore: {
        type: Boolean,
        default: true
    },

    // Type & Category
    type: {
        type: String,
        enum: ['voice', 'music', 'video', 'chat', 'auction', 'game'],
        default: 'voice'
    },
    category: {
        type: String,
        enum: ['all', 'voice', 'music', 'video', 'chat', 'battle', 'auction'],
        default: 'all'
    },
    tags: [{
        type: String,
        maxlength: 20
    }],

    // Hosting
    hostId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    level: {
        type: Number,
        default: 1
    },
    exp: {
        type: Number,
        default: 0
    },
    expToday: {
        type: Number,
        default: 0
    },
    region: {
        type: String,
        default: 'Global'
    },
    fans: {
        type: Number,
        default: 0
    },
    followers: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    coHosts: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    moderators: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],

    // Settings
    settings: {
        isPrivate: {
            type: Boolean,
            default: false
        },
        password: {
            type: String,
            select: false // Don't return password by default
        },
        maxParticipants: {
            type: Number,
            default: 20,
            min: 2,
            max: 1000
        },
        entryFee: {
            type: Number,
            default: 0,
            min: 0
        },
        hdVoice: {
            type: Boolean,
            default: false
        },
        banTextChat: {
            type: Boolean,
            default: false
        },
        banPhotoChat: {
            type: Boolean,
            default: false
        },
        banRedPacket: {
            type: Boolean,
            default: false
        },
        allowGifts: {
            type: Boolean,
            default: true
        },
        allowScreenShare: {
            type: Boolean,
            default: false
        },
        allowVideo: {
            type: Boolean,
            default: false
        },
        stageJoinsLocked: {
            type: Boolean,
            default: false
        },
        maxActiveSpeakers: {
            type: Number,
            default: 8,
            min: 1,
            max: 8
        },
        requireApproval: {
            type: Boolean,
            default: false
        },
        slowMode: {
            type: Number,
            default: 0 // 0 = off, seconds between messages
        },
        ageRestricted: {
            type: Boolean,
            default: false
        }
    },

    // Moderation
    bans: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        reason: String,
        bannedAt: {
            type: Date,
            default: Date.now
        },
        expiresAt: Date
    }],
    mutes: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        expiresAt: Date
    }],

    // Economy
    economy: {
        totalEarned: {
            type: Number,
            default: 0
        },
        todayEarned: {
            type: Number,
            default: 0
        },
        topContributors: [{
            userId: {
                type: mongoose.Schema.Types.ObjectId,
                ref: 'User'
            },
            amount: Number,
            gifts: Number
        }]
    },

    // Theme & Appearance
    theme: {
        background: {
            type: String,
            default: 'default'
        },
        coverImage: String,
        music: String,
        musicTitle: String,
        musicLoop: {
            type: Boolean,
            default: false
        },
        youtubeUrl: String,
        youtubeTitle: String,
        youtubeThumbnail: String,
        youtubeQueue: [{
            videoId: String,
            url: String,
            title: String,
            thumbnailUrl: String,
            durationMs: {
                type: Number,
                default: 0
            },
            addedBy: String,
            addedAt: {
                type: Date,
                default: Date.now
            }
        }],
        youtubePositionMs: {
            type: Number,
            default: 0
        },
        youtubePlaybackState: {
            type: String,
            enum: ['paused', 'playing'],
            default: 'paused'
        },
        youtubeSyncedAt: Date
    },

    // Current State
    participants: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        role: {
            type: String,
            enum: ['host', 'cohost', 'moderator', 'speaker', 'listener'],
            default: 'listener'
        },
        seatIndex: {
            type: Number,
            default: -1 // -1 means they are just listeners, not on a seat
        },
        joinedAt: {
            type: Date,
            default: Date.now
        },
        lastActive: {
            type: Date,
            default: Date.now
        },
        isMuted: {
            type: Boolean,
            default: false
        },
        isDeafened: {
            type: Boolean,
            default: false
        },
        isSpeaking: {
            type: Boolean,
            default: false
        },
        raisedHand: {
            type: Boolean,
            default: false
        },
        contribution: {
            type: Number,
            default: 0
        } // points earned in this room
    }],
    lockedSeats: [{
        type: Number,
        min: 0
    }],
    reports: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        reason: {
            type: String,
            default: 'spam'
        },
        createdAt: {
            type: Date,
            default: Date.now
        }
    }],
    participantCount: {
        type: Number,
        default: 0
    },
    onlineCount: {
        type: Number,
        default: 0
    },

    // Voice Stream (for LiveKit integration later)
    stream: {
        provider: String, // 'livekit' or 'agora'
        roomName: String,
        token: String,
        serverUrl: String
    },

    // Announcement
    announcement: {
        text: String,
        updatedAt: {
            type: Date,
            default: Date.now
        },
        updatedBy: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        }
    },

    // Metrics
    metrics: {
        followers: {
            type: Number,
            default: 0
        },
        totalVisits: {
            type: Number,
            default: 0
        },
        peakParticipants: {
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
        }
    },

    // Featured (for admin use)
    featured: {
        type: Boolean,
        default: false
    },
    featuredUntil: Date,
    rallyActive: {
        type: Boolean,
        default: false
    },
    rallyExpiresAt: Date,

    // Timestamps
    createdAt: {
        type: Date,
        default: Date.now
    },
    startedAt: Date,
    endedAt: Date,
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

// Generate unique room ID before validation
roomSchema.pre('validate', async function () {
    if (!this.roomId) {
        let isUnique = false;
        while (!isUnique) {
            const potentialId = Math.floor(1000000 + Math.random() * 9000000).toString();
            const existingRoom = await mongoose.models.Room.findOne({ roomId: potentialId });
            if (!existingRoom) {
                this.roomId = potentialId;
                isUnique = true;
            }
        }
    }
});

// Update timestamps and participant counts before save
roomSchema.pre('save', async function () {
    this.updatedAt = Date.now();
    if (this.rallyActive && this.rallyExpiresAt && this.rallyExpiresAt <= new Date()) {
        this.rallyActive = false;
    }
    this.participantCount = this.participants.length;
    this.onlineCount = this.participants.filter(p =>
        p.lastActive > new Date(Date.now() - 5 * 60 * 1000) // Active in last 5 minutes
    ).length;
});

// Indexes for faster queries
roomSchema.index({ hostId: 1 });
roomSchema.index({ 'participants.userId': 1 });
roomSchema.index({ type: 1 });
roomSchema.index({ category: 1 });
roomSchema.index({ createdAt: -1 });
roomSchema.index({ featured: -1 });
roomSchema.index({ rallyActive: -1, rallyExpiresAt: -1 });
roomSchema.index({ onlineCount: -1 });
roomSchema.index({ roomId: 1 }, { unique: true });
roomSchema.index({ groupId: 1, endedAt: 1 });

module.exports = mongoose.model('Room', roomSchema);
