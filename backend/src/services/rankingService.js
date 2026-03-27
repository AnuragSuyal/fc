const redis = require('redis');
const User = require('../models/User');

class RankingService {
    constructor() {
        this.redisClient = null;
    }

    async initialize() {
        this.redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
        this.redisClient.on('error', (err) => console.log('Redis Client Error', err));
        await this.redisClient.connect();
        console.log('âœ… Ranking Service connected to Redis');
    }

    // Sync user profile data to redis for fast leaderboard lookups
    async syncUserProfile(user) {
        if (!this.redisClient || !this.redisClient.isOpen) return;
        try {
            const key = `user:profile:${user._id.toString()}`;
            await this.redisClient.hSet(key, {
                username: user.username,
                avatar: user.avatar || 'default-avatar.png',
                level: user.level.toString(),
                vipLevel: user.vipLevel.toString()
            });
            await this.redisClient.expire(key, 86400 * 7); // Cache for 7 days
        } catch (error) {
            console.error('Error syncing user profile to redis:', error);
        }
    }

    // Update gift ranking
    async updateGiftRanking(userId, giftValue, roomId = null) {
        if (!this.redisClient || !this.redisClient.isOpen) return;
        try {
            const now = new Date();
            const dayKey = `ranking:gifts:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `ranking:gifts:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `ranking:gifts:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = 'ranking:gifts:alltime';

            const val = Number(giftValue);
            const uid = userId.toString();

            const multi = this.redisClient.multi();
            multi.zIncrBy(dayKey, val, uid);
            multi.zIncrBy(weekKey, val, uid);
            multi.zIncrBy(monthKey, val, uid);
            multi.zIncrBy(allTimeKey, val, uid);
            if (roomId) multi.zIncrBy(`ranking:gifts:room:${roomId.toString()}`, val, uid);
            await multi.exec();

            // Set expiry for daily/weekly/monthly keys
            await this.redisClient.expire(dayKey, 86400 * 2); // 2 days
            await this.redisClient.expire(weekKey, 86400 * 14); // 14 days
            await this.redisClient.expire(monthKey, 86400 * 60); // 60 days
        } catch (error) {
            console.error('Error updating gift ranking:', error);
        }
    }

    // Update charm ranking (gifts received)
    async updateCharmRanking(userId, giftValue) {
        if (!this.redisClient || !this.redisClient.isOpen) return;
        try {
            const now = new Date();
            const dayKey = `ranking:charm:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `ranking:charm:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `ranking:charm:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = 'ranking:charm:alltime';

            const val = Number(giftValue);
            const uid = userId.toString();

            const multi = this.redisClient.multi();
            multi.zIncrBy(dayKey, val, uid);
            multi.zIncrBy(weekKey, val, uid);
            multi.zIncrBy(monthKey, val, uid);
            multi.zIncrBy(allTimeKey, val, uid);
            await multi.exec();

            // Set expiry
            await this.redisClient.expire(dayKey, 86400 * 2);
            await this.redisClient.expire(weekKey, 86400 * 14);
            await this.redisClient.expire(monthKey, 86400 * 60);
        } catch (error) {
            console.error('Error updating charm ranking:', error);
        }
    }

    // Update game ranking
    async updateGameRanking(userId, gameType, won) {
        if (!this.redisClient || !this.redisClient.isOpen) return;
        if (!won) return;

        try {
            const now = new Date();
            const gameKey = `ranking:game:${gameType}`;
            const dayKey = `${gameKey}:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `${gameKey}:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `${gameKey}:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = `${gameKey}:alltime`;

            const multi = this.redisClient.multi();
            multi.zIncrBy(dayKey, 1, userId);
            multi.zIncrBy(weekKey, 1, userId);
            multi.zIncrBy(monthKey, 1, userId);
            multi.zIncrBy(allTimeKey, 1, userId);
            await multi.exec();

            await this.redisClient.expire(dayKey, 86400 * 2);
            await this.redisClient.expire(weekKey, 86400 * 14);
            await this.redisClient.expire(monthKey, 86400 * 60);
        } catch (error) {
            console.error('Error updating game ranking', error);
        }
    }

    // Get rankings
    async getRankings(type, period = 'alltime', limit = 100, roomId = null) {
        if (!this.redisClient || !this.redisClient.isOpen) return [];
        try {
            let key;

            if (roomId) {
                key = `ranking:${type}:room:${roomId}`;
            } else {
                const now = new Date();
                switch (period) {
                    case 'daily':
                        key = `ranking:${type}:daily:${now.toISOString().split('T')[0]}`;
                        break;
                    case 'weekly':
                        key = `ranking:${type}:weekly:${this.getWeekNumber(now)}`;
                        break;
                    case 'monthly':
                        key = `ranking:${type}:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
                        break;
                    default:
                        key = `ranking:${type}:alltime`;
                }
            }

            let rankings;
            try {
                // Newer Redis (>=6.2): ZRANGE ... REV WITHSCORES
                rankings = await this.redisClient.zRangeWithScores(key, 0, limit - 1, { REV: true });
            } catch (err) {
                console.error('Redis ranking error, attempting fallback:', err);
                rankings = null;
            }

            // Fallback for older Redis versions (e.g., 3.x) using ZREVRANGE WITHSCORES
            if (!rankings) {
                try {
                    const raw = await this.redisClient.sendCommand([
                        'ZREVRANGE',
                        key,
                        '0',
                        String(limit - 1),
                        'WITHSCORES'
                    ]);
                    const parsed = [];
                    for (let i = 0; i < raw.length; i += 2) {
                        parsed.push({ value: raw[i], score: Number(raw[i + 1]) });
                    }
                    rankings = parsed;
                } catch (fallbackErr) {
                    console.error('Redis ranking fallback failed:', fallbackErr);
                    rankings = [];
                }
            }
            if (!rankings || rankings.length === 0) return [];

            // Get user details for each ranked user
            const userIds = rankings.map(r => r.value);
            const users = await User.find({ _id: { $in: userIds } })
                .select('username avatar level vipLevel');

            const userMap = {};
            users.forEach(u => {
                userMap[u._id.toString()] = u;
            });

            return rankings.map((r, index) => ({
                rank: index + 1,
                userId: r.value,
                username: userMap[r.value]?.username || 'Unknown',
                avatar: userMap[r.value]?.avatar || 'default-avatar.png',
                level: userMap[r.value]?.level || 1,
                vipLevel: userMap[r.value]?.vipLevel || 0,
                score: Math.floor(r.score)
            }));
        } catch (error) {
            console.error('Error getting rankings:', error);
            return [];
        }
    }

    // Get user's rank
    async getUserRank(userId, type, period = 'alltime') {
        if (!this.redisClient || !this.redisClient.isOpen) return null;
        try {
            let key;

            const now = new Date();
            switch (period) {
                case 'daily':
                    key = `ranking:${type}:daily:${now.toISOString().split('T')[0]}`;
                    break;
                case 'weekly':
                    key = `ranking:${type}:weekly:${this.getWeekNumber(now)}`;
                    break;
                case 'monthly':
                    key = `ranking:${type}:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
                    break;
                default:
                    key = `ranking:${type}:alltime`;
            }

            const rank = await this.redisClient.zRevRank(key, userId);
            const score = await this.redisClient.zScore(key, userId);

            if (rank === null) return null;

            return {
                rank: rank + 1,
                score: Math.floor(score || 0)
            };
        } catch (error) {
            console.error('Error getting user rank:', error);
            return null;
        }
    }

    // Helper to get week number
    getWeekNumber(date) {
        const d = new Date(date);
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() + 4 - (d.getDay() || 7));
        const yearStart = new Date(d.getFullYear(), 0, 1);
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    }
}

module.exports = new RankingService();






