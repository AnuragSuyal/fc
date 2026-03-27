# Socket.IO Protocol Specification

This document defines the real-time communication contract between the Flutter frontend and the Node.js backend.

## ðŸ  Room Events

### `room:join` / `join_room`
- **Direction**: Frontend -> Backend
- **Payload**: `{ "roomId": string }` or `string`
- **Result**: Socket joins `room:${roomId}` channel.

### `room:message`
- **Direction**: Bidirectional
- **Payload (Regular)**:
  ```json
  {
    "roomId": "string",
    "content": "string",
    "type": "text"
  }
  ```
- **Payload (Emoji-Only)**:
  ```json
  {
    "roomId": "string",
    "content": "string",
    "type": "emoji",
    "emojis": ["ðŸ”¥", "ðŸ”¥"],
    "seatIndex": number
  }
  ```

### `room:reaction`
- **Direction**: Bidirectional
- **Payload**:
  ```json
  {
    "roomId": "string",
    "userId": "string",
    "emoji": "string",
    "seatIndex": number
  }
  ```

### `room:sound_effect`
- **Direction**: Bidirectional
- **Payload**:
  ```json
  {
    "roomId": "string",
    "soundId": "string",
    "seatIndex": number
  }
  ```

## ðŸŽ Gifting Events

### `send_gift`
- **Direction**: Frontend -> Backend
- **Payload**: `{ "toUserId": string, "roomId": string, "giftId": string }`

### `receive_gift`
- **Direction**: Backend -> Frontend
- **Payload**:
  ```json
  {
    "sender": { "id": "string", "username": "string" },
    "recipient": { "id": "string", "username": "string" },
    "giftId": "string",
    "animation": "string"
  }
  ```

## ðŸ’° Wallet & Status

### `balance_update`
- **Direction**: Backend -> Frontend
- **Payload**: `{ "coins": number, "gems": number }`






