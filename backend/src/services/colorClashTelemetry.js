const { logger } = require('../middleware/errorMiddleware');

const sanitizeValue = (value) => {
    if (value === undefined) return undefined;
    if (value === null) return null;
    if (value instanceof Date) return value.toISOString();
    if (Array.isArray(value)) return value.map(sanitizeValue);
    if (
        value &&
        typeof value === 'object' &&
        (value._bsontype === 'ObjectId' || value.constructor?.name === 'ObjectId')
    ) {
        return value.toString();
    }
    if (Buffer.isBuffer(value)) {
        return value.toString('hex');
    }
    if (typeof value === 'object') {
        return Object.fromEntries(
            Object.entries(value)
                .map(([key, entry]) => [key, sanitizeValue(entry)])
                .filter(([, entry]) => entry !== undefined)
        );
    }
    if (typeof value === 'bigint') return value.toString();
    return value;
};

const emit = (level, event, payload = {}) => {
    const safePayload = sanitizeValue(payload);
    if (!logger || typeof logger[level] !== 'function') {
        return;
    }
    logger[level]('color_clash', {
        event,
        ...safePayload
    });
};

module.exports = {
    info(event, payload = {}) {
        emit('info', event, payload);
    },
    warn(event, payload = {}) {
        emit('warn', event, payload);
    },
    error(event, payload = {}) {
        emit('error', event, payload);
    }
};
