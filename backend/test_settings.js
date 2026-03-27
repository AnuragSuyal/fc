const axios = require('axios');

async function runTests() {
    const baseURL = 'http://localhost:5000/api';

    try {
        console.log('Registering test user...');
        const regRes = await axios.post(`${baseURL}/auth/register`, {
            username: `u${Math.floor(Date.now() / 1000)}`,
            email: `set${Date.now()}@test.com`,
            password: 'password123'
        });
        const token = regRes.data.token;
        console.log('User registered. Token acquired.');

        const headers = { Authorization: `Bearer ${token}` };

        console.log('\n1. Get settings:');
        let res = await axios.get(`${baseURL}/settings`, { headers });
        console.log(res.data);

        console.log('\n2. Update notifications:');
        res = await axios.put(`${baseURL}/settings/notifications`, {
            friendOnline: true,
            messages: true,
            gifts: false,
            gameInvites: true,
            eventReminders: true,
            sound: true,
            vibrate: false
        }, { headers });
        console.log(res.data);

        console.log('\n3. Update privacy:');
        res = await axios.put(`${baseURL}/settings/privacy`, {
            showOnline: true,
            showActivity: true,
            allowFriendRequests: true,
            showLocation: false
        }, { headers });
        console.log(res.data);

        console.log('\n4. Update quiet hours:');
        res = await axios.put(`${baseURL}/settings/quiet-hours`, {
            enabled: true,
            start: '23:00',
            end: '07:00'
        }, { headers });
        console.log(res.data);

        console.log('\n5. Update language:');
        res = await axios.put(`${baseURL}/settings/language`, {
            language: 'es',
            currency: 'EUR'
        }, { headers });
        console.log(res.data);

        console.log('\n6. Update profile:');
        res = await axios.put(`${baseURL}/settings/profile`, {
            bio: 'Gamer and streamer',
            avatar: 'new-avatar-url.jpg'
        }, { headers });
        console.log(res.data);

        console.log('\n7. Change password:');
        res = await axios.post(`${baseURL}/settings/change-password`, {
            currentPassword: 'password123',
            newPassword: 'newpassword123'
        }, { headers });
        console.log(res.data);

        console.log('\n8. Delete account:');
        // Using new password to login if needed, but token should still be valid
        res = await axios.delete(`${baseURL}/settings/account`, { headers });
        console.log(res.data);

        console.log('\nâœ… All Settings Endpoints Tested Successfully!');

    } catch (err) {
        console.error('Test failed:', err.response ? err.response.data : err.message);
    }
}

runTests();






