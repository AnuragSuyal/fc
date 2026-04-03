const normalizeParticipantId = (value) => String(value || '').trim();

const sortDirectChatParticipants = (...values) => values
    .flat()
    .map(normalizeParticipantId)
    .filter(Boolean)
    .sort();

const buildDirectChatId = (...values) => {
    const participants = sortDirectChatParticipants(...values);
    if (participants.length !== 2) {
        return '';
    }
    return `dm:${participants[0]}:${participants[1]}`;
};

const matchesDirectChatId = (chatId, ...values) => {
    const expected = buildDirectChatId(...values);
    if (!expected) return false;
    return normalizeParticipantId(chatId) === expected;
};

module.exports = {
    buildDirectChatId,
    matchesDirectChatId,
    normalizeParticipantId,
    sortDirectChatParticipants
};
