const jwt = require('jsonwebtoken');

const optionalAuth = async (req, res, next) => {
    const token = req.header('Authorization')?.replace('Bearer ', '');
    if (!token) return next();

    try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        req.userId = decoded.userId;
        req.token = token;
    } catch (error) {
        // Ignore invalid token for optional auth
    }

    return next();
};

module.exports = optionalAuth;






