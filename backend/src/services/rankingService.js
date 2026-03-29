const redis = require('redis');
const User = require('../models/User');

class RankingService {
    constructor() {
        this.redisClient = null;
        this.ownsRedisClient = false;
    }

    async initialize({ redisClient = null } = {}) {
        if (redisClient) {
            this.redisClient = redisClient;
            this.ownsRedisClient = false;
            return this.redisClient;
        }

        if (this.redisClient?.isOpen) {
            return this.redisClient;
        }

        this.redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
        this.redisClient.on('error', (err) => console.log('Redis Client Error', err));
        await this.redisClient.connect();
        this.ownsRedisClient = true;
        console.log('Ranking Service connected to Redis');
        return this.redisClient;
    }

    configure({ redisClient } = {}) {
        if (redisClient) {
            this.redisClient = redisClient;
            this.ownsRedisClient = false;
        }
        return this;
    }

    getClient() {
        return (this.redisClient && (this.redisClient.isOpen || this.redisClient.isReady)) ? this.redisClient : null;
    }

    colorClashSeasonKey(seasonId) {
        return `ranking:colorclash:season:${seasonId}:rating`;
    }

    async zRangeWithScoresDesc(key, start, stop) {
        const client = this.getClient();
        if (!client) return [];

        if (typeof client.zRevRangeWithScores === 'function') {
            return client.zRevRangeWithScores(key, start, stop);
        }

        if (typeof client.sendCommand === 'function') {
            const raw = await client.sendCommand([
                'ZREVRANGE',
                key,
                String(start),
                String(stop),
                'WITHSCORES'
            ]);
            const parsed = [];
            for (let index = 0; index < raw.length; index += 2) {
                parsed.push({
                    value: raw[index],
                    score: Number(raw[index + 1] || 0)
                });
            }
            return parsed;
        }

        if (typeof client.zRangeWithScores === 'function') {
            return client.zRangeWithScores(key, start, stop, { REV: true });
        }

        return [];
    }

    async zRevRankCompat(key, member) {
        const client = this.getClient();
        if (!client) return null;
        if (typeof client.zRevRank === 'function') {
            return client.zRevRank(key, member);
        }
        const rows = await this.zRangeWithScoresDesc(key, 0, 100000);
        const index = rows.findIndex((entry) => entry.value === member.toString());
        return index >= 0 ? index : null;
    }

    async zScoreCompat(key, member) {
        const client = this.getClient();
        if (!client) return null;
        if (typeof client.zScore === 'function') {
            return client.zScore(key, member);
        }
        const rows = await this.zRangeWithScoresDesc(key, 0, 100000);
        const entry = rows.find((row) => row.value === member.toString());
        return entry ? Number(entry.score || 0) : null;
    }

    async syncUserProfile(user) {
        const client = this.getClient();
        if (!client) return;
        try {
            const key = `user:profile:${user._id.toString()}`;
            await client.hSet(key, {
                username: user.username,
                avatar: user.avatar || 'default-avatar.png',
                level: String(user.level || 1),
                vipLevel: String(user.vipLevel || 0)
            });
            await client.expire(key, 86400 * 7);
        } catch (error) {
            console.error('Error syncing user profile to redis:', error);
        }
    }

    async updateGiftRanking(userId, giftValue, roomId = null) {
        const client = this.getClient();
        if (!client) return;
        try {
            const now = new Date();
            const dayKey = `ranking:gifts:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `ranking:gifts:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `ranking:gifts:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = 'ranking:gifts:alltime';

            const val = Number(giftValue);
            const uid = userId.toString();

            const multi = client.multi();
            multi.zIncrBy(dayKey, val, uid);
            multi.zIncrBy(weekKey, val, uid);
            multi.zIncrBy(monthKey, val, uid);
            multi.zIncrBy(allTimeKey, val, uid);
            if (roomId) multi.zIncrBy(`ranking:gifts:room:${roomId.toString()}`, val, uid);
            await multi.exec();

            await client.expire(dayKey, 86400 * 2);
            await client.expire(weekKey, 86400 * 14);
            await client.expire(monthKey, 86400 * 60);
        } catch (error) {
            console.error('Error updating gift ranking:', error);
        }
    }

    async updateCharmRanking(userId, giftValue) {
        const client = this.getClient();
        if (!client) return;
        try {
            const now = new Date();
            const dayKey = `ranking:charm:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `ranking:charm:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `ranking:charm:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = 'ranking:charm:alltime';

            const val = Number(giftValue);
            const uid = userId.toString();

            const multi = client.multi();
            multi.zIncrBy(dayKey, val, uid);
            multi.zIncrBy(weekKey, val, uid);
            multi.zIncrBy(monthKey, val, uid);
            multi.zIncrBy(allTimeKey, val, uid);
            await multi.exec();

            await client.expire(dayKey, 86400 * 2);
            await client.expire(weekKey, 86400 * 14);
            await client.expire(monthKey, 86400 * 60);
        } catch (error) {
            console.error('Error updating charm ranking:', error);
        }
    }

    async updateGameRanking(userId, gameType, won) {
        const client = this.getClient();
        if (!client || !won) return;

        try {
            const now = new Date();
            const gameKey = `ranking:game:${gameType}`;
            const dayKey = `${gameKey}:daily:${now.toISOString().split('T')[0]}`;
            const weekKey = `${gameKey}:weekly:${this.getWeekNumber(now)}`;
            const monthKey = `${gameKey}:monthly:${now.getFullYear()}-${now.getMonth() + 1}`;
            const allTimeKey = `${gameKey}:alltime`;

            const uid = userId.toString();
            const multi = client.multi();
            multi.zIncrBy(dayKey, 1, uid);
            multi.zIncrBy(weekKey, 1, uid);
            multi.zIncrBy(monthKey, 1, uid);
            multi.zIncrBy(allTimeKey, 1, uid);
            await multi.exec();

            await client.expire(dayKey, 86400 * 2);
            await client.expire(weekKey, 86400 * 14);
            await client.expire(monthKey, 86400 * 60);
        } catch (error) {
            console.error('Error updating game ranking', error);
        }
    }

    async updateColorClashSeasonRank({ seasonId, userId, rating }) {
        const client = this.getClient();
        if (!client || !seasonId || !userId) return;
        await client.zAdd(this.colorClashSeasonKey(seasonId), [{
            score: Number(rating || 0),
            value: userId.toString()
        }]);
    }

    async getColorClashSeasonLeaderboard({ seasonId, limit = 100, offset = 0 } = {}) {
        if (!seasonId) return [];
        return this.zRangeWithScoresDesc(
            this.colorClashSeasonKey(seasonId),
            Number(offset || 0),
            Number(offset || 0) + Number(limit || 100) - 1
        );
    }

    async getColorClashUserSeasonRank({ seasonId, userId } = {}) {
        if (!seasonId || !userId) return null;
        const key = this.colorClashSeasonKey(seasonId);
        const rank = await this.zRevRankCompat(key, userId.toString());
        const score = await this.zScoreCompat(key, userId.toString());
        if (rank === null) return null;
        return {
            rank: rank + 1,
            score: Math.round(Number(score || 0))
        };
    }

    async getRankings(type, period = 'alltime', limit = 100, roomId = null) {
        const client = this.getClient();
        if (!client) return [];
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

            const rankings = await this.zRangeWithScoresDesc(key, 0, limit - 1);
            if (!rankings.length) return [];

            const userIds = rankings.map((entry) => entry.value);
            const users = await User.find({ _id: { $in: userIds } })
                .select('username avatar level vipLevel');
            const userMap = {};
            users.forEach((user) => {
                userMap[user._id.toString()] = user;
            });

            return rankings.map((entry, index) => ({
                rank: index + 1,
                userId: entry.value,
                username: userMap[entry.value]?.username || 'Unknown',
                avatar: userMap[entry.value]?.avatar || 'default-avatar.png',
                level: userMap[entry.value]?.level || 1,
                vipLevel: userMap[entry.value]?.vipLevel || 0,
                score: Math.floor(Number(entry.score || 0))
            }));
        } catch (error) {
            console.error('Error getting rankings:', error);
            return [];
        }
    }

    async getUserRank(userId, type, period = 'alltime') {
        const client = this.getClient();
        if (!client) return null;
        try {
            const now = new Date();
            let key;
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

            const rank = await this.zRevRankCompat(key, userId.toString());
            const score = await this.zScoreCompat(key, userId.toString());
            if (rank === null) return null;
            return {
                rank: rank + 1,
                score: Math.floor(Number(score || 0))
            };
        } catch (error) {
            console.error('Error getting user rank:', error);
            return null;
        }
    }

    getWeekNumber(date) {
        const d = new Date(date);
        d.setHours(0, 0, 0, 0);
        d.setDate(d.getDate() + 4 - (d.getDay() || 7));
        const yearStart = new Date(d.getFullYear(), 0, 1);
        return Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    }
}

module.exports = new RankingService();
