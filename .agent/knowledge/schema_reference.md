# Schema Reference (Mongoose)

Detailed mapping of core data structures to ensure consistency between MongoDB and Flutter Models.

## ðŸ‘¤ User Model
**Reference**: `backend/src/models/User.js`

| Field | Type | Description |
|-------|------|-------------|
| `username` | String | Unique, 3-20 chars. |
| `email` | String | Unique. |
| `coins` | Number | Main currency. |
| `gems` | Number | Premium currency. |
| `level` | Number | XP-based progression (default: 1). |
| `vipLevel` | Number | Subscription tier (0-10). |
| `status` | Object | `{ isOnline, lastActive }`. |

---

## ðŸ  Room Model
**Reference**: `backend/src/models/Room.js`

| Field | Type | Description |
|-------|------|-------------|
| `roomId` | String | Display ID (e.g., "1698332"). |
| `type` | String | `voice`, `music`, `video`, `chat`, `auction`. |
| `hostId` | ObjectId | Ref to `User`. |
| `participants` | Array | Objects containing `userId`, `role`, `seatIndex`, `isSpeaking`. |
| `seatIndex` | Number | -1 (listener) to 8 (speaker seats). |
| `economy` | Object | `{ totalEarned, todayEarned }`. |
| `metrics` | Object | `{ followers, totalVisits, totalMessages }`. |

### Participant Roles
- `host`: The creator (Seat 0).
- `cohost`: Granted moderation + speaker rights.
- `moderator`: Room admin rights.
- `speaker`: Allowed to use mic (Seat 1-8).
- `listener`: Default role (no seat).

---

## ðŸŽ Gift Model
**Reference**: `backend/src/models/Gift.js`

| Field | Type | Description |
|-------|------|-------------|
| `name` | String | Display name. |
| `price` | Number | Coin cost. |
| `animation` | String | Lottie JSON filename. |
| `type` | String | `regular`, `vip`, `luxury`. |






