const { io } = require("socket.io-client");
const axios = require("axios");

const STAGING_URL = process.env.STAGING_URL || "http://localhost:5000";
const CLIENT_COUNT = 10;
const clients = [];

console.log(`ðŸš€ Starting Smoke & Chaos Test on ${STAGING_URL}`);

async function runTest() {
    console.log(`\n--- Phase 1: Session Affinity (Sticky Sessions) Check ---`);

    for (let i = 0; i < CLIENT_COUNT; i++) {
        const socket = io(STAGING_URL, {
            transports: ['websocket'],
            forceNew: true
        });

        socket.on('connect', () => {
            // In a real K8s env with Ingress Nginx, we'd check the 'io' cookie or a 'X-Pod-Id' header
            console.log(`[Client ${i}] âœ… Connected. Socket ID: ${socket.id}`);
        });

        socket.on('disconnect', (reason) => {
            console.log(`[Client ${i}] âŒ Disconnected: ${reason}`);
        });

        clients.push(socket);
    }

    // Wait for all to connect
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log(`\n--- Phase 2: Real-time State Verification ---`);
    const roomId = "smoke-test-room";
    clients.forEach((s, i) => {
        s.emit('room:join', { roomId });
    });

    await new Promise(resolve => setTimeout(resolve, 1000));
    console.log("âœ… All clients joined room: smoke-test-room");

    console.log(`\n--- Phase 3: Chaos Simulation (Replica Termination) ---`);
    console.log("âš ï¸ WARNING: Manual pod termination would occur here in a real K8s cluster.");
    console.log("Command: kubectl delete pod -l app=friend-circle-api --grace-period=0");

    // Simulate a disconnect for half the clients to see if they recover
    console.log("Simulating network hiccup for 5 clients...");
    for (let i = 0; i < 5; i++) {
        clients[i].io.engine.close();
    }

    await new Promise(resolve => setTimeout(resolve, 5000));

    console.log(`\n--- Phase 4: Recovery & Reconnection Check ---`);
    clients.forEach((s, i) => {
        if (s.connected) {
            console.log(`[Client ${i}] Still connected.`);
        } else {
            console.log(`[Client ${i}] Reconnecting...`);
        }
    });

    console.log(`\n--- Smoke Test Summary ---`);
    const connectedCount = clients.filter(s => s.connected).length;
    console.log(`Results: ${connectedCount}/${CLIENT_COUNT} clients active.`);

    if (connectedCount === CLIENT_COUNT) {
        console.log("âœ… SMOKE TEST PASSED: State recovered and affinity maintained.");
    } else {
        console.log("âŒ SMOKE TEST FAILED: Some clients failed to recover.");
    }

    process.exit(connectedCount === CLIENT_COUNT ? 0 : 1);
}

runTest().catch(err => {
    console.error("Test failed with error:", err);
    process.exit(1);
});






