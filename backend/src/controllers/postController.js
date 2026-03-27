const Post = require('../models/Post');
const User = require('../models/User');
const economyController = require('./economyController');

// @desc    Create a new post
exports.createPost = async (req, res, next) => {
    try {
        const { content, images, type, metadata } = req.body;

        const post = new Post({
            userId: req.userId,
            content: content || '',
            images: images || [],
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

        post.views += 1;
        await post.save();

        const postObj = post.toObject();
        if (req.userId) {
            postObj.isLikedByUser = post.likes.some(like => like.userId.toString() === req.userId);
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
        res.json({ liked, likeCount: post.likes.length });
    } catch (error) {
        next(error);
    }
};

// @desc    Add comment
exports.addComment = async (req, res, next) => {
    try {
        const { content } = req.body;
        const post = await Post.findById(req.params.id);
        if (!post || post.isDeleted) {
            const error = new Error('Post not found');
            error.status = 404;
            throw error;
        }

        const comment = { userId: req.userId, content: content.trim(), createdAt: new Date() };
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
                content: content.substring(0, 100),
                message: `${user.username} commented on your post`
            });
        }

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

        if (req.body.content !== undefined) post.content = req.body.content;
        if (req.body.images !== undefined) post.images = req.body.images;
        post.isEdited = true;

        await post.save();
        await post.populate('userId', 'username avatar level');
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
        res.json({ success: true });
    } catch (error) {
        next(error);
    }
};





