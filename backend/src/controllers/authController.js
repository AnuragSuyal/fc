const User = require('../models/User');
const jwt = require('jsonwebtoken');
const passport = require('passport');
const OTP = require('../services/otpService');

// Helpers to generate JWT tokens
const generateAccessToken = (userId) => {
    const expiresIn = process.env.JWT_EXPIRY || '7d';
    return jwt.sign({ userId }, process.env.JWT_SECRET, { expiresIn });
};

const generateRefreshToken = (userId) => {
    return jwt.sign({ userId }, process.env.REFRESH_SECRET || 'refresh-secret', { expiresIn: '7d' });
};

// Common token pair generator
const generateTokens = (userId) => ({
    token: generateAccessToken(userId),
    refreshToken: generateRefreshToken(userId)
});

// Helper to generate random username for guests
const generateGuestUsername = () => {
    const adjectives = ['Happy', 'Lucky', 'Clever', 'Swift', 'Brave', 'Smart', 'Cool', 'Wild'];
    const nouns = ['Tiger', 'Eagle', 'Dolphin', 'Wolf', 'Falcon', 'Lion', 'Panda', 'Fox'];
    const randomNum = Math.floor(Math.random() * 1000);

    const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
    const noun = nouns[Math.floor(Math.random() * nouns.length)];

    return `${adj}${noun}${randomNum}`;
};

// @desc    Register a new user
// @route   POST /api/auth/register
// @access  Public
exports.register = async (req, res, next) => {
    try {
        const { username, email, password, phone } = req.body;

        // Check if user exists
        const existingUser = await User.findOne({
            $or: [{ email }, { username }, ...(phone ? [{ phone }] : [])]
        });

        if (existingUser) {
            const error = new Error(existingUser.email === email ? 'Email already registered' : 'Username already taken');
            error.status = 400;
            error.code = 'USER_ALREADY_EXISTS';
            throw error;
        }

        // Create user
        const user = new User({
            username,
            email,
            password,
            ...(phone ? { phone } : {})
        });

        await user.save();

        const { token, refreshToken } = generateTokens(user._id);

        // Store refresh token in Redis for session validation
        const redis = req.app.get('redis');
        if (redis) {
            await redis.set(`session:${user._id}`, refreshToken, { EX: 604800 });
        }

        res.status(201).json({
            token,
            accessToken: token,
            refreshToken,
            user: user.toJSON()
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Login user
// @route   POST /api/auth/login
// @access  Public
exports.login = async (req, res, next) => {
    try {
        const { email, password } = req.body;

        const user = await User.findOne({ email }).select('+password');

        if (!user || !(await user.comparePassword(password))) {
            const error = new Error('Invalid email or password');
            error.status = 401;
            error.code = 'UNAUTHENTICATED';
            throw error;
        }

        // Update online status
        user.status.isOnline = true;
        user.status.lastActive = Date.now();
        user.lastLoginDate = new Date();
        await user.save();

        const { token, refreshToken } = generateTokens(user._id);

        // Store refresh token in Redis
        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.set(`session:${user._id}`, refreshToken, { EX: 604800 }); // 7 days
        }

        res.json({
            token,
            accessToken: token,
            refreshToken,
            user: user.toJSON()
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Guest login
// @route   POST /api/auth/guest
// @access  Public
exports.guestLogin = async (req, res, next) => {
    try {
        const username = `Guest_${generateGuestUsername()}`;

        const user = new User({
            username,
            password: Math.random().toString(36).substring(2, 12),
            coins: 50, // Less coins for guests
            isGuest: true
        });

        await user.save();

        const { token, refreshToken } = generateTokens(user._id);

        const redis = req.app.get('redis');
        if (redis) {
            await redis.set(`session:${user._id}`, refreshToken, { EX: 604800 });
        }

        res.json({
            token,
            accessToken: token,
            refreshToken,
            user: {
                ...user.toJSON(),
                isGuest: true
            }
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get current user
// @route   GET /api/auth/me
// @access  Private
exports.getMe = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            error.code = 'NOT_FOUND';
            throw error;
        }
        res.json(user);
    } catch (error) {
        next(error);
    }
};

// @desc    Refresh access token
// @route   POST /api/auth/refresh
// @access  Public
exports.refreshToken = async (req, res, next) => {
    try {
        const { refreshToken } = req.body;

        if (!refreshToken) {
            const error = new Error('Refresh token required');
            error.status = 401;
            error.code = 'UNAUTHENTICATED';
            throw error;
        }

        let decoded;
        try {
            decoded = jwt.verify(refreshToken, process.env.REFRESH_SECRET || 'refresh-secret');
        } catch (err) {
            const error = new Error('Invalid refresh token');
            error.status = 401;
            error.code = 'UNAUTHENTICATED';
            throw error;
        }

        const redis = req.app.get('redis');
        if (!redis || !redis.isReady) {
            const error = new Error('Session store unavailable');
            error.status = 503;
            error.code = 'UNAVAILABLE';
            throw error;
        }
        const storedToken = await redis.get(`session:${decoded.userId}`);

        if (!storedToken || storedToken !== refreshToken) {
            const error = new Error('Invalid or expired session');
            error.status = 401;
            error.code = 'UNAUTHENTICATED';
            throw error;
        }

        const accessToken = generateAccessToken(decoded.userId);
        const rotate = req.body?.rotate === true;
        let newRefreshToken = null;

        if (rotate) {
            newRefreshToken = generateRefreshToken(decoded.userId);
            await redis.set(`session:${decoded.userId}`, newRefreshToken, { EX: 604800 });
        }

        res.json({
            token: accessToken,
            accessToken,
            refreshToken: rotate ? newRefreshToken : undefined
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Logout user
// @route   POST /api/auth/logout
// @access  Private
exports.logout = async (req, res, next) => {
    try {
        await User.findByIdAndUpdate(req.userId, {
            'status.isOnline': false,
            'status.lastActive': Date.now()
        });

        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.del(`session:${req.userId}`);
        }

        res.json({ success: true, message: 'Logged out successfully' });
    } catch (error) {
        next(error);
    }
};

// OTP AUTHENTICATION
exports.sendOTP = async (req, res, next) => {
    try {
        const { phone } = req.body;
        const otp = OTP.generateOTP();
        await OTP.storeOTP(phone, otp);
        await OTP.sendSMS(phone, otp);

        res.json({
            success: true,
            message: 'OTP sent successfully',
            ...(process.env.NODE_ENV !== 'production' && { otp })
        });
    } catch (error) {
        next(error);
    }
};

exports.verifyOTP = async (req, res, next) => {
    try {
        const { phone, otp } = req.body;

        const isValid = await OTP.verifyOTP(phone, otp);
        if (!isValid) {
            const error = new Error('Invalid or expired OTP');
            error.status = 401;
            error.code = 'UNAUTHENTICATED';
            throw error;
        }

        let user = await User.findOne({ phone });

        if (!user) {
            const username = `Member_${Math.floor(100000 + Math.random() * 900000)}`;
            user = new User({
                username,
                phone,
                password: Math.random().toString(36).substring(2, 12),
                isVerified: true
            });
            await user.save();
        }

        user.status.isOnline = true;
        user.status.lastActive = Date.now();
        await user.save();

        const { token, refreshToken } = generateTokens(user._id);

        const redis = req.app.get('redis');
        await redis.set(`session:${user._id}`, refreshToken, { EX: 604800 });

        res.json({
            token,
            accessToken: token,
            refreshToken,
            user: user.toJSON()
        });
    } catch (error) {
        next(error);
    }
};

// GOOGLE AUTH CALLBACK
exports.googleCallback = (req, res, next) => {
    passport.authenticate('google', { session: false }, async (err, profile, info) => {
        try {
            if (err || !profile) {
                return res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?error=google_auth_failed`);
            }

            const email = profile.emails[0].value;
            let user = await User.findOne({ email });

            if (!user) {
                user = new User({
                    username: profile.displayName.replace(/\s+/g, '').substring(0, 15) + Math.floor(Math.random() * 1000),
                    email,
                    avatar: profile.photos?.[0]?.value,
                    password: Math.random().toString(36).substring(2, 12),
                    isVerified: true
                });
                await user.save();
            }

            const { token, refreshToken } = generateTokens(user._id);
            // We can't easily return two tokens in a redirect without making it messy
            // Usually we'd return just the access token or a code to exchange
            // For now, let's just pass the access token in the redirect as it was doing
            res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?token=${token}`);
        } catch (error) {
            res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?error=server_error`);
        }
    })(req, res, next);
};

// FACEBOOK AUTH CALLBACK
exports.facebookCallback = (req, res, next) => {
    passport.authenticate('facebook', { session: false }, async (err, profile, info) => {
        try {
            if (err || !profile) {
                return res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?error=facebook_auth_failed`);
            }

            const email = profile.emails?.[0]?.value || `${profile.id}@facebook.com`;
            let user = await User.findOne({ email });

            if (!user) {
                user = new User({
                    username: profile.displayName.replace(/\s+/g, '').substring(0, 15) + Math.floor(Math.random() * 1000),
                    email,
                    avatar: profile.photos?.[0]?.value,
                    password: Math.random().toString(36).substring(2, 12),
                    isVerified: true
                });
                await user.save();
            }

            const { token } = generateTokens(user._id);
            res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?token=${token}`);
        } catch (error) {
            res.redirect(`${process.env.FRONTEND_URL || 'friendcircle://auth'}?error=server_error`);
        }
    })(req, res, next);
};

exports.googleAuth = passport.authenticate('google', { scope: ['profile', 'email'] });
exports.facebookAuth = passport.authenticate('facebook', { scope: ['email'] });

exports.handleSocialToken = async (req, res, next) => {
    try {
        const { token } = req.body;
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        const user = await User.findById(decoded.userId);

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            error.code = 'NOT_FOUND';
            throw error;
        }

        user.status.isOnline = true;
        user.status.lastActive = Date.now();
        user.lastLoginDate = new Date();
        await user.save();

        const { token: accessToken, refreshToken } = generateTokens(user._id);

        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            await redis.set(`session:${user._id}`, refreshToken, { EX: 604800 });
        }

        res.json({
            token: accessToken,
            accessToken,
            refreshToken,
            user: user.toJSON()
        });
    } catch (error) {
        next(error);
    }
};






// @desc    Refresh access token (with rotation)
// Already defined above – this adds the missing 2FA verify stub

// @desc    Enable 2FA (returns TOTP secret)
exports.enable2FA = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        // In production: use 'speakeasy' npm package to generate a TOTP secret
        const secret = `FRIEND_CIRCLE_2FA_${req.userId}_${Date.now()}`;
        user.twoFactorSecret  = secret;
        user.twoFactorEnabled = false; // not enabled until verified
        await user.save();

        res.json({
            success: true,
            secret,
            qrCode: `otpauth://totp/FriendCircle:${user.username}?secret=${secret}&issuer=FriendCircle`,
            message: 'Scan QR code then verify with a 6-digit code to activate 2FA'
        });
    } catch (error) { next(error); }
};

// @desc    Verify & enable 2FA
exports.verify2FA = async (req, res, next) => {
    try {
        const { code } = req.body;
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }

        // In production: verify TOTP code via speakeasy
        // const verified = speakeasy.totp.verify({ secret: user.twoFactorSecret, encoding: 'base32', token: code });
        const verified = code && code.length === 6; // stub – replace with real TOTP

        if (!verified) { const e = new Error('Invalid 2FA code'); e.status = 401; throw e; }

        user.twoFactorEnabled = true;
        await user.save();

        res.json({ success: true, message: '2FA enabled successfully' });
    } catch (error) { next(error); }
};

// @desc    Disable 2FA
exports.disable2FA = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId);
        if (!user) { const e = new Error('User not found'); e.status = 404; throw e; }
        user.twoFactorEnabled = false;
        user.twoFactorSecret  = undefined;
        await user.save();
        res.json({ success: true, message: '2FA disabled' });
    } catch (error) { next(error); }
};
