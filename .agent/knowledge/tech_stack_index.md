# Friend Circle: Master Tech Index

This index anchors Antigravity's development process to official specifications and best practices. **DO NOT GUESS. READ DOCS FIRST.**

## ðŸ“± Frontend (Flutter)
- [Flutter Core](https://docs.flutter.dev/) | [Dart Guide](https://dart.dev/guides)
- **State Mgmt**: [Riverpod](https://riverpod.dev/) (Preferred for scaling) | [Provider](https://pub.dev/packages/provider) (Current)
- **Networking**: [Dio](https://pub.dev/packages/dio) | [Retrofit](https://pub.dev/packages/retrofit)
- **Real-time**: [Socket.IO Client](https://pub.dev/packages/socket_io_client) | [LiveKit Flutter](https://docs.livekit.io/clients/flutter/)
- **Storage**: [Isar](https://isar.dev/) (NoSQL) | [Sqflite](https://pub.dev/packages/sqflite) (SQL)
- **Visuals**: [Lottie](https://airbnb.io/lottie/#/flutter) | [Animations](https://docs.flutter.dev/ui/animations)

## ðŸš€ Backend (Node.js)
- [Node.js API](https://nodejs.org/api/) | [Best Practices](https://github.com/goldbergyoni/nodebestpractices)
- **Framework**: [Express.js](https://expressjs.com/)
- **Real-time**: [Socket.IO Server](https://socket.io/docs/v4/server-api/) | [Redis Adapter](https://socket.io/docs/v4/redis-adapter/)
- **Database**: [MongoDB Manual](https://www.mongodb.com/docs/manual/) | [Mongoose Guide](https://mongoosejs.com/docs/guide.html)
- **Caching**: [Redis Patterns](https://redis.io/docs/manual/patterns/) | [IoRedis](https://github.com/redis/ioredis)
- **Voice**: [LiveKit Server](https://docs.livekit.io/self-hosting/overview/) | [WebRTC Fundamentals](https://webrtc.org/getting-started/overview)

## ðŸ—ï¸ DevOps & Scaling
- **Containerization**: [Docker](https://docs.docker.com/) | [Docker Compose](https://docs.docker.com/compose/)
- **Proxy/LB**: [NGINX WebSocket Proxying](https://nginx.org/en/docs/http/websocket.html)
- **Auth**: [JWT](https://jwt.io/introduction) | [Passport.js](https://www.passportjs.org/)

## ðŸ’° Economy & Payments
- **Global**: [Stripe API](https://stripe.com/docs/api) | [Stripe Webhooks](https://stripe.com/docs/webhooks)
- **Mobile Subscriptions**: [RevenueCat](https://www.revenuecat.com/docs/)

---

## ðŸ› ï¸ Verified Architectural Patterns
1. **Presence**: Tracked via Redis Sorted Sets for leaderboards and Room Sets for occupancy.
2. **Gifting**: Distributed Transactions (Atomic MongoDB updates + Redis Cache invalidate).
3. **Voice**: LiveKit Selective Forwarding Unit (SFU) architecture.






