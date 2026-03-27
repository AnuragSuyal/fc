// Generic webhook handlers

exports.cloudinaryWebhook = async (req, res, next) => {
    try {
        res.json({ received: true });
    } catch (error) {
        next(error);
    }
};






