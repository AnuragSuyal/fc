const winston = require('winston');

// Configure Winston logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
        new winston.transports.File({ filename: 'logs/combined.log' }),
    ],
});

if (process.env.NODE_ENV !== 'production') {
    logger.add(new winston.transports.Console({
        format: winston.format.simple(),
    }));
}

const errorMiddleware = (err, req, res, next) => {
    const requestId = req.id || 'N/A';
    logger.error(`${err.message} - ${req.method} ${req.url} - RID: ${requestId} - IP: ${req.ip}`);

    const statusCode = err.status || (res.statusCode === 200 ? 500 : res.statusCode);

    // Google Cloud API Error Model
    const errorResponse = {
        error: {
            code: err.code || 'INTERNAL_ERROR',
            message: err.message || 'An unexpected error occurred.',
            status: getHttpStatusText(statusCode),
            requestId: requestId,
            timestamp: new Date().toISOString()
        }
    };

    if (process.env.NODE_ENV !== 'production' && err.stack) {
        errorResponse.error.stack = err.stack;
    }

    res.status(statusCode).json(errorResponse);
};

// Map status codes to Google API Status strings
function getHttpStatusText(code) {
    const map = {
        400: 'INVALID_ARGUMENT',
        401: 'UNAUTHENTICATED',
        403: 'PERMISSION_DENIED',
        404: 'NOT_FOUND',
        409: 'ABORTED',
        429: 'RESOURCE_EXHAUSTED',
        500: 'INTERNAL',
        501: 'UNIMPLEMENTED',
        503: 'UNAVAILABLE'
    };
    return map[code] || 'UNKNOWN';
}

module.exports = { errorMiddleware, logger };






