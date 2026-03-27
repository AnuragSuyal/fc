const axios = require('axios');

async function testApi() {
    try {
        const response = await axios.get('http://localhost:5000/api/rooms?category=all');
        console.log('Response:', JSON.stringify(response.data, null, 2));
    } catch (err) {
        console.error('Error:', err.response ? err.response.data : err.message);
    }
}

testApi();






