const Post = require('../models/Post');
const User = require('../models/User');
const economyController = require('./economyController');

const normalizeImages = (images = []) => {
    if (!Array.isArray(images)) {
        return [];
    }

    return images
        .map((image) => {
            if (typeof image === 'string') {
                return { url: image };
            }

            if (image && typeof image === 'object') {
                const url = typeof image.url === 'string' ? image.url.trim() : '';
                const thumbnail =
                    typeof image.thumbnail === 'string'
                        ? image.thumbnail.trim()
                        : '';

                if (!url) {
                    return null;
                }

                return {
                    url,
                    ...(thumbnail ? { thumbnail } : {})
                };
            }

            return null;
        })
        .filter(Boolean);
};

const emitPostChanged = (req, post, action) => {
    const io = req.app.get('io');
    if (!io || !post) return;

    const ownerId =
        post.userId?._id?.toString?.() ||
        post.userId?.toString?.() ||
        '';
    if (!ownerId) return;

    io.emit('post:changed', {
        action,
        userId: ownerId,
        actorId: req.userId?.toString?.() || '',
        postId: post._id?.toString?.() || '',
        likeCount: Array.isArray(post.likes) ? post.likes.length : post.likeCount || 0,
        commentCount: Array.isArray(post.comments) ? post.comments.length : post.commentCount || 0,
        viewCount: post.views || 0,
        timestamp: new Date().toISOString()
    });
};

// @desc    Create a new post
exports.createPost = async (req, res, next) => {
    try {
        const { content, images, type, metadata } = req.body;
        const normalizedContent = typeof content === 'string' ? content.trim() : '';
        const normalizedImages = normalizeImages(images);

        const post = new Post({
            userId: req.userId,
            content: normalizedContent,
            images: normalizedImages,
            type: type || 'normal',
            metadata: metadata || {}
        });

        await post.save();
        await post.populate([
            { path: 'userId', select: 'username avatar level' },
            { path: 'mentions.userId', select: 'username avatar' }
        ]);

        if (post.mentions.length > 0) {
            const io = req.app.get('io');
            const sender = await User.findById(req.userId).select('username');
            post.mentions.forEach(mention => {
                io.to(`user:${mention.userId._id}`).emit('notification', {
                    type: 'mention',
                    postId: post._id,
                    fromUser: req.userId,
                    message: `${sender?.username || 'Someone'} mentioned you in a post`
                });
            });
        }

        const redis = req.app.get('redis');
        economyController._progressQuest(redis, req.userId, 'post_feed', 1).catch(() => {});
        emitPostChanged(req, post, 'create');

        res.status(201).json(post);
    } catch (error) {
        next(error);
    }
};

// @desc    Get feed
exports.getFeed = async (req, res, next) => {
    try {
        const { page = 1, limit = 20 } = req.query;

        const user = await User.findById(req.userId).select('friends');
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }
        const friendIds = user.friends || [];

        const query = {
            isDeleted: false,
            $or: [
                { userId: req.userId },
                { userId: { $in: friendIds } }
            ]
        };

        const posts = await Post.find(query)
            .populate('userId', 'username avatar level')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Post.countDocuments(query);
        const postsWithLikeStatus = posts.map(post => {
            const postObj = post.toObject();
            postObj.isLikedByUser = post.likes.some(like => like.userId.toString() === req.userId);
            return postObj;
        });

        res.json({
            posts: postsWithLikeStatus,
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get user's posts
exports.getUserPosts = async (req, res, next) => {
    try {
        const { userId } = req.params;
        const { page = 1, limit = 20 } = req.query;

        const query = { userId, isDeleted: false };
        const posts = await Post.find(query)
            .populate('userId', 'username avatar level')
            .sort({ createdAt: -1 })
            .limit(parseInt(limit))
            .skip((parseInt(page) - 1) * parseInt(limit));

        const total = await Post.countDocuments(query);

        let postsWithLikeStatus = posts.map(post => {
            const postObj = post.toObject();
            if (req.userId) {
                postObj.isLikedByUser = post.likes.some(like => like.userId.toString() === req.userId);
            }
            return postObj;
        });

        res.json({
            posts: postsWithLikeStatus,
            pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get single post
exports.getPostById = async (req, res, next) => {
    try {
        const post = await Post.findById(req.params.id)
            .populate('userId', 'username avatar level')
            .populate('comments.userId', 'username avatar')
            .populate('mentions.userId', 'username avatar');

        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        const ownerId = post.userId?._id?.toString?.() || post.userId?.toString?.() || '';
        const viewerId = req.userId?.toString?.() || '';
        const shouldTrackView = req.query.trackView !== 'false';
        let didTrackView = false;

        if (shouldTrackView && viewerId && ownerId && viewerId !== ownerId) {
            const alreadyViewed = Array.isArray(post.viewers)
                ? post.viewers.some(
                    (viewer) => viewer?.userId?.toString?.() === viewerId
                )
                : false;

            if (!alreadyViewed) {
                post.viewers.push({
                    userId: req.userId,
                    viewedAt: new Date()
                });
                post.views += 1;
                await post.save();
                didTrackView = true;
            }
        }

        const postObj = post.toObject();
        if (req.userId) {
            postObj.isLikedByUser = post.likes.some(like => like.userId.toString() === req.userId);
        }

        if (didTrackView) {
            emitPostChanged(req, post, 'view');
        }

        res.json(postObj);
    } catch (error) {
        next(error);
    }
};

// @desc    Like/unlike
exports.toggleLike = async (req, res, next) => {
    try {
        const post = await Post.findById(req.params.id);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        const likeIndex = post.likes.findIndex(like => like.userId.toString() === req.userId);
        let liked;

        if (likeIndex === -1) {
            post.likes.push({ userId: req.userId });
            liked = true;

            if (post.userId.toString() !== req.userId) {
                const io = req.app.get('io');
                const user = await User.findById(req.userId).select('username');
                io.to(`user:${post.userId}`).emit('notification', {
                    type: 'like',
                    postId: post._id,
                    fromUser: req.userId,
                    username: user.username,
                    message: `${user.username} liked your post`
                });
            }
        } else {
            post.likes.splice(likeIndex, 1);
            liked = false;
        }

        await post.save();
        emitPostChanged(req, post, 'like');
        res.json({ liked, likeCount: post.likes.length });
    } catch (error) {
        next(error);
    }
};

// @desc    Add comment
exports.addComment = async (req, res, next) => {
    try {
        const { content } = req.body;
        const normalizedContent = typeof content === 'string' ? content.trim() : '';
        if (!normalizedContent) {
            const error = new Error('Comment cannot be empty');
            error.status = 400;
            throw error;
        }

        const post = await Post.findById(req.params.id);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        const comment = { userId: req.userId, content: normalizedContent, createdAt: new Date() };
        post.comments.push(comment);
        await post.save();
        await post.populate('comments.userId', 'username avatar');

        const newComment = post.comments[post.comments.length - 1];

        if (post.userId.toString() !== req.userId) {
            const io = req.app.get('io');
            const user = await User.findById(req.userId).select('username');
            io.to(`user:${post.userId}`).emit('notification', {
                type: 'comment',
                postId: post._id,
                commentId: newComment._id,
                fromUser: req.userId,
                username: user.username,
                content: normalizedContent.substring(0, 100),
                message: `${user.username} commented on your post`
            });
        }

        emitPostChanged(req, post, 'comment');
        res.status(201).json({ comment: newComment, commentCount: post.comments.length });
    } catch (error) {
        next(error);
    }
};

// @desc    Delete comment
exports.deleteComment = async (req, res, next) => {
    try {
        const { postId, commentId } = req.params;
        const post = await Post.findById(postId);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        const commentIndex = post.comments.findIndex(c => c._id.toString() === commentId);
        if (commentIndex === -1) {
            const error = new Error('Comment not found');
            error.status = 404;
            throw error;
        }

        const comment = post.comments[commentIndex];
        if (comment.userId.toString() !== req.userId && post.userId.toString() !== req.userId) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        post.comments.splice(commentIndex, 1);
        await post.save();
        emitPostChanged(req, post, 'comment_delete');
        res.json({ success: true, commentCount: post.comments.length });
    } catch (error) {
        next(error);
    }
};

// @desc    Update post
exports.updatePost = async (req, res, next) => {
    try {
        const post = await Post.findById(req.params.id);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        if (post.userId.toString() !== req.userId) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        if (req.body.content !== undefined) {
            post.content = typeof req.body.content === 'string'
                ? req.body.content.trim()
                : req.body.content;
        }
        if (req.body.images !== undefined) {
            post.images = normalizeImages(req.body.images);
        }
        post.isEdited = true;

        await post.save();
        await post.populate('userId', 'username avatar level');
        emitPostChanged(req, post, 'update');
        res.json(post);
    } catch (error) {
        next(error);
    }
};

// @desc    Delete post
exports.deletePost = async (req, res, next) => {
    try {
        const post = await Post.findById(req.params.id);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        if (post.userId.toString() !== req.userId) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        post.isDeleted = true;
        await post.save();
        emitPostChanged(req, post, 'delete');
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};


