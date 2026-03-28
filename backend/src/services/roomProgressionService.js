const { calculateSpendXp } = require('./spendXpService');

const EXTRA_ADMIN_UNLOCK_LEVEL = 4;
const BASE_ADMIN_LIMIT = 4;
const MAX_ADMIN_LIMIT = 5;

const normalizeNumber = (value) => {
    const amount = Number(value);
    if (!Number.isFinite(amount) || amount <= 0) {
        return 0;
    }

    return Math.floor(amount);
};

const getRoomLevelFromExp = (exp = 0) => {
    const safeExp = normalizeNumber(exp);
    return Math.max(1, Math.floor(Math.sqrt(safeExp / 100)) + 1);
};

const getRoomAdminLimit = (level = 1) =>
    Number(level || 1) >= EXTRA_ADMIN_UNLOCK_LEVEL ? MAX_ADMIN_LIMIT : BASE_ADMIN_LIMIT;

const getNextAdminUnlockLevel = (level = 1) =>
    Number(level || 1) >= EXTRA_ADMIN_UNLOCK_LEVEL ? null : EXTRA_ADMIN_UNLOCK_LEVEL;

const awardRoomGiftXp = ({ room, coins = 0, gems = 0 } = {}) => {
    if (!room) {
        return null;
    }

    const xpGained = calculateSpendXp({ coins, gems });
    const previousLevel = Number(room.level || 1);

    room.exp = Number(room.exp || 0) + xpGained;
    room.expToday = Number(room.expToday || 0) + xpGained;

    const newLevel = getRoomLevelFromExp(room.exp);
    room.level = newLevel;

    return {
        room,
        xpGained,
        previousLevel,
        newLevel,
        leveledUp: newLevel > previousLevel,
        adminLimit: getRoomAdminLimit(newLevel),
        nextAdminUnlockLevel: getNextAdminUnlockLevel(newLevel)
    };
};

module.exports = {
    BASE_ADMIN_LIMIT,
    EXTRA_ADMIN_UNLOCK_LEVEL,
    MAX_ADMIN_LIMIT,
    awardRoomGiftXp,
    getNextAdminUnlockLevel,
    getRoomAdminLimit,
    getRoomLevelFromExp
};
