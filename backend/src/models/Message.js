const mongoose = require('mongoose');

const messageSchema = new mongoose.Schema({
    // Message context
    roomId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Room'
    },
    senderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    recipientId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User'
    }, // for DMs
    groupId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Group'
    }, // for group chats

    // Content
    content: {
        type: String,
        required: true,
        maxlength: 5000
    },
    type: {
        type: String,
        enum: ['text', 'image', 'gift', 'system', 'announcement'],
        default: 'text'
    },

    // Gift reference
    giftId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Gift'
    },
    giftAnimation: String,

    // Mentions
    mentions: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        username: String
    }],

    // Reactions
    reactions: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        reaction: String, // emoji
        createdAt: {
            type: Date,
            default: Date.now
        }
    }],

    // Reply
    replyTo: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Message'
    },

    // Status
    isEdited: {
        type: Boolean,
        default: false
    },
    isDeleted: {
        type: Boolean,
        default: false
    },
    readBy: [{
        userId: {
            type: mongoose.Schema.Types.ObjectId,
            ref: 'User'
        },
        readAt: {
            type: Date,
            default: Date.now
        }
    }],

    // Timestamps
    createdAt: {
        type: Date,
        default: Date.now
    },
    updatedAt: {
        type: Date,
        default: Date.now
    },
    deletedAt: Date
});

// Update timestamp
messageSchema.pre('save', async function () {
    this.updatedAt = Date.now();
});

// Indexes for faster queries
messageSchema.index({ roomId: 1, createdAt: -1 });
messageSchema.index({ senderId: 1, recipientId: 1, createdAt: -1 });
messageSchema.index({ groupId: 1, createdAt: -1 });
messageSchema.index({ mentions: 1 });

module.exports = mongoose.model('Message', messageSchema);






