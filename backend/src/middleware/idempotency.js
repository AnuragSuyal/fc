const { logger } = require('./errorMiddleware');

const DEFAULT_TTL_SECONDS = 60 * 60 * 24; // 24 hours

const normalizeHeader = (req) => {
    return req.get('Idempotency-Key')
        || req.get('X-Idempotency-Key')
        || req.get('idempotency-key')
        || req.get('x-idempotency-key')
        || req.headers['idempotency-key']
        || req.headers['x-idempotency-key'];
};

const idempotency = (options = {}) => {
    const {
        keyPrefix = 'idempotent',
        ttlSeconds = DEFAULT_TTL_SECONDS,
        scope = 'user'
    } = options;

    return async (req, res, next) => {
        const redis = req.app.get('redis');
        const rawKey = normalizeHeader(req);
        if (rawKey) {
            req.idempotencyKey = rawKey;
        }

        const redisReady = !!redis && (redis.isReady ?? redis.isOpen);
        if (!rawKey || !redisReady) {
            return next();
        }

        const scopeId = scope === 'ip'
            ? (req.ip || 'unknown')
            : (req.userId || req.ip || 'unknown');

        const storageKey = `${keyPrefix}:${scopeId}:${rawKey}`;

        try {
            const cached = await redis.get(storageKey);
            if (cached) {
                const parsed = JSON.parse(cached);
                return res.status(parsed.status || 200).json(parsed.body);
            }

            const lockSet = await redis.set(storageKey, '__LOCK__', { NX: true, EX: 30 });
            if (!lockSet) {
                return res.status(409).json({ error: 'Request in progress. Please retry.' });
            }

            req.idempotencyKey = rawKey;
            req.idempotencyStorageKey = storageKey;
            req.idempotencyStored = false;

            const originalJson = res.json.bind(res);
            res.json = (body) => {
                const status = res.statusCode || 200;
                if (status < 400) {
                    redis.set(storageKey, JSON.stringify({ status, body }), { EX: ttlSeconds })
                        .then(() => { req.idempotencyStored = true; })
                        .catch((err) => {
                            if (logger?.warn) {
                                logger.warn(`Idempotency store failed: ${err.message}`);
                            }
                        });
                }
                return originalJson(body);
            };

            res.on('finish', () => {
                if (!req.idempotencyStored && res.statusCode >= 400) {
                    redis.del(storageKey).catch(() => { });
                }
            });

            return next();
        } catch (error) {
            return next();
        }
    };
};

module.exports = idempotency;






