# Friend Circle: Technical Knowledge Base & Best Practices

This directory serves as the "Source of Truth" for Antigravity (the agent) to ensure high-fidelity, error-free development of the Friend Circle application.

## ðŸ“Œ Technology Stack

### Frontend (Flutter)
- **State Management**: Provider (for Auth/UI state).
- **Voice**: LiveKit Client + flutter_background_service.
- **Networking**: Dio + Socket.IO Client.
- **UI**: Custom premium design system (Glassmorphism, Lottie, Haptics).

### Backend (Node.js/Express)
- **Database**: MongoDB (Mongoose).
- **Real-time**: Socket.IO.
- **Voice Server**: LiveKit Server SDK.
- **Cache**: Redis.

## ðŸ“– Knowledge Index
1. [Socket Event Protocol](socket_protocol.md) - Payload specs for real-time loops.
2. [Voice Chat Patterns](voice_chat_patterns.md) - Implementation architecture for LiveKit.
3. [Schema Reference](schema_reference.md) - Mongoose models and relationship maps.
4. [UI & Aesthetics](ui_aesthetics.md) - Tokens for the visual payoff system.






