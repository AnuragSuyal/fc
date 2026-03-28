const mongoose = require('mongoose');

const postSchema = new mongoose.Schema({
    // Author
    userId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true,
        index: true
    },

    // Content
    content: {
        type: String,
        required: function () {
            return !Array.isArray(this.images) || this.images.length === 0;
        },
        trim: true,
        maxlength: 2000
    },
    images: [{
        url: String,
        thumbnail: String
    }],

    // Type
    type: {
        type: String,
        enum: ['normal', 'achievement', 'event'],
        default: 'normal'
    },

    // Engagement
    likes: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        createdAt: {
            type: Date,
            default: Date.now
        }
    }],
    likeCount: {
        type: Number,
        default: 0
    },

    comments: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        content: {
            type: String,
            required: true,
            maxlength: 500
        },
        createdAt: {
            type: Date,
            default: Date.now
        },
        updatedAt: Date
    }],
    commentCount: {
        type: Number,
        default: 0
    },

    // Mentions
    mentions: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        username: String
    }],

    // Metadata (for special posts)
    metadata: {
        achievementId: String,
        roomId: { type: mongoose.Schema.Types.ObjectId, ref: 'Room' },
        eventName: String
    },

    // Stats
    views: {
        type: Number,
        default: 0
    },
    viewers: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        viewedAt: {
            type: Date,
            default: Date.now
        }
    }],

    // Status
    isEdited: {
        type: Boolean,
        default: false
    },
    isDeleted: {
        type: Boolean,
        default: false,
        index: true
    },

    // Timestamps
    createdAt: {
        type: Date,
        default: Date.now,
        index: true
    },
    updatedAt: {
        type: Date,
        default: Date.now
    }
});

// Update timestamps and counts
// Update timestamps and counts
// Update timestamps and counts
// Update timestamps and counts
postSchema.pre('save', async function () {
    this.updatedAt = Date.now();
    this.likeCount = this.likes.length;
    this.commentCount = this.comments.length;
});

// Extract mentions from content
postSchema.pre('save', async function () {
    if (this.isModified('content')) {
        const mentionRegex = /@(\w+)/g;
        const matches = [...this.content.matchAll(mentionRegex)];

        if (matches.length > 0) {
            const User = mongoose.model('User');
            const usernames = matches.map(m => m[1]);

            try {
                const users = await User.find({
                    username: { $in: usernames }
                }).select('_id username');

                this.mentions = users.map(u => ({
                    userId: u._id,
                    username: u.username
                }));
            } catch (err) {
                console.error('Post mentions extraction error:', err);
            }
        }
    }
});

// Indexes
postSchema.index({ userId: 1, createdAt: -1 });
postSchema.index({ 'mentions.userId': 1 });
postSchema.index({ 'viewers.userId': 1 });

module.exports = mongoose.model('Post', postSchema);




