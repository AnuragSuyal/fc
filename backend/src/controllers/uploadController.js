const multer = require('multer');
const path = require('path');
const fs = require('fs');
const User = require('../models/User');
const { applyAvatarUpdate } = require('../utils/avatarUploadLimit');

const uploadDir = path.join(__dirname, '../../uploads');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        const ext = path.extname(file.originalname);
        cb(null, 'file-' + uniqueSuffix + ext);
    }
});

const imageFilter = (req, file, cb) => {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error('Invalid file type. Only JPEG, PNG, GIF and WEBP are allowed.'));
    }
};

const upload = multer({
    storage,
    fileFilter: imageFilter,
    limits: { fileSize: 5 * 1024 * 1024 }
});

const audioFilter = (req, file, cb) => {
    const allowedTypes = [
        'audio/mpeg',
        'audio/mp3',
        'audio/x-m4a',
        'audio/mp4',
        'audio/aac',
        'audio/wav',
        'audio/x-wav',
        'audio/ogg',
        'audio/webm'
    ];
    if (allowedTypes.includes(file.mimetype)) {
        cb(null, true);
    } else {
        cb(new Error('Invalid file type. Only MP3, M4A, AAC, WAV and OGG audio files are allowed.'));
    }
};

const uploadAudio = multer({
    storage,
    fileFilter: audioFilter,
    limits: { fileSize: 20 * 1024 * 1024 }
});

const cleanupUploadedFile = async (file) => {
    const filePath = file?.path;
    if (!filePath) return;

    try {
        await fs.promises.unlink(filePath);
    } catch (_) {
        // Ignore cleanup failures for already-removed temp uploads.
    }
};

// @desc    Upload avatar
exports.uploadAvatar = (req, res, next) => {
    upload.single('avatar')(req, res, async (err) => {
        let avatarSaved = false;
        try {
            if (err) {
                const error = new Error(err.message);
                error.status = 400;
                throw error;
            }

            if (!req.file) {
                const error = new Error('No file uploaded');
                error.status = 400;
                throw error;
            }

            const baseUrl = `${req.protocol}://${req.get('host')}`;
            const avatarUrl = `${baseUrl}/api/uploads/${req.file.filename}`;
            const user = await User.findById(req.userId);
            if (!user) {
                const error = new Error('User not found');
                error.status = 404;
                throw error;
            }

            const uploadStats = applyAvatarUpdate(user, avatarUrl);
            await user.save();
            avatarSaved = true;

            const redis = req.app.get('redis');
            if (redis && redis.isReady) {
                try {
                    await redis.del(`cache:user:${req.userId}`);
                } catch (_) {
                    // Avoid failing the upload after the avatar has already been saved.
                }
            }

            res.json({
                success: true,
                url: avatarUrl,
                filename: req.file.filename,
                message: 'Avatar updated successfully',
                uploadsRemainingToday: uploadStats.uploadsRemainingToday,
            });
        } catch (error) {
            if (!avatarSaved) {
                await cleanupUploadedFile(req.file);
            }
            next(error);
        }
    });
};

// @desc    Upload image
exports.uploadImage = (req, res, next) => {
    upload.single('image')(req, res, async (err) => {
        try {
            if (err) {
                const error = new Error(err.message);
                error.status = 400;
                throw error;
            }

            if (!req.file) {
                const error = new Error('No file uploaded');
                error.status = 400;
                throw error;
            }

            const baseUrl = `${req.protocol}://${req.get('host')}`;
            const fileUrl = `${baseUrl}/api/uploads/${req.file.filename}`;

            res.json({ success: true, url: fileUrl, filename: req.file.filename });
        } catch (error) {
            next(error);
        }
    });
};

// @desc    Upload audio
exports.uploadAudio = (req, res, next) => {
    uploadAudio.single('audio')(req, res, async (err) => {
        try {
            if (err) {
                const error = new Error(err.message);
                error.status = 400;
                throw error;
            }

            if (!req.file) {
                const error = new Error('No audio file uploaded');
                error.status = 400;
                throw error;
            }

            const baseUrl = `${req.protocol}://${req.get('host')}`;
            const fileUrl = `${baseUrl}/api/uploads/${req.file.filename}`;

            res.json({
                success: true,
                url: fileUrl,
                filename: req.file.filename,
                originalName: req.file.originalname,
                mimetype: req.file.mimetype
            });
        } catch (error) {
            next(error);
        }
    });
};

// @desc    Serve file
exports.serveFile = (req, res, next) => {
    const filepath = path.join(uploadDir, req.params.filename);

    fs.access(filepath, fs.constants.F_OK, (err) => {
        if (err) {
            const error = new Error('File not found');
            error.status = 404;
            return next(error);
        }
        res.sendFile(filepath);
    });
};



