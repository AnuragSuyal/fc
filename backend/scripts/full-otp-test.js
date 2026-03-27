const http = require('http');

async function request(options, data) {
    return new Promise((resolve, reject) => {
        const req = http.request(options, (res) => {
            let body = '';
            res.on('data', chunk => body += chunk);
            res.on('end', () => resolve({ statusCode: res.statusCode, headers: res.headers, body: JSON.parse(body) }));
        });
        req.on('error', reject);
        if (data) req.write(JSON.stringify(data));
        req.end();
    });
}

async function runTest() {
    const phone = '+919876543321';
    console.log(`ðŸš€ Starting OTP verification for ${phone}`);

    try {
        // 1. Send OTP
        const sendRes = await request({
            hostname: 'localhost',
            port: 5000,
            path: '/api/auth/otp/send',
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, { phone });

        console.log(`âœ… Send OTP Result: ${sendRes.statusCode}`);
        const otp = sendRes.body.otp;
        console.log(`ðŸ”‘ Received OTP: ${otp}`);

        if (!otp) throw new Error('No OTP received in response');

        // 2. Verify OTP
        const verifyRes = await request({
            hostname: 'localhost',
            port: 5000,
            path: '/api/auth/otp/verify',
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        }, { phone, otp });

        console.log(`âœ… Verify OTP Result: ${verifyRes.statusCode}`);
        console.log(`ðŸ“« Response Body: ${JSON.stringify(verifyRes.body, null, 2)}`);

        if (verifyRes.statusCode === 200) {
            console.log('\nâœ… VERIFICATION SUCCESSFUL');
        } else {
            console.log('\nâŒ VERIFICATION FAILED');
        }

    } catch (error) {
        console.error('ðŸ’¥ Test Error:', error.message);
    }
}

runTest();






