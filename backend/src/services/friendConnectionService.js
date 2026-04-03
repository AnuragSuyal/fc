const FriendConnection = require('../models/FriendConnection');
const Message = require('../models/Message');

const normalizeId = (value) => String(value || '').trim();

const buildFriendPairKey = (leftUserId, rightUserId) => {
    const ids = [normalizeId(leftUserId), normalizeId(rightUserId)]
        .filter(Boolean)
        .sort();
    if (ids.length !== 2) {
        return '';
    }
    return ids.join(':');
};

const upsertFriendConnection = async ({
    leftUserId,
    rightUserId,
    connectedAt = new Date(),
    source = 'friend_request_accept',
    metadata = {},
    session = null
} = {}) => {
    const pairKey = buildFriendPairKey(leftUserId, rightUserId);
    if (!pairKey) {
        return null;
    }

    const [userAId, userBId] = pairKey.split(':');
    const update = {
        $set: {
            disconnectedAt: null,
            source,
            metadata,
            updatedAt: new Date()
        },
        $setOnInsert: {
            pairKey,
            userAId,
            userBId,
            connectedAt
        }
    };

    return FriendConnection.findOneAndUpdate(
        { pairKey },
        update,
        {
            returnDocument: 'after',
            upsert: true,
            session
        }
    );
};

const removeFriendConnection = async ({
    leftUserId,
    rightUserId,
    session = null
} = {}) => {
    const pairKey = buildFriendPairKey(leftUserId, rightUserId);
    if (!pairKey) {
        return null;
    }

    return FriendConnection.findOneAndUpdate(
        { pairKey },
        {
            $set: {
                disconnectedAt: new Date()
            }
        },
        {
            returnDocument: 'after',
            session
        }
    );
};

const getFriendConnection = async (leftUserId, rightUserId, { session = null } = {}) => {
    const pairKey = buildFriendPairKey(leftUserId, rightUserId);
    if (!pairKey) {
        return null;
    }
    const query = FriendConnection.findOne({ pairKey });
    return session ? query.session(session) : query;
};

const findEarliestMessageAt = async (leftUserId, rightUserId, { session = null } = {}) => {
    const query = Message.findOne({
        $or: [
            { senderId: leftUserId, recipientId: rightUserId },
            { senderId: rightUserId, recipientId: leftUserId }
        ]
    })
        .select('createdAt')
        .sort({ createdAt: 1 });

    const result = session ? await query.session(session) : await query;
    return result?.createdAt || null;
};

const ensureFriendConnection = async ({
    leftUser,
    rightUser,
    session = null
} = {}) => {
    if (!leftUser?._id || !rightUser?._id) {
        return null;
    }

    const existing = await getFriendConnection(leftUser._id, rightUser._id, { session });
    if (existing) {
        return existing;
    }

    const earliestMessageAt = await findEarliestMessageAt(leftUser._id, rightUser._id, { session });
    const fallbackConnectedAt = earliestMessageAt || new Date(
        Math.max(
            new Date(leftUser.createdAt || Date.now()).getTime(),
            new Date(rightUser.createdAt || Date.now()).getTime()
        )
    );

    return upsertFriendConnection({
        leftUserId: leftUser._id,
        rightUserId: rightUser._id,
        connectedAt: fallbackConnectedAt,
        source: 'backfill_existing_friendship',
        metadata: {
            backfilled: true
        },
        session
    });
};

module.exports = {
    buildFriendPairKey,
    ensureFriendConnection,
    getFriendConnection,
    removeFriendConnection,
    upsertFriendConnection
};
