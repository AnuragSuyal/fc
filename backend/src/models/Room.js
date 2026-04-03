const mongoose = require('mongoose');
const { recalculateRoomPresenceState } = require('../services/roomPresenceService');

const colorClashStakeSchema = new mongoose.Schema({
    currency: {
        type: String,
        enum: ['none', 'coins'],
        default: 'none'
    },
    entryFee: {
        type: Number,
        default: 0,
        min: 0
    },
    payouts: {
        type: [{
            place: {
                type: Number,
                min: 1,
                required: true
            },
            bps: {
                type: Number,
                min: 1,
                max: 10000,
                required: true
            }
        }],
        default: () => [{ place: 1, bps: 10000 }]
    },
    houseFeeBps: {
        type: Number,
        default: 500,
        min: 0,
        max: 10000
    },
    sinkFeeBps: {
        type: Number,
        default: 200,
        min: 0,
        max: 10000
    }
}, { _id: false });

const colorClashRulesSchema = new mongoose.Schema({
    startingHandSize: {
        type: Number,
        default: 7,
        min: 3,
        max: 12
    },
    timeoutStrikeLimit: {
        type: Number,
        default: 3,
        min: 1,
        max: 5
    },
    customCards: {
        shield: {
            type: Boolean,
            default: false
        },
        echo: {
            type: Boolean,
            default: false
        },
        swap: {
            type: Boolean,
            default: false
        }
    }
}, { _id: false });

const colorClashGameConfigSchema = new mongoose.Schema({
    gameId: {
        type: String,
        default: 'color_clash'
    },
    lobbyStatus: {
        type: String,
        enum: ['open', 'countdown', 'matched', 'in_progress', 'rematch', 'cancelled', 'finished'],
        default: 'open'
    },
    tableMode: {
        type: String,
        enum: ['casual_free', 'gold_stake', 'friend_room', 'ranked', 'custom_chaos'],
        default: 'friend_room'
    },
    visibility: {
        type: String,
        enum: ['public', 'private', 'invite_only'],
        default: 'private'
    },
    allowSpectators: {
        type: Boolean,
        default: true
    },
    minPlayersToStart: {
        type: Number,
        default: 2,
        min: 2,
        max: 8
    },
    maxPlayers: {
        type: Number,
        default: 4,
        min: 2,
        max: 8
    },
    countdownSec: {
        type: Number,
        default: 6,
        min: 3,
        max: 30
    },
    turnTimeoutSec: {
        type: Number,
        default: 25,
        min: 5,
        max: 90
    },
    themePackId: {
        type: String,
        default: 'forest_picnic'
    },
    rules: {
        type: colorClashRulesSchema,
        default: () => ({})
    },
    stake: {
        type: colorClashStakeSchema,
        default: () => ({})
    },
    seasonId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashSeason',
        default: null
    },
    invitedUserIds: [{
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }],
    activeMatchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        default: null
    },
    lastCompletedMatchId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'ColorClashMatch',
        default: null
    }
}, { _id: false });

const MAX_STAGE_SEATS = 8;

const idsEqual = (left, right) => {
    if (!left || !right) return false;
    return left.toString() === right.toString();
};

const roomSeatStateSchema = new mongoose.Schema({
    seatIndex: {
        type: Number,
        required: true,
        min: 1,
        max: MAX_STAGE_SEATS
    },
    occupiedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    isLocked: {
        type: Boolean,
        default: false
    },
    lockedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    lockedAt: {
        type: Date,
        default: null
    },
    lockReason: {
        type: String,
        default: ''
    },
    seatType: {
        type: String,
        default: 'speaker'
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
}, { _id: false });

const miniDrawPointSchema = new mongoose.Schema({
    x: {
        type: Number,
        required: true,
        min: 0,
        max: 1
    },
    y: {
        type: Number,
        required: true,
        min: 0,
        max: 1
    }
}, { _id: false });

const miniDrawStrokeSchema = new mongoose.Schema({
    strokeId: {
        type: String,
        required: true
    },
    toolType: {
        type: String,
        enum: ['pen', 'eraser'],
        default: 'pen'
    },
    colorValue: {
        type: Number,
        default: 0xFFFFFFFF
    },
    thickness: {
        type: Number,
        default: 3,
        min: 1,
        max: 24
    },
    points: {
        type: [miniDrawPointSchema],
        default: () => []
    },
    createdByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    },
    version: {
        type: Number,
        default: 0
    },
    isVisible: {
        type: Boolean,
        default: true
    }
}, { _id: false });

const miniDrawRedoStackSchema = new mongoose.Schema({
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    strokeIds: {
        type: [String],
        default: () => []
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
}, { _id: false });

const miniDrawStateSchema = new mongoose.Schema({
    sessionId: {
        type: String,
        default: ''
    },
    isUnlocked: {
        type: Boolean,
        default: false
    },
    unlockCostCoins: {
        type: Number,
        default: 300
    },
    unlockedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    unlockedAt: {
        type: Date,
        default: null
    },
    enabled: {
        type: Boolean,
        default: true
    },
    accessPolicy: {
        type: String,
        enum: ['all_participants', 'host_admin', 'view_only'],
        default: 'all_participants'
    },
    version: {
        type: Number,
        default: 0
    },
    strokes: {
        type: [miniDrawStrokeSchema],
        default: () => []
    },
    redoStacks: {
        type: [miniDrawRedoStackSchema],
        default: () => []
    },
    lastClearedByUserId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        default: null
    },
    lastClearedAt: {
        type: Date,
        default: null
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
}, { _id: false });

const normalizeSeatStatesForRoom = (room) => {
    const existingSeatStates = Array.isArray(room.seatStates)
        ? room.seatStates
        : [];
    const lockedSeatSet = new Set(
        (Array.isArray(room.lockedSeats) ? room.lockedSeats : [])
            .map((seatIndex) => Number(seatIndex))
            .filter((seatIndex) => Number.isInteger(seatIndex) && seatIndex >= 1 && seatIndex <= MAX_STAGE_SEATS)
    );
    const participantBySeat = new Map();

    for (const participant of room.participants || []) {
        const seatIndex = Number(participant?.seatIndex);
        if (!Number.isInteger(seatIndex) || seatIndex < 1 || seatIndex > MAX_STAGE_SEATS) {
            continue;
        }
        participantBySeat.set(seatIndex, participant.userId || null);
    }

    const now = new Date();
    const nextSeatStates = [];

    for (let seatIndex = 1; seatIndex <= MAX_STAGE_SEATS; seatIndex += 1) {
        const existing = existingSeatStates.find((entry) => Number(entry?.seatIndex) === seatIndex) || {};
        const occupiedByUserId = participantBySeat.get(seatIndex) || null;
        const seatType = existing.seatType || (room.type === 'video' && seatIndex === 1 ? 'host_reserved' : 'speaker');
        const isLocked = existing.isLocked === true || lockedSeatSet.has(seatIndex);
        const nextState = {
            seatIndex,
            occupiedByUserId,
            isLocked,
            lockedByUserId: isLocked ? (existing.lockedByUserId || null) : null,
            lockedAt: isLocked ? (existing.lockedAt || now) : null,
            lockReason: isLocked ? String(existing.lockReason || '') : '',
            seatType,
            updatedAt: existing.updatedAt || now
        };

        const changed = (
            !idsEqual(existing.occupiedByUserId, nextState.occupiedByUserId) ||
            existing.isLocked !== nextState.isLocked ||
            !idsEqual(existing.lockedByUserId, nextState.lockedByUserId) ||
            String(existing.lockReason || '') !== nextState.lockReason ||
            String(existing.seatType || '') !== nextState.seatType
        );

        if (changed) {
            nextState.updatedAt = now;
        }

        nextSeatStates.push(nextState);
    }

    room.seatStates = nextSeatStates;
    room.lockedSeats = nextSeatStates
        .filter((seat) => seat.isLocked)
        .map((seat) => seat.seatIndex);
};

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
    ownerId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        index: true
    },
    isPermanent: {
        type: Boolean,
        default: false
    },
    archivedAt: Date,
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
    mode: {
        type: String,
        enum: ['normal', 'acquaint', 'auction'],
        default: 'normal'
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
    topic: {
        type: String,
        trim: true,
        maxlength: 120,
        default: ''
    },
    language: {
        type: String,
        trim: true,
        maxlength: 16,
        default: 'en'
    },
    roomRules: {
        type: String,
        maxlength: 500,
        default: ''
    },

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
        allowAdminSeatControl: {
            type: Boolean,
            default: true
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
        youtubeSyncedAt: Date,
        youtubeActiveVideoId: {
            type: String,
            default: ''
        },
        youtubeSessionVersion: {
            type: Number,
            default: 0
        }
    },

    gameConfig: {
        type: colorClashGameConfigSchema,
        default: null
    },

    miniDraw: {
        type: miniDrawStateSchema,
        default: () => ({})
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
        isPresent: {
            type: Boolean,
            default: true
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
    seatStates: {
        type: [roomSeatStateSchema],
        default: () => []
    },
    lockedSeats: [{
        type: Number,
        min: 0
    }],
    reports: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        targetUserId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User',
            default: null
        },
        type: {
            type: String,
            enum: ['room', 'user'],
            default: 'room'
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
    hostPresent: {
        type: Boolean,
        default: false
    },
    adminCount: {
        type: Number,
        default: 0
    },
    activeControllersCount: {
        type: Number,
        default: 0
    },
    roomActive: {
        type: Boolean,
        default: false
    },
    inactiveSince: {
        type: Date,
        default: null
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
    if (!this.mode) {
        this.mode = this.type === 'auction'
            ? 'auction'
            : this.type === 'chat'
                ? 'acquaint'
                : 'normal';
    }
    if (this.rallyActive && this.rallyExpiresAt && this.rallyExpiresAt <= new Date()) {
        this.rallyActive = false;
    }
    this.participantCount = this.participants.filter((participant) => participant.isPresent !== false).length;
    recalculateRoomPresenceState(this);
    this.onlineCount = this.participants.filter((participant) => participant.isPresent !== false).length;
    normalizeSeatStatesForRoom(this);
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
roomSchema.index(
    { ownerId: 1, isPermanent: 1 },
    {
        unique: true,
        partialFilterExpression: {
            ownerId: { $exists: true },
            isPermanent: true
        }
    }
);
roomSchema.index({ groupId: 1, endedAt: 1 });
roomSchema.index({ type: 1, 'gameConfig.gameId': 1, 'gameConfig.tableMode': 1, endedAt: 1, showInExplore: 1 });
roomSchema.index({ 'gameConfig.activeMatchId': 1 });

module.exports = mongoose.model('Room', roomSchema);
