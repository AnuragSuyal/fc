const axios = require('axios');
const API_BASE = 'http://localhost:5000/api';

async function runAlphaPersonasTest() {
    console.log('--- STARTING ALPHA PERSONAS VERIFICATION ---');
    try {
        const ts = Date.now();

        // Persona 1: The "Newbie" (Free User, Level 1)
        const newbieRes = await axios.post(`${API_BASE}/auth/register`, {
            username: `n_${ts.toString().slice(-6)}`,
            email: `newbie_${ts}@test.com`,
            password: 'Password123!',
        });
        const newbieToken = newbieRes.data.token;
        const newbieId = newbieRes.data.user._id;
        console.log(`âœ… Persona 1 (Newbie) Registered with ID: ${newbieId}`);

        // Persona 2: The "VIP Whale" (Level 12 VIP)
        // Note: For testing, we might need to manually promote this user if no easy purchase route exists in test
        const whaleRes = await axios.post(`${API_BASE}/auth/register`, {
            username: `w_${ts.toString().slice(-6)}`,
            email: `whale_${ts}@test.com`,
            password: 'Password123!',
        });
        const whaleToken = whaleRes.data.token;
        const whaleId = whaleRes.data.user._id;

        // Upgrade Whale to VIP 12
        await axios.post(`${API_BASE}/vip/purchase`, { level: 12 }, {
            headers: { Authorization: `Bearer ${whaleToken}` }
        });
        console.log(`âœ… Persona 2 (Whale) Registered and Promoted to VIP 12`);

        // Persona 3: The "Creator" (Recipient)
        const creatorRes = await axios.post(`${API_BASE}/auth/register`, {
            username: `c_${ts.toString().slice(-6)}`,
            email: `creator_${ts}@test.com`,
            password: 'Password123!',
        });
        const creatorToken = creatorRes.data.token;
        const creatorId = creatorRes.data.user._id;
        console.log(`âœ… Persona 3 (Creator) Registered with ID: ${creatorId}`);

        // Seed gifts (bypass admin check since it's not implemented yet)
        console.log('\n--- Seeding Gift Catalog ---');
        await axios.post(`${API_BASE}/gifts/seed`, {}, {
            headers: { Authorization: `Bearer ${newbieToken}` }
        });

        // --- TEST 1: Economy Math (20% Platform Fee) ---
        console.log('\n--- Test 1: Economy Math (20% Platform Fee) ---');

        // Get a gift ID that newbie can afford (start balance 100 + daily 100 = 200)
        const giftCatalog = await axios.get(`${API_BASE}/gifts/catalog`);
        let gift = null;
        for (const cat in giftCatalog.data) {
            gift = giftCatalog.data[cat].find(g => g.price.coins <= 200 && g.price.coins > 0);
            if (gift) break;
        }

        if (!gift) throw new Error("No affordable gifts in catalog for testing");
        const giftId = gift._id || gift.id;
        const giftCost = gift.price.coins;
        console.log(`Found gift: ${gift.name} (${giftCost} coins) with ID: ${giftId}`);

        // --- TEST: Tiered Permissions (Daily Rewards) ---
        console.log('\n--- Test: Tiered Permissions (Daily Rewards) ---');

        const newbieDaily = await axios.post(`${API_BASE}/economy/daily-reward`, {}, {
            headers: { Authorization: `Bearer ${newbieToken}` }
        });
        console.log(`Newbie (VIP 0) Daily Reward: ${newbieDaily.data.coins} coins.`);

        // --- TEST 1: Economy Math (20% Platform Fee) ---
        console.log('\n--- Test 1: Economy Math (20% Platform Fee) ---');

        console.log(`Sending gift: ${gift.name} (${giftCost} coins) from Newbie to Creator`);

        // Ensure newbie has enough coins (default 100 + daily 100 = 200)
        if (giftCost > 200) {
            console.log("âš ï¸ Gift too expensive for newbie balance, skipping transfer test.");
        } else {
            const initialCreatorCoins = 100; // Default welcome bonus
            console.log(`DEBUG: toUserId=${creatorId}, giftId=${giftId}`);
            await axios.post(`${API_BASE}/gifts/send`, {
                toUserId: creatorId,
                giftId: giftId,
                message: "Test fee"
            }, { headers: { Authorization: `Bearer ${newbieToken}` } });

            // Verify Creator payout
            const updatedCreator = await axios.get(`${API_BASE}/auth/me`, {
                headers: { Authorization: `Bearer ${creatorToken}` }
            });

            const expectedPayout = Math.floor(giftCost * 0.8);
            const actualPayout = updatedCreator.data.coins - initialCreatorCoins;

            if (actualPayout === expectedPayout) {
                console.log(`âœ… Pixel-Perfect! Creator received ${actualPayout} coins (80% of ${giftCost}).`);
            } else {
                console.error(`âŒ Fee Math Incorrect. Expected ${expectedPayout}, got ${actualPayout}.`);
            }
        }

        // --- TEST 2: Tiered Permissions (Daily Rewards) ---
        console.log('\n--- Test 2: Tiered Permissions (Daily Rewards) ---');

        const whaleDaily = await axios.post(`${API_BASE}/economy/daily-reward`, {}, {
            headers: { Authorization: `Bearer ${whaleToken}` }
        });
        console.log(`Whale (VIP 12) Daily Reward: ${whaleDaily.data.coins} coins.`);

        if (whaleDaily.data.coins === 1500) {
            console.log('âœ… VIP Tiered Permission Verified: 1,500 coins awarded for VIP 12.');
        } else {
            console.error(`âŒ VIP Bonus Calculation Wrong. Expected 1500, got ${whaleDaily.data.coins}.`);
        }

        console.log('\n--- ALPHA PERSONAS VERIFICATION COMPLETED ---');
    } catch (err) {
        console.error('âŒ PERSONA TEST FAILED:', err.response?.data || err.message);
        process.exit(1);
    }
}

runAlphaPersonasTest();






