function validateGift(req, res, next) {
    const rawGiftId = typeof req.body.giftId === 'string'
        ? req.body.giftId.trim()
        : '';
    if (!rawGiftId) {
        return res.status(400).json({
            error: "Gift ID required"
        });
    }
    if (!/^[A-Za-z0-9_-]{1,80}$/.test(rawGiftId)) {
        return res.status(400).json({
            error: "Invalid gift ID"
        });
    }
    req.body.giftId = rawGiftId;
    if (!req.body.toUserId) {
        return res.status(400).json({
            error: "Recipient ID required"
        });
    }
    next();
}

module.exports = validateGift;





