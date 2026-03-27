const Group = require('../models/Group');
const User = require('../models/User');
const mongoose = require('mongoose');

// @desc    Create a new group
exports.createGroup = async (req, res, next) => {
    try {
        const { name, description, motto, isPublic } = req.body;

        const group = new Group({
            name,
            description: description || '',
            motto: motto || '',
            isPublic: isPublic !== undefined ? isPublic : true,
            leaderId: req.userId,
            members: [{
                userId: req.userId,
                role: 'leader',
                joinedAt: Date.now()
            }]
        });

        await group.save();
        await group.populate([
            { path: 'leaderId', select: 'username avatar' },
            { path: 'members.userId', select: 'username avatar' }
        ]);

        res.status(201).json(group);
    } catch (error) {
        next(error);
    }
};

// @desc    Get user's groups
exports.getMyGroups = async (req, res, next) => {
    try {
        const groups = await Group.find({ 'members.userId': req.userId })
            .populate('leaderId', 'username avatar')
            .populate('members.userId', 'username avatar')
            .sort({ updatedAt: -1 });

        res.json(groups);
    } catch (error) {
        next(error);
    }
};

// @desc    Get discoverable groups
exports.getDiscoverGroups = async (req, res, next) => {
    try {
        const groups = await Group.find({
            isPublic: true,
            'members.userId': { $ne: req.userId }
        })
            .populate('leaderId', 'username avatar')
            .limit(50)
            .sort({ memberCount: -1 });

        res.json(groups);
    } catch (error) {
        next(error);
    }
};

// @desc    Get group leaderboard
exports.getLeaderboard = async (req, res, next) => {
    try {
        const groups = await Group.find()
            .populate('leaderId', 'username avatar')
            .sort({ 'stats.totalXp': -1, memberCount: -1 })
            .limit(100);

        // Map rank on fly
        const rankedGroups = groups.map((g, i) => {
            const obj = g.toObject();
            obj.stats.rank = i + 1;
            return obj;
        });

        res.json(rankedGroups);
    } catch (error) {
        next(error);
    }
};

// @desc    Get single group
exports.getGroupById = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id)
            .populate('leaderId', 'username avatar level')
            .populate('admins', 'username avatar')
            .populate('members.userId', 'username avatar level');

        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        res.json(group);
    } catch (error) {
        next(error);
    }
};

// @desc    Join a group
exports.joinGroup = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const isMember = group.members.some(m => m.userId.toString() === req.userId);
        if (isMember) {
            const error = new Error('Already a member');
            error.status = 400;
            throw error;
        }

        if (group.members.length >= group.maxMembers) {
            const error = new Error('Group is full');
            error.status = 400;
            throw error;
        }

        group.members.push({ userId: req.userId, role: 'member', joinedAt: Date.now() });
        await group.save();

        res.json({ success: true, message: 'Joined group successfully' });
    } catch (error) {
        next(error);
    }
};

// @desc    Leave a group
exports.leaveGroup = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (group.leaderId.toString() === req.userId) {
            const error = new Error('Leader cannot leave. Transfer leadership first or delete the group.');
            error.status = 400;
            throw error;
        }

        group.members = group.members.filter(m => m.userId.toString() !== req.userId);
        await group.save();

        res.json({ success: true, message: 'Left group successfully' });
    } catch (error) {
        next(error);
    }
};

// @desc    Claim treasure chest
exports.claimTreasure = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const isMember = group.members.some(m => m.userId.toString() === req.userId);
        if (!isMember) {
            const error = new Error('Not a member of this group');
            error.status = 403;
            throw error;
        }

        const now = new Date();
        const lastClaimed = group.treasureChest.lastClaimed;
        const cooldownMs = 24 * 60 * 60 * 1000;
        const isAvailable = group.treasureChest.available || !lastClaimed || (now - lastClaimed) >= cooldownMs;
        if (!isAvailable) {
            const error = new Error('Treasure not available');
            error.status = 400;
            throw error;
        }

        const reward = 100 + (group.members.length * 10);
        const user = await User.findById(req.userId);
        user.coins = (user.coins || 0) + reward;
        await user.save();

        group.treasureChest.available = false;
        group.treasureChest.lastClaimed = now;
        await group.save();

        res.json({ success: true, coins: reward, message: 'Treasure claimed!', newBalance: user.coins });
    } catch (error) {
        next(error);
    }
};

// @desc    Update group
exports.updateGroup = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        const isLeader = group.leaderId.toString() === req.userId;
        const isAdmin = group.admins.some(a => a.toString() === req.userId);

        if (!isLeader && !isAdmin) {
            const error = new Error('Not authorized');
            error.status = 403;
            throw error;
        }

        const updatable = ['name', 'description', 'motto', 'avatar', 'coverImage', 'isPublic', 'approvalRequired', 'maxMembers'];
        updatable.forEach(field => {
            if (req.body[field] !== undefined) group[field] = req.body[field];
        });

        await group.save();
        res.json(group);
    } catch (error) {
        next(error);
    }
};

// @desc    Delete group
exports.deleteGroup = async (req, res, next) => {
    try {
        const group = await Group.findById(req.params.id);
        if (!group) {
            const error = new Error('Group not found');
            error.status = 404;
            throw error;
        }

        if (group.leaderId.toString() !== req.userId) {
            const error = new Error('Only leader can delete group');
            error.status = 403;
            throw error;
        }

        await group.deleteOne();
        res.json({ success: true, message: 'Group deleted' });
    } catch (error) {
        next(error);
    }
};






