const express  = require('express');
const router   = express.Router();
const ac       = require('../controllers/authController');
const auth     = require('../middleware/auth');
const passport = require('../config/passport');
const { authLimiter, otpLimiter } = require('../middleware/rateLimit');
const validate = require('../middleware/validate');
const { registerSchema, loginSchema, phoneSchema, verifyOtpSchema } = require('../utils/validation');

router.use(authLimiter);

// Public
router.post('/register', validate(registerSchema), ac.register);
router.post('/login',    validate(loginSchema),    ac.login);
router.post('/guest',    ac.guestLogin);
router.post('/refresh',  ac.refreshToken);

// OTP
router.post('/otp/send',   otpLimiter, validate(phoneSchema),    ac.sendOTP);
router.post('/otp/verify', otpLimiter, validate(verifyOtpSchema), ac.verifyOTP);

// Social OAuth
router.get('/google',            ac.googleAuth);
router.get('/google/callback',   ac.googleCallback);
router.get('/facebook',          ac.facebookAuth);
router.get('/facebook/callback', ac.facebookCallback);
router.post('/social/token',     ac.handleSocialToken);

// Protected
router.get('/me',       auth, ac.getMe);
router.post('/logout',  auth, ac.logout);

// 2FA
router.post('/2fa/enable',  auth, ac.enable2FA);
router.post('/2fa/verify',  auth, ac.verify2FA);
router.post('/2fa/disable', auth, ac.disable2FA);

module.exports = router;


