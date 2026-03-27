const { io } = require('socket.io-client');
const axios = require('axios');
const fs = require('fs');

const API_BASE = 'http://localhost:5000/api';
const SOCKET_URL = 'http://localhost:5000';
const CONCURRENT_CLIENTS = 10;
const EVENTS_PER_CLIENT = 100;
const TOTAL_EVENTS = CONCURRENT_CLIENTS * EVENTS_PER_CLIENT;

async function runLoadTest() {
    console.log(`--- STARTING LOAD TEST: ${TOTAL_EVENTS} GIFT EVENTS ---`);
    console.log(`Clients: ${CONCURRENT_CLIENTS}, Events/Client: ${EVENTS_PER_CLIENT}`);

    const ts = Date.now();
    const clients = [];
    const tokens = [];
    const userIds = [];

    try {
        // 1. Setup Clients (Register and Connect)
        for (let i = 0; i < CONCURRENT_CLIENTS; i++) {
            const res = await axios.post(`${API_BASE}/auth/register`, {
                username: `lt_${ts}_${i}`,
                email: `lt_${ts}_${i}@test.com`,
                password: 'Password123!',
            });
            const token = res.data.token;
            tokens.push(token);
            userIds.push(res.data.user._id);

            const socket = io(SOCKET_URL, {
                auth: { token },
                transports: ['websocket']
            });

            const client = {
                socket,
                receivedCount: 0,
                id: i
            };

            socket.on('receive_gift', () => {
                client.receivedCount++;
            });

            // Recharge user to handle 100 gifts
            await axios.post(`${API_BASE}/wallet/purchase/coins`, {
                packId: 'coins_legendary'
            }, { headers: { Authorization: `Bearer ${token}` } });

            // CRITICAL: Verification loop
            let verified = false;
            for (let attempt = 0; attempt < 3; attempt++) {
                const check = await axios.get(`${API_BASE}/wallet/balance`, {
                    headers: { Authorization: `Bearer ${token}` }
                });
                if (check.data.coins >= 150000) {
                    verified = true;
                    break;
                }
                await new Promise(r => setTimeout(r, 500));
            }
            if (!verified) console.warn(`âš ï¸ User ${i} recharge verification failed!`);

            clients.push(client);
        }

        const balRes = await axios.get(`${API_BASE}/wallet/balance`, {
            headers: { Authorization: `Bearer ${tokens[0]}` }
        });
        console.log(`âœ… ${CONCURRENT_CLIENTS} clients connected and recharged. User 0 balance: ${balRes.data.coins} coins.`);

        // 2. Create a Room
        const roomRes = await axios.post(`${API_BASE}/rooms`, {
            name: 'Load Test Arena',
            type: 'voice',
            category: 'voice'
        }, { headers: { Authorization: `Bearer ${tokens[0]}` } });
        const roomId = roomRes.data._id || roomRes.data.id;
        console.log(`âœ… Room created: ${roomId}`);

        // Join room (Socket Level)
        for (const c of clients) {
            c.socket.emit('join_room', roomId);
        }

        // Join room (API Level) to satisfy participants check if needed
        for (let i = 1; i < CONCURRENT_CLIENTS; i++) {
            await axios.post(`${API_BASE}/rooms/${roomId}/join`, {}, {
                headers: { Authorization: `Bearer ${tokens[i]}` }
            });
        }

        await new Promise(resolve => setTimeout(resolve, 1000)); // wait for join

        // 3. Seed a gift
        await axios.post(`${API_BASE}/gifts/seed`, {}, {
            headers: { Authorization: `Bearer ${tokens[0]}` }
        });
        const giftCatalog = await axios.get(`${API_BASE}/gifts/catalog`);
        const giftId = giftCatalog.data.simple[1]._id; // Use Rose (100 coins)

        // 4. Execution Phase
        console.log(`ðŸš€ Bursting ${TOTAL_EVENTS} gifts in room ${roomId}...`);
        const start = Date.now();

        const sendPromises = [];
        for (let i = 0; i < CONCURRENT_CLIENTS; i++) {
            for (let j = 0; j < EVENTS_PER_CLIENT; j++) {
                sendPromises.push(
                    axios.post(`${API_BASE}/gifts/send`, {
                        toUserId: userIds[(i + 1) % CONCURRENT_CLIENTS],
                        giftId: giftId,
                        roomId: roomId,
                        message: "Shower!"
                    }, { headers: { Authorization: `Bearer ${tokens[i]}` } })
                );
            }
        }

        const results = await Promise.allSettled(sendPromises);
        const successCount = results.filter(r => r.status === 'fulfilled').length;
        const failCount = results.filter(r => r.status === 'rejected').length;

        if (failCount > 0) {
            const firstFail = results.find(r => r.status === 'rejected');
            console.error('Sample Error:', firstFail.reason.response?.data || firstFail.reason.message);
        }

        const duration = (Date.now() - start) / 1000;
        console.log(`\n--- Execution Results ---`);
        console.log(`Time taken: ${duration.toFixed(2)}s`);
        console.log(`Successful Requests: ${successCount}`);
        console.log(`Failed Requests: ${failCount}`);
        console.log(`Throughput: ${(successCount / duration).toFixed(2)} req/s`);

        // 5. Verification Phase
        console.log(`\n--- Socket Verification ---`);
        await new Promise(resolve => setTimeout(resolve, 3000)); // Wait for broadcasts

        clients.forEach((c, idx) => {
            console.log(`Client ${idx} received ${c.receivedCount} broadcasts.`);
        });

        const totalReceived = clients.reduce((sum, c) => sum + c.receivedCount, 0);
        console.log(`Total Broadcasts Received: ${totalReceived}`);

        // Broadly: total broadcasts = successCount * (approx participants)
        // Since all 10 are in the room, each gift should be received by 10 clients.
        const expectedTotal = successCount * CONCURRENT_CLIENTS;
        console.log(`Expected Total Broadcasts: ${expectedTotal}`);

        if (totalReceived >= expectedTotal * 0.9 && totalReceived > 0) {
            console.log(`âœ… Socket Cluster Stability Verified! (Reliability: ${((totalReceived / expectedTotal) * 100).toFixed(1)}%)`);
        } else if (totalReceived > 0) {
            console.log(`âš ï¸ Partial data received. Consistency: ${((totalReceived / expectedTotal) * 100).toFixed(1)}%`);
        } else {
            console.log(`âŒ No broadcasts received. Check socket event names and room joining logic.`);
        }

        const summary = {
            duration,
            successCount,
            failCount,
            throughput: successCount / duration,
            totalReceived,
            expectedTotal,
            reliability: (totalReceived / expectedTotal) * 100
        };
        fs.writeFileSync('load_test_summary.json', JSON.stringify(summary, null, 2));

        // Cleanup
        clients.forEach(c => c.socket.disconnect());
        process.exit(0);

    } catch (err) {
        console.error('âŒ LOAD TEST ERR:', err.response?.data || err.message);
        if (err.stack) console.error(err.stack);
        process.exit(1);
    }
}

runLoadTest();






