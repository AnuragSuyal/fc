const { z } = require('zod');
const dotenv = require('dotenv');

dotenv.config();

const envSchema = z.object({
    PORT: z.string().default('5000'),
    NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
    MONGO_URI: z.string().url().or(z.string().min(1)),
    MONGODB_URI: z.string().url().optional(),
    REDIS_URL: z.string().url(),
    JWT_SECRET: z.string().min(32),
    REFRESH_SECRET: z.string().min(32),
    STRIPE_SECRET_KEY: z.string().startsWith('sk_').or(z.literal('')).optional(),
    LIVEKIT_API_KEY: z.string().optional(),
    LIVEKIT_API_SECRET: z.string().optional(),
    LIVEKIT_URL: z.string().optional()
});

const envVars = { ...process.env, MONGO_URI: process.env.MONGO_URI || process.env.MONGODB_URI };
const parsed = envSchema.safeParse(envVars);

if (!parsed.success) {
    console.error('âŒ Invalid environment variables:', JSON.stringify(parsed.error.format(), null, 2));
    process.exit(1);
}

module.exports = parsed.data;






