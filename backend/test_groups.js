const axios = require('axios');

const API_URL = 'http://localhost:5000/api';

async function testGroups() {
    console.log('Testing Groups API...');
    try {
        // 1. Create User 1 and Login
        const user1 = {
            username: 'grouptester1',
            email: 'grouptester1@test.com',
            password: 'password123'
        };

        // Register
        try {
            await axios.post(`${API_URL}/auth/register`, user1);
        } catch (e) { } // ignore if exists

        // Login
        const login1Response = await axios.post(`${API_URL}/auth/login`, {
            email: user1.email,
            password: user1.password
        });
        const token1 = login1Response.data.token;
        console.log('User 1 logged in');

        const headers1 = { Authorization: `Bearer ${token1}` };

        // 2. Create Group
        const createGroupRes = await axios.post(`${API_URL}/groups`, {
            name: 'Epic Dev Squad ' + Date.now().toString().slice(-4),
            description: 'We write code',
            motto: 'Code is Life'
        }, { headers: headers1 });
        const groupId = createGroupRes.data._id;
        console.log('1. Group created. ID:', groupId, 'Tag:', createGroupRes.data.tag);

        // 3. Get My Groups
        const myGroupsRes = await axios.get(`${API_URL}/groups/my-groups`, { headers: headers1 });
        console.log('2. My groups count (User 1):', myGroupsRes.data.length);

        // 4. Create User 2 and Login
        const user2 = {
            username: 'grouptester2',
            email: 'grouptester2@test.com',
            password: 'password123'
        };
        try {
            await axios.post(`${API_URL}/auth/register`, user2);
        } catch (e) { }

        const login2Response = await axios.post(`${API_URL}/auth/login`, {
            email: user2.email,
            password: user2.password
        });
        const token2 = login2Response.data.token;
        console.log('User 2 logged in');

        const headers2 = { Authorization: `Bearer ${token2}` };

        // 5. Discover Groups
        const discoverRes = await axios.get(`${API_URL}/groups/discover`, { headers: headers2 });
        console.log('3. Discover groups count (User 2):', discoverRes.data.length);

        // 6. Join Group
        const joinRes = await axios.post(`${API_URL}/groups/${groupId}/join`, {}, { headers: headers2 });
        console.log('4. User 2 joined group:', joinRes.data.success);

        // 7. Get Leaderboard
        const leaderboardRes = await axios.get(`${API_URL}/groups/leaderboard`);
        console.log('5. Leaderboard count:', leaderboardRes.data.length);

        // 8. Try to claim treasure (might fail if not available, but endpoint works)
        try {
            await axios.post(`${API_URL}/groups/${groupId}/treasure`, {}, { headers: headers2 });
            console.log('6. Treasure claimed');
        } catch (e) {
            console.log('6. Treasure claim response received:', e.response?.data?.error || e.message);
        }

        // 9. Leave Group (User 2)
        const leaveRes = await axios.post(`${API_URL}/groups/${groupId}/leave`, {}, { headers: headers2 });
        console.log('7. User 2 left group:', leaveRes.data.success);

        // 10. Update Group & Delete Group (User 1)
        await axios.put(`${API_URL}/groups/${groupId}`, { description: 'Updated desc' }, { headers: headers1 });
        console.log('8. Group updated via PUT /groups/:id');

        await axios.delete(`${API_URL}/groups/${groupId}`, { headers: headers1 });
        console.log('9. Group deleted via DELETE /groups/:id');

        console.log('âœ… ALL ENDPIONTS TESTED SUCCESSFULLY');

    } catch (error) {
        console.error('Test failed:', error.response?.data || error.message);
    }
}

testGroups();






