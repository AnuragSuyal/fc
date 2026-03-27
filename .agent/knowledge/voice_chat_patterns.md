# Voice Chat Implementation (LiveKit)

Friend Circle uses LiveKit for low-latency, high-fidelity voice chat.

## ðŸ—ï¸ Architecture

### 1. Token Generation (Backend)
- **Endpoint**: `POST /api/rooms/:id/token`
- **Auth**: Required.
- **Logic**: Uses `livekit-server-sdk`.
- **Grants**: Must include `{ roomJoin: true, room: roomId, canPublish: true, canSubscribe: true }`.
- **Identity**: Should be the `userId` to allow participant tracking.

### 2. Platform Specifics (Mobile)
- **iOS**: Must have `NSMicrophoneUsageDescription` and `UIBackgroundModes` containing `audio`.
- **Android**: Must have `android.permission.RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, and `BLUETOOTH_CONNECT`.
- **Persistence**: Managed by `flutter_background_service`.
- **Client**: `livekit_client`.
- **Lifecycle**:
  - `initAudio()`: Sets up `audio_session` for voice call mode.
  - `connectToRoom()`: Connects to the LiveKit server using the token.
  - `disconnect()`: Cleans up local tracks and finishes background service.

## ðŸª‘ Seating System
- Seats are 0-indexed.
- **Seat 0**: Dedicated to the Host.
- **Seats 1-8**: Dedicated to participants on the grid.
- **Role Transition**: Taking a seat (`POST /api/rooms/:id/seat`) promotes a participant from `listener` to `speaker`.

## ðŸ›¡ï¸ Best Practices
- **Backgrounding**: Always check `Permission.microphone` before initializing the background service.
- **Cleanup**: Ensure `VoiceService.disconnect()` is called on `Navigator.pop` or Room Leave to prevent parasitic battery drain.
- **Visuals**: Use `Positioned.fill` for animation overlays to ensure they sit on top of the "Glow Layer".






