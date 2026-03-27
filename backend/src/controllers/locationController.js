const User = require('../models/User');

// @desc    Update user location
exports.updateLocation = async (req, res, next) => {
    try {
        const { latitude, longitude, sharing, radius } = req.body;

        const updateData = {
            location: {
                type: 'Point',
                coordinates: [longitude, latitude]
            },
            lastLocationUpdate: Date.now()
        };

        if (sharing !== undefined) updateData.locationSharing = sharing;
        if (radius !== undefined) updateData.visibilityRadius = radius;

        const user = await User.findByIdAndUpdate(
            req.userId,
            updateData,
            { new: true }
        ).select('username location locationSharing visibilityRadius');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json({
            success: true,
            location: user.location,
            sharing: user.locationSharing,
            radius: user.visibilityRadius
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Get nearby users
exports.getNearbyUsers = async (req, res, next) => {
    try {
        const { maxDistance = 10, limit = 50 } = req.query;

        const currentUser = await User.findById(req.userId);
        if (!currentUser) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        if (!currentUser.location || !currentUser.locationSharing) {
            const error = new Error('Location not shared. Please enable location sharing first.');
            error.status = 400;
            throw error;
        }

        const nearbyUsers = await User.aggregate([
            {
                $geoNear: {
                    near: {
                        type: 'Point',
                        coordinates: currentUser.location.coordinates
                    },
                    distanceField: 'distance',
                    maxDistance: parseInt(maxDistance) * 1000,
                    spherical: true,
                    query: {
                        _id: { $ne: currentUser._id },
                        locationSharing: true,
                        location: { $exists: true }
                    }
                }
            },
            { $limit: parseInt(limit) },
            {
                $project: {
                    username: 1,
                    avatar: 1,
                    level: 1,
                    vipLevel: 1,
                    distance: 1,
                    'status.isOnline': 1,
                    'status.currentRoom': 1
                }
            }
        ]);

        res.json({
            count: nearbyUsers.length,
            users: nearbyUsers.map(user => ({
                ...user,
                distance: (user.distance / 1000).toFixed(1)
            }))
        });
    } catch (error) {
        next(error);
    }
};

// @desc    Disable location sharing
exports.disableLocationSharing = async (req, res, next) => {
    try {
        await User.findByIdAndUpdate(req.userId, { locationSharing: false });
        res.json({ success: true, message: 'Location sharing disabled' });
    } catch (error) {
        next(error);
    }
};

// @desc    Get location status
exports.getLocationStatus = async (req, res, next) => {
    try {
        const user = await User.findById(req.userId)
            .select('location locationSharing visibilityRadius lastLocationUpdate');

        if (!user) {
            const error = new Error('User not found');
            error.status = 404;
            throw error;
        }

        res.json({
            sharing: user.locationSharing,
            radius: user.visibilityRadius,
            lastUpdate: user.lastLocationUpdate,
            location: user.locationSharing ? user.location : null
        });
    } catch (error) {
        next(error);
    }
};






