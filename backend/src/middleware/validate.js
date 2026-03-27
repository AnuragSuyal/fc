const validate = (schema) => (req, res, next) => {
    try {
        schema.parse(req.body);
        next();
    } catch (error) {
        const details = Array.isArray(error?.errors)
            ? error.errors.map(e => ({ path: e.path?.[0], message: e.message }))
            : [{ path: 'body', message: error?.message || 'Validation failed' }];
        return res.status(400).json({
            error: 'Validation failed',
            details
        });
    }
};

module.exports = validate;






