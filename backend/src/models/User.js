const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const Counter = require('./Counter');
const {
    buildLevelFields,
    syncUserLevelState
} = require('../services/levelingRulesService');
const {
    buildVipMembershipSnapshot,
    syncVipMembershipState
} = require('../services/vipMembershipService');

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
    let counter = await Counter.findById(USER_UID_SEQUENCE).select('seq');

    if (!counter) {
        try {
            counter = await Counter.create({
                _id: USER_UID_SEQUENCE,
                seq: USER_UID_START
            });
            return counter.seq.toString();
        } catch (error) {
            if (error?.code !== 11000) {
                throw error;
            }
        }
    }

    counter = await Counter.findByIdAndUpdate(
        USER_UID_SEQUENCE,
        {
            $inc: { seq: 1 }
        },
        {
            returnDocument: 'after'
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
    region: {
        type: String,
        trim: true,
        default: 'Global'
    },
    isGuest: {
        type: Boolean,
        default: false
    },
    isDeleted: {
        type: Boolean,
        default: false,
        index: true
    },
    isSystemAccount: {
        type: Boolean,
        default: false,
        index: true
    },
    accountState: {
        status: {
            type: String,
            enum: ['active', 'suspended', 'banned', 'deleted'],
            default: 'active',
            index: true
        },
        reason: {
            type: String,
            default: ''
        },
        updatedAt: {
            type: Date,
            default: Date.now
        }
    },
    verification: {
        isVerifiedAccount: {
            type: Boolean,
            default: false
        },
        verifiedAt: {
            type: Date,
            default: null
        }
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
        },
        colorClash: {
            played: { type: Number, default: 0 },
            won: { type: Number, default: 0 },
            casualPlayed: { type: Number, default: 0 },
            casualWon: { type: Number, default: 0 },
            level: { type: Number, default: 1 },
            rankedPlayed: { type: Number, default: 0 },
            rankedWon: { type: Number, default: 0 },
            stakePlayed: { type: Number, default: 0 },
            stakeNetCoins: { type: Number, default: 0 },
            currentRating: { type: Number, default: 0 },
            seasonBestTier: { type: String, default: '' }
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
    lastLevelUpdatedAt: {
        type: Date,
        default: Date.now
    },
    levelMilestoneTier: {
        type: String,
        default: 'default'
    },
    levelMilestoneLevel: {
        type: Number,
        default: 1
    },
    xpStats: {
        totalAwarded: {
            type: Number,
            default: 0
        },
        totalAwards: {
            type: Number,
            default: 0
        },
        roomXp: {
            type: Number,
            default: 0
        },
        socialXp: {
            type: Number,
            default: 0
        },
        rewardXp: {
            type: Number,
            default: 0
        },
        profileXp: {
            type: Number,
            default: 0
        },
        premiumXp: {
            type: Number,
            default: 0
        },
        lastAwardedAt: {
            type: Date,
            default: null
        },
        lastSourceType: {
            type: String,
            default: ''
        },
        lastAwardAmount: {
            type: Number,
            default: 0
        }
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

    shopProfile: {
        equipped: {
            profileFrameItemId: { type: String, default: '' },
            profileGlowItemId: { type: String, default: '' },
            profileBackgroundItemId: { type: String, default: '' },
            avatarBorderItemId: { type: String, default: '' },
            nameplateItemId: { type: String, default: '' },
            levelFrameSkinItemId: { type: String, default: '' },
            roomCardSkinItemId: { type: String, default: '' },
            popupCardThemeItemId: { type: String, default: '' },
            chatBubbleItemId: { type: String, default: '' },
            messageHighlightItemId: { type: String, default: '' },
            entryEffectItemId: { type: String, default: '' },
            micAuraItemId: { type: String, default: '' },
            speakingGlowItemId: { type: String, default: '' }
        },
        activeBoosts: {
            xpBoostMultiplier: { type: Number, default: 1 },
            xpBoostItemId: { type: String, default: '' },
            xpBoostExpiresAt: { type: Date, default: null },
            profileHighlightItemId: { type: String, default: '' },
            profileHighlightExpiresAt: { type: Date, default: null },
            discoverBoostItemId: { type: String, default: '' },
            discoverBoostExpiresAt: { type: Date, default: null },
            voiceAuraBoostItemId: { type: String, default: '' },
            voiceAuraBoostExpiresAt: { type: Date, default: null }
        },
        firstShopPurchaseAt: { type: Date, default: null },
        lastInventoryUpdatedAt: { type: Date, default: null },
        recentlyViewedItemIds: {
            type: [String],
            default: []
        }
    },

    // VIP
    vipTier: {
        type: String,
        default: '',
        index: true
    },
    vipStatus: {
        type: String,
        enum: ['inactive', 'active', 'expired', 'cancelled'],
        default: 'inactive'
    },
    vipStartAt: {
        type: Date,
        default: null
    },
    vipExpireAt: {
        type: Date,
        default: null
    },
    vipAutoRenew: {
        type: Boolean,
        default: false
    },
    vipPlanDuration: {
        type: String,
        enum: ['monthly', 'quarterly', 'yearly'],
        default: 'monthly'
    },
    vipPurchaseSource: {
        type: String,
        default: ''
    },
    monthlyRewardLastClaimedAt: {
        type: Date,
        default: null
    },
    vipLastUpdatedAt: {
        type: Date,
        default: Date.now
    },
    vipLevel: {
        type: Number,
        default: 0, // 0 = no active VIP, 1-13 = active tier level
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
    permanentRoomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room'
    },
    hasPermanentRoom: {
        type: Boolean,
        default: false
    },
    recentRooms: [{
        roomId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'Room',
            required: true
        },
        lastVisitedAt: {
            type: Date,
            default: Date.now
        }
    }],

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
        colorClash: {
            equippedThemePackId: { type: String, default: 'forest_picnic' },
            ownedThemePackIds: {
                type: [String],
                default: () => ['forest_picnic', 'neon_orbit', 'candy_carnival']
            },
            rankedLock: {
                active: { type: Boolean, default: false },
                reason: { type: String, default: '' },
                flagId: { type: mongoose.Schema.Types.ObjectId, ref: 'AntiFraudFlag', default: null },
                appliedAt: { type: Date, default: null }
            },
            stakeLock: {
                active: { type: Boolean, default: false },
                reason: { type: String, default: '' },
                flagId: { type: mongoose.Schema.Types.ObjectId, ref: 'AntiFraudFlag', default: null },
                appliedAt: { type: Date, default: null }
            },
            rankedAccessLocked: {
                type: Boolean,
                default: false
            },
            rankedAccessLockReason: {
                type: String,
                default: ''
            },
            stakeAccessLocked: {
                type: Boolean,
                default: false
            },
            stakeAccessLockReason: {
                type: String,
                default: ''
            },
            riskState: {
                severity: {
                    type: String,
                    enum: ['none', 'low', 'medium', 'high', 'critical'],
                    default: 'none'
                },
                score: {
                    type: Number,
                    default: 0
                },
                lastFlagType: {
                    type: String,
                    default: ''
                },
                lastAutoAction: {
                    type: String,
                    enum: ['none', 'ranked_lock', 'stake_lock', 'manual_review'],
                    default: 'none'
                },
                activeFlagCount: {
                    type: Number,
                    default: 0
                }
            },
            lastRiskActionAt: {
                type: Date,
                default: null
            },
            deviceHash: {
                type: String,
                default: ''
            },
            tutorialCompletedVersions: {
                type: [String],
                default: () => []
            }
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
userSchema.index({ permanentRoomId: 1 }, { unique: true, sparse: true });

// Allocate a permanent public UID once for every user.
userSchema.pre('validate', async function () {
    if (!this.uid) {
        await assignUserUid(this);
    }
});

// Update timestamps and Hash password before saving
userSchema.pre('save', async function () {
    this.updatedAt = Date.now();
    syncUserLevelState(this);
    syncVipMembershipState(this);

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
    const previousLevel = this.level || 1;
    this.xp = Math.max(0, Number(this.xp || 0) + Math.max(Number(amount || 0), 0));
    const syncResult = syncUserLevelState(this);
    return syncResult.newLevel > previousLevel;
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
    Object.assign(user, buildLevelFields(user));
    user.vipMembership = buildVipMembershipSnapshot(user);
    return user;
};

module.exports = mongoose.model('User', userSchema);
