const validate = (schema) => (req, res, next) => {
    try {
        schema.parse(req.body);
        next();
    } catch (error) {
        const issues = Array.isArray(error?.issues)
            ? error.issues
            : Array.isArray(error?.errors)
                ? error.errors
                : null;
        const details = Array.isArray(issues)
            ? issues.map(e => ({ path: e.path?.[0], message: e.message }))
            : [{ path: 'body', message: error?.message || 'Validation failed' }];
        return res.status(400).json({
            error: 'Validation failed',
            details
        });
    }
};

module.exports = validate;





