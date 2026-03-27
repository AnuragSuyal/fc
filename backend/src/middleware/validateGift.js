function validateGift(req, res, next) {
    if (!req.body.giftId) {
        return res.status(400).json({
            error: "Gift ID required"
        });
    }
    if (!req.body.toUserId) {
        return res.status(400).json({
            error: "Recipient ID required"
        });
    }
    next();
}

module.exports = validateGift;






