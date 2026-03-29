const { z } = require('zod');

const registerSchema = z.object({
    username: z.string().min(3).max(20).regex(/^[a-zA-Z0-9_]+$/, 'Username can only contain letters, numbers, and underscores'),
    email: z.string().email(),
    password: z.string().min(8).regex(/^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d@$!%*?&._-]{8,}$/, 'Password must contain at least one letter and one number'),
    phone: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Invalid phone format (must be E.164, e.g., +1234567890)').optional()
});

const loginSchema = z.object({
    email: z.string().email(),
    password: z.string()
});

const sendGiftSchema = z.object({
    toUserId: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid recipient ID'),
    giftId: z.string()
        .min(1, 'Gift ID is required')
        .max(80, 'Invalid gift ID')
        .regex(/^[A-Za-z0-9_-]+$/, 'Invalid gift ID'),
    roomId: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid room ID').optional(),
    message: z.string().max(100).optional(),
    broadcast: z.boolean().optional()
});

const phoneSchema = z.object({
    phone: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Invalid phone format (must be E.164, e.g., +1234567890)')
});

const verifyOtpSchema = z.object({
    phone: z.string().regex(/^\+[1-9]\d{1,14}$/, 'Invalid phone format'),
    otp: z.string().length(6, 'OTP must be 6 digits')
});

const createRoomSchema = z.object({
    name: z.string().min(3).max(50),
    description: z.string().max(200).optional(),
    announcement: z.string().max(500).optional(),
    type: z.enum(['voice', 'music', 'video', 'chat', 'auction', 'game']).optional(),
    mode: z.enum(['normal', 'acquaint', 'auction']).optional(),
    category: z.enum(['all', 'voice', 'music', 'video', 'chat', 'battle', 'auction']).optional(),
    tags: z.array(z.string().max(20)).max(5).optional(),
    settings: z.object({
        isPrivate: z.boolean().optional(),
        password: z.string().optional(),
        maxParticipants: z.number().min(2).max(1000).optional(),
        entryFee: z.number().min(0).optional(),
        hdVoice: z.boolean().optional(),
        banTextChat: z.boolean().optional(),
        banPhotoChat: z.boolean().optional(),
        banRedPacket: z.boolean().optional(),
        allowGifts: z.boolean().optional(),
        allowScreenShare: z.boolean().optional(),
        allowVideo: z.boolean().optional(),
        stageJoinsLocked: z.boolean().optional(),
        allowAdminSeatControl: z.boolean().optional(),
        maxActiveSpeakers: z.number().int().min(1).max(8).optional(),
        requireApproval: z.boolean().optional(),
        slowMode: z.number().min(0).optional(),
        ageRestricted: z.boolean().optional()
    }).optional(),
    theme: z.object({
        background: z.string().optional(),
        coverImage: z.string().url().optional(),
        music: z.string().url().optional(),
        musicTitle: z.string().max(120).optional(),
        musicLoop: z.boolean().optional(),
        youtubeUrl: z.string().url().optional(),
        youtubeTitle: z.string().max(160).optional(),
        youtubeThumbnail: z.string().url().optional(),
        youtubePositionMs: z.number().int().min(0).optional(),
        youtubePlaybackState: z.enum(['paused', 'playing']).optional(),
        youtubeQueue: z.array(
            z.object({
                videoId: z.string().max(32).optional(),
                url: z.string().url(),
                title: z.string().max(160).optional(),
                thumbnailUrl: z.string().url().optional(),
                durationMs: z.number().int().min(0).optional(),
                addedBy: z.string().optional(),
                addedAt: z.union([z.string(), z.date()]).optional()
            })
        ).optional()
    }).optional()
});

const updateRoomSchema = createRoomSchema.partial().extend({
    announcement: z.string().max(500).optional()
});

const createPostSchema = z.object({
    content: z.string().max(2000).optional(),
    images: z.array(
        z.object({
            url: z.string().url(),
            thumbnail: z.string().url().optional()
        })
    ).max(9).optional(),
    type: z.enum(['normal', 'achievement', 'event']).optional(),
    metadata: z.record(z.string(), z.any()).optional()
}).refine(data => {
    const hasContent = typeof data.content === 'string' && data.content.trim().length > 0;
    const hasImages = Array.isArray(data.images) && data.images.length > 0;
    return hasContent || hasImages;
}, {
    message: "Post must have content or images"
});

const sendDirectMessageSchema = z.object({
    recipientId: z.string().min(1).max(64),
    content: z.string().min(1).max(5000),
    type: z.enum(['text', 'image', 'voice', 'gift', 'system', 'emoji', 'private_image']).optional(),
    replyTo: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid message ID').optional(),
    metadata: z.record(z.string(), z.any()).optional()
});

const sendRoomMessageSchema = z.object({
    roomId: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid room ID'),
    content: z.string().min(1).max(5000),
    type: z.enum(['text', 'image', 'voice', 'gift', 'system', 'emoji', 'private_image']).optional(),
    replyTo: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid message ID').optional(),
    metadata: z.record(z.string(), z.any()).optional()
});

const sendGroupMessageSchema = z.object({
    groupId: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid group ID'),
    content: z.string().min(1).max(5000),
    type: z.enum(['text', 'image', 'voice', 'gift', 'system', 'emoji', 'private_image']).optional(),
    replyTo: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid message ID').optional(),
    metadata: z.record(z.string(), z.any()).optional()
});

const inviteRoomFriendSchema = z.object({
    targetUserId: z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid user ID')
});

const createGroupSchema = z.object({
    name: z.string().min(3).max(50),
    description: z.string().max(500).optional(),
    motto: z.string().max(100).optional(),
    avatar: z.string().url().optional(),
    isPublic: z.boolean().optional(),
    maxMembers: z.number().min(10).max(500).optional(),
    approvalRequired: z.boolean().optional(),
    type: z.enum(['small', 'large', 'epic']).optional(),
    vibe: z.string().max(40).optional(),
    invitedFriendIds: z.array(
        z.string().regex(/^[0-9a-fA-F]{24}$/, 'Invalid friend ID')
    ).max(24).optional()
});

const updateProfileSchema = z.object({
    bio: z.string().max(500).optional(),
    avatar: z.string().url().optional(),
    coverPhoto: z.string().url().optional(),
    region: z.string().max(60).optional()
});

const updateLocationSchema = z.object({
    latitude: z.number().min(-90).max(90),
    longitude: z.number().min(-180).max(180),
    sharing: z.boolean().optional(),
    radius: z.number().min(0).max(100).optional()
});

const updateSettingsSchema = z.object({
    notifications: z.object({
        friendOnline: z.boolean().optional(),
        messages: z.boolean().optional(),
        gifts: z.boolean().optional(),
        gameInvites: z.boolean().optional(),
        eventReminders: z.boolean().optional(),
        sound: z.boolean().optional(),
        vibrate: z.boolean().optional()
    }).optional(),
    privacy: z.object({
        showOnline: z.boolean().optional(),
        showActivity: z.boolean().optional(),
        allowFriendRequests: z.boolean().optional(),
        showLocation: z.boolean().optional()
    }).optional(),
    quietHours: z.object({
        enabled: z.boolean().optional(),
        start: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/).optional(),
        end: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/).optional()
    }).optional(),
    language: z.string().length(2).optional(),
    currency: z.string().length(3).optional()
});

const changePasswordSchema = z.object({
    currentPassword: z.string().min(1),
    newPassword: z.string().min(8).regex(/^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d@$!%*?&._-]{8,}$/, 'Password must contain at least one letter and one number')
});
const updateUserSchema = z.object({
    username: z.string().min(3).max(20).regex(/^[a-zA-Z0-9_]+$/, 'Username can only contain letters, numbers, and underscores').optional(),
    bio: z.string().max(500).optional(),
    avatar: z.string().url().optional(),
    region: z.string().max(60).optional(),
    settings: updateSettingsSchema.optional()
});
const purchaseVipSchema = z.object({
    level: z.number().int().min(1).max(13),
    period: z.enum(['monthly', 'annual']).optional()
});

module.exports = {
    registerSchema,
    loginSchema,
    sendGiftSchema,
    phoneSchema,
    verifyOtpSchema,
    createRoomSchema,
    updateRoomSchema,
    createPostSchema,
    sendDirectMessageSchema,
    sendRoomMessageSchema,
    sendGroupMessageSchema,
    inviteRoomFriendSchema,
    createGroupSchema,
    updateProfileSchema,
    updateLocationSchema,
    purchaseVipSchema,
    updateSettingsSchema,
    changePasswordSchema,
    updateUserSchema
};
