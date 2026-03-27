const twilio = require('twilio');
const redisClient = require('../config/redis');

class OTPService {
    constructor() {
        // Only initialize Twilio if credentials exist and look valid
        try {
            if (process.env.TWILIO_ACCOUNT_SID?.startsWith('AC') && process.env.TWILIO_AUTH_TOKEN) {
                this.client = twilio(
                    process.env.TWILIO_ACCOUNT_SID,
                    process.env.TWILIO_AUTH_TOKEN
                );
            }
        } catch (err) {
            console.error('Twilio initialization failed (skipping):', err.message);
            this.client = null;
        }
    }

    // Generate 6-digit OTP
    generateOTP() {
        return Math.floor(100000 + Math.random() * 900000).toString();
    }

    // Store OTP with expiry (5 minutes)
    async storeOTP(phone, otp) {
        console.log(`[OTP DEBUG] Storing for ${phone}: ${otp}`);
        // Store in Redis with an expiration of 300 seconds (5 minutes)
        await redisClient.set(`otp:${phone}`, otp, { EX: 300 });
    }

    // Verify OTP
    async verifyOTP(phone, otp) {
        const stored = await redisClient.get(`otp:${phone}`);
        console.log(`[OTP DEBUG] Verifying ${phone}: input=${otp}, stored=${stored}`);
        
        if (!stored) return false;

        const isValid = stored === otp;
        if (isValid) {
            await redisClient.del(`otp:${phone}`); // Delete after successful use
        }
        return isValid;
    }

    // Send SMS via Twilio
    async sendSMS(phone, otp) {
        if (!this.client || !process.env.TWILIO_PHONE_NUMBER) {
            return this.sendMockSMS(phone, otp);
        }

        try {
            const message = await this.client.messages.create({
                body: `Your Friend Circle verification code is: ${otp}`,
                from: process.env.TWILIO_PHONE_NUMBER,
                to: phone
            });
            console.log('SMS sent:', message.sid);
            return true;
        } catch (error) {
            console.error('SMS error:', error);
            return this.sendMockSMS(phone, otp); // Fallback to mock if Twilio fails
        }
    }

    // Mock SMS for development
    async sendMockSMS(phone, otp) {
        console.log('\n----------------------------------------');
        console.log(`ðŸ“± [MOCK SMS] To: ${phone}`);
        console.log(`ðŸ’¬ Code: ${otp}`);
        console.log('----------------------------------------\n');
        return true;
    }
}

module.exports = new OTPService();






