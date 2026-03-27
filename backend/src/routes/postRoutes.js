const express = require('express');
const router = express.Router();
const postController = require('../controllers/postController');
const auth = require('../middleware/auth');

const validate = require('../middleware/validate');
const { createPostSchema } = require('../utils/validation');

// Protected routes
router.get('/feed', auth, postController.getFeed);

// Public routes
router.get('/user/:userId', postController.getUserPosts);
router.get('/:id', postController.getPostById);
router.post('/', auth, validate(createPostSchema), postController.createPost);
router.post('/:id/like', auth, postController.toggleLike);
router.post('/:id/comments', auth, postController.addComment);
router.delete('/:postId/comments/:commentId', auth, postController.deleteComment);
router.put('/:id', auth, postController.updatePost);
router.delete('/:id', auth, postController.deletePost);

module.exports = router;






