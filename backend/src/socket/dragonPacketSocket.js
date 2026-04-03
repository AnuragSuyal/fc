const {
    DRAGON_SOCKET_EVENTS,
    handleDragonTapSocket
} = require('../services/dragonPacketService');

const registerDragonPacketSocket = ({
    io,
    socket,
    redis,
    isActiveRoomParticipant
}) => {
    socket.on('dragon:tap', async (payload = {}, ack) => {
        const roomId = payload?.roomId?.toString?.() || payload?.roomId || '';
        const eventId = payload?.eventId?.toString?.() || payload?.eventId || '';
        const seq = payload?.seq;

        if (!roomId || !eventId) {
            const response = {
                eventId,
                accepted: false,
                tapCounted: false,
                currentCountedTaps: 0,
                riskState: 'invalid'
            };
            if (typeof ack === 'function') {
                ack(response);
            } else {
                socket.emit(DRAGON_SOCKET_EVENTS.TAP_ACK, response);
            }
            return;
        }

        if (!isActiveRoomParticipant(roomId)) {
            const response = {
                eventId,
                accepted: false,
                tapCounted: false,
                currentCountedTaps: 0,
                riskState: 'not_in_room'
            };
            if (typeof ack === 'function') {
                ack(response);
            } else {
                socket.emit(DRAGON_SOCKET_EVENTS.TAP_ACK, response);
            }
            return;
        }

        try {
            const response = await handleDragonTapSocket({
                roomId,
                eventId,
                seq,
                socket,
                redis
            });

            if (typeof ack === 'function') {
                ack(response);
            } else {
                socket.emit(DRAGON_SOCKET_EVENTS.TAP_ACK, response);
            }
        } catch (error) {
            const response = {
                eventId,
                accepted: false,
                tapCounted: false,
                currentCountedTaps: 0,
                riskState: String(error?.code || 'error').toLowerCase()
            };
            if (typeof ack === 'function') {
                ack(response);
            } else {
                socket.emit(DRAGON_SOCKET_EVENTS.TAP_ACK, response);
            }
        }
    });
};

module.exports = registerDragonPacketSocket;
