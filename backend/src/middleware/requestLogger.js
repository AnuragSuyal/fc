const crypto = require('crypto');
const { logger } = require('./errorMiddleware');

const requestLogger = (req, res, next) => {
    const requestId = crypto.randomUUID ? crypto.randomUUID() : crypto.randomBytes(16).toString('hex');
    req.id = requestId;

    const start = process.hrtime.bigint();

    res.on('finish', () => {
        const durationMs = Number(process.hrtime.bigint() - start) / 1e6;
        if (logger?.info) {
            logger.info('request', {
                requestId,
                method: req.method,
                path: req.originalUrl,
                status: res.statusCode,
                durationMs: Number(durationMs.toFixed(2)),
                ip: req.ip
            });
        }
    });

    next();
};

module.exports = requestLogger;






