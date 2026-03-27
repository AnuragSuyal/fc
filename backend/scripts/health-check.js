const http = require('http');

const options = {
    hostname: 'localhost',
    port: 5000,
    path: '/health',
    method: 'GET',
    timeout: 2000
};

const req = http.request(options, (res) => {
    console.log(`Health Check Status: ${res.statusCode}`);
    let data = '';
    res.on('data', (chunk) => {
        data += chunk;
    });
    res.on('end', () => {
        try {
            const result = JSON.parse(data);
            console.log('âœ… Server is healthy');
            console.log('MongoDB:', result.services.mongodb);
            console.log('Redis:', result.services.redis);
        } catch (e) {
            console.log('âŒ Invalid response');
        }
    });
});

req.on('error', (e) => {
    console.log('âŒ Server is DOWN:', e.message);
});

req.end();






