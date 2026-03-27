const jwt  = require('jsonwebtoken');

const auth = async (req, res, next) => {
    try {
        const token = req.header('Authorization')?.replace('Bearer ', '');
        if (!token) return res.status(401).json({ error: 'No token provided' });

        let decoded;
        try {
            decoded = jwt.verify(token, process.env.JWT_SECRET);
        } catch (err) {
            return res.status(401).json({ error: 'Invalid token' });
        }

        // Redis session check – degrade gracefully if Redis is unavailable
        const redis = req.app.get('redis');
        if (redis && redis.isReady) {
            try {
                const sessionExists = await redis.exists(`session:${decoded.userId}`);
                if (!sessionExists) {
                    return res.status(401).json({ error: 'Session expired or revoked' });
                }
            } catch (redisErr) {
                // Redis down – fall back to JWT-only validation
                console.warn('Auth: Redis check failed, falling back to JWT-only:', redisErr.message);
            }
        }

        req.userId = decoded.userId;
        req.token  = token;
        next();
    } catch (error) {
        res.status(401).json({ error: 'Please authenticate' });
    }
};

module.exports = auth;




