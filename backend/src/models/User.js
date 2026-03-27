const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const Counter = require('./Counter');

const USER_UID_SEQUENCE = 'user_uid';
const USER_UID_START = 1000000;
const missingUidQuery = {
    $or: [
        { uid: { $exists: false } },
        { uid: null },
        { uid: '' }
    ]
};

const allocateNextUserUid = async () => {
    const counter = await Counter.findByIdAndUpdate(
        USER_UID_SEQUENCE,
        {
            $setOnInsert: { seq: USER_UID_START - 1 },
            $inc: { seq: 1 }
        },
        {
            new: true,
            upsert: true,
            setDefaultsOnInsert: true
        }
    );

    return counter.seq.toString();
};

const assignUserUid = async (user) => {
    if (user.uid) return user.uid;
    user.uid = await allocateNextUserUid();
    return user.uid;
};

const userSchema = new mongoose.Schema({
    // Basic Info
    username: {
        type: String,
        required: true,
        unique: true,
        trim: true,
        minlength: 3,
        maxlength: 20
    },
    uid: {
        type: String,
        required: true,
        trim: true
    },
    email: {
        type: String,
        unique: true,
        sparse: true,
        lowercase: true,
        match: [/^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/, 'Please fill a valid email address']
    },
    phone: {
        type: String,
        unique: true,
        sparse: true
    },
    password: {
        type: String,
        required: true,
        select: false // Don't return password by default
    },

    // Profile
    avatar: {
        type: String,
        default: 'default-avatar.png'
    },
    avatarUploadHistory: {
        type: [Date],
        default: []
    },
    coverPhoto: {
        type: String,
        default: 'default-cover.jpg'
    },
    bio: {
        type: String,
        maxlength: 500
    },

    // Profile views/visitors
    profileVisitors: [{
        userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
        visitedAt: { type: Date, default: Date.now },
        message: String
    }],

    // Game statistics
    gameStats: {
        werewolf: {
            played: { type: Number, default: 0 },
            won: { type: Number, default: 0 },
            level: { type: Number, default: 1 },
            speed: String,
            logic: String
        },
        drawing: {
            played: { type: Number, default: 0 },
            won: { type: Number, default: 0 },
            level: { type: Number, default: 1 },
            speed: String
        },
        karaoke: {
            played: { type: Number, default: 0 },
            won: { type: Number, default: 0 },
            level: { type: Number, default: 1 },
            pitch: String
        },
        uno: {
            played: { type: Number, default: 0 },
            won: { type: Number, default: 0 },
            level: { type: Number, default: 1 },
            strategy: String
        }
    },

    // Level & Progression
    level: {
        type: Number,
        default: 1
    },
    xp: {
        type: Number,
        default: 0
    },

    // Currency
    coins: {
        type: Number,
        default: 100 // Welcome bonus
    },
    gems: {
        type: Number,
        default: 0
    },
    tickets: {
        type: Number,
        default: 0
    },

    // VIP
    vipLevel: {
        type: Number,
        default: 0, // 0 = no VIP, 1-12 = VIP levels
        index: true
    },
    vipExpiry: {
        type: Date
    },
    vipPurchasedAt: Date,

    // Streak system
    loginStreak: {
        type: Number,
        default: 0
    },
    lastLoginDate: {
        type: Date,
        default: Date.now
    },
    longestStreak: {
        type: Number,
        default: 0
    },

    quests: [{
        questId: String,
        title: String,
        description: String,
        type: { type: String }, // 'daily', 'weekly', 'achievement'
        target: Number,
        progress: { type: Number, default: 0 },
        completed: { type: Boolean, default: false },
        claimed: { type: Boolean, default: false },
        reward: {
            coins: Number,
            gems: Number,
            xp: Number,
            badge: String
        },
        expiresAt: Date,
        startedAt: { type: Date, default: Date.now },
        completedAt: Date
    }],

    // Daily reward tracking
    dailyRewardClaimed: { type: Boolean, default: false },
    lastDailyReward: Date,
    dailyRewardDay: { type: Number, default: 1 }, // 1-30 day cycle

    // Badges
    badges: [{
        id: String,
        name: String,
        description: String,
        icon: String,
        rarity: String, // common, rare, epic, legendary
        earnedAt: {
            type: Date,
            default: Date.now
        }
    }],

    // Social
    friends: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    friendRequests: [{
        from: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        status: {
            type: String,
            enum: ['pending', 'accepted', 'rejected'],
            default: 'pending'
        },
        sentAt: {
            type: Date,
            default: Date.now
        }
    }],
    blockedUsers: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    followers: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    following: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],

    // Location & Discovery
    location: {
        type: {
            type: String,
            enum: ['Point'],
            default: 'Point'
        },
        coordinates: {
            type: [Number],
            default: [0, 0] // [longitude, latitude]
        }
    },
    lastLocationUpdate: {
        type: Date,
        default: Date.now
    },
    locationSharing: {
        type: Boolean,
        default: false
    },
    visibilityRadius: {
        type: Number,
        default: 10 // in kilometers
    },

    // Status
    status: {
        isOnline: {
            type: Boolean,
            default: false
        },
        lastActive: {
            type: Date,
            default: Date.now
        },
        currentRoom: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room'
        }
    },

    // Settings
    settings: {
        notifications: {
            friendOnline: { type: Boolean, default: true },
            messages: { type: Boolean, default: true },
            gifts: { type: Boolean, default: true },
            gameInvites: { type: Boolean, default: true },
            eventReminders: { type: Boolean, default: false },
            sound: { type: Boolean, default: true },
            vibrate: { type: Boolean, default: true }
        },
        privacy: {
            showOnline: { type: Boolean, default: true },
            showActivity: { type: Boolean, default: true },
            allowFriendRequests: { type: Boolean, default: true },
            showLocation: { type: Boolean, default: false }
        },
        quietHours: {
            enabled: { type: Boolean, default: false },
            start: { type: String, default: '22:00' },
            end: { type: String, default: '08:00' }
        },
        language: { type: String, default: 'en' },
        currency: { type: String, default: 'USD' }
    },

    // Referral
    referralCode: {
        type: String,
        unique: true
    },
    referredBy: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    },

    // Stats
    stats: {
        giftsSent: {
            type: Number,
            default: 0
        },
        giftsReceived: {
            type: Number,
            default: 0
        },
        totalSpent: {
            type: Number,
            default: 0
        },
        roomsCreated: {
            type: Number,
            default: 0
        }
    },

    // Total spent tracking (for VIP levels)
    totalSpent: { type: Number, default: 0 }, // in cents
    totalCoinsSpent: { type: Number, default: 0 },
    totalGemsSpent: { type: Number, default: 0 },

    // Timestamps
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    },
    deletedAt: {
        type: Date
    }
});

// Add geospatial index for location
userSchema.index({ location: '2dsphere' });
userSchema.index({ uid: 1 }, { unique: true, sparse: true });

// Allocate a permanent public UID once for every user.
userSchema.pre('validate', async function () {
    if (!this.uid) {
        await assignUserUid(this);
    }
});

// Update timestamps and Hash password before saving
userSchema.pre('save', async function () {
    this.updatedAt = Date.now();

    if (!this.isModified('password')) return;

    try {
        const saltRounds = Number(process.env.BCRYPT_SALT_ROUNDS || 12);
        const salt = await bcrypt.genSalt(saltRounds);
        this.password = await bcrypt.hash(this.password, salt);
    } catch (error) {
        throw error;
    }
});

// Method to compare passwords
userSchema.methods.comparePassword = async function (candidatePassword) {
    return await bcrypt.compare(candidatePassword, this.password);
};

// Method to add XP and handle level up
userSchema.methods.addXP = async function (amount) {
    this.xp += amount;

    // Simple leveling logic: level = floor(sqrt(xp / 100)) + 1
    // or: xpRequired = level * level * 100
    const newLevel = Math.floor(Math.sqrt(this.xp / 100)) + 1;

    if (newLevel > this.level) {
        this.level = newLevel;
        return true; // Level up
    }
    return false;
};

userSchema.statics.findByIdOrUid = function (identifier) {
    const normalized = String(identifier || '').trim();

    if (!normalized) {
        return this.findOne({ _id: null });
    }

    if (mongoose.Types.ObjectId.isValid(normalized)) {
        return this.findOne({
            $or: [
                { _id: normalized },
                { uid: normalized }
            ]
        });
    }

    return this.findOne({ uid: normalized });
};

userSchema.statics.backfillMissingUids = async function ({ batchSize = 100 } = {}) {
    let updated = 0;

    while (true) {
        const users = await this.find(missingUidQuery)
            .select('_id uid')
            .limit(batchSize);

        if (users.length === 0) {
            break;
        }

        for (const user of users) {
            const uid = await assignUserUid(user);
            const result = await this.updateOne(
                {
                    _id: user._id,
                    ...missingUidQuery
                },
                {
                    $set: {
                        uid,
                        updatedAt: new Date()
                    }
                }
            );

            updated += result.modifiedCount || 0;
        }

        if (users.length < batchSize) {
            break;
        }
    }

    return updated;
};

// Method to return user data without sensitive info
userSchema.methods.toJSON = function () {
    const user = this.toObject();
    delete user.password;
    delete user.avatarUploadHistory;
    return user;
};

module.exports = mongoose.model('User', userSchema);




