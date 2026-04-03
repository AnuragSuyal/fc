const rateLimit = require('express-rate-limit').default || require('express-rate-limit');

const isDev = process.env.NODE_ENV !== 'production';
const passthrough = (req, res, next) => next();

const generateKey = (req) => {
    if (!req) return '127.0.0.1';
    return req.ip || req.headers['x-forwarded-for'] || req.connection?.remoteAddress || '127.0.0.1';
};

const apiLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 15 * 60 * 1000,
        max: 100,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: generateKey,
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Too many requests'
        }
    });

const authLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 60 * 60 * 1000,
        max: 5,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: generateKey,
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Too many attempts'
        }
    });

const otpLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 60 * 1000,
        max: 3,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: generateKey,
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Too many OTP attempts'
        }
    });

const giftLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 60 * 1000,
        max: 20,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: generateKey,
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Slow down'
        }
    });

const coinTransferLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 60 * 1000,
        max: 12,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: (req) => req.userId || generateKey(req),
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Slow down'
        }
    });

const dragonPacketLimiter = isDev
    ? passthrough
    : rateLimit({
        windowMs: 60 * 1000,
        max: 15,
        standardHeaders: true,
        legacyHeaders: false,
        keyGenerator: (req) => req.userId || generateKey(req),
        message: {
            code: 429,
            status: 'Resource Exhausted',
            message: 'Slow down'
        }
    });

module.exports = {
    apiLimiter,
    authLimiter,
    otpLimiter,
    giftLimiter,
    coinTransferLimiter,
    dragonPacketLimiter
};




