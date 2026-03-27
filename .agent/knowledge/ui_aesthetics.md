# UI & Aesthetics (Premium Design System)

Guidance for maintaining the "High Fidelity" look and feel of Friend Circle.

## ðŸŽ¨ Color Palette (Lux Dark Theme)

| Token | Hex/Value | Description |
|-------|-----------|-------------|
| `Deep Space Blue` | `0xFF1E1E2E` | Primary background start. |
| `Deep Purple` | `0xFF2D1B36` | Primary background end. |
| `Glow Blue` | `Colors.blueAccent` | Active speaking state / Voice mode. |
| `VIP Amber` | `Colors.amber` | Host crowns / VIP badges. |
| `Success Teal` | `Colors.tealAccent` | Confirmation / "Join" buttons. |

## ðŸ”® Glassmorphism Patterns

### Standard Glass Container
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.05),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: Colors.white.withOpacity(0.1)),
  ),
  child: ...
)
```

### Bottom Toolbar
- **Background**: `Colors.black.withOpacity(0.3)`
- **Blur**: Apply `BackdropFilter` with `sigmaX: 10, sigmaY: 10` for depth.

## âœ¨ Micro-interactions

### 1. Haptics
- **Light**: Small UI taps (tabs, icons).
- **Medium**: Success actions (taking seat, sending reaction).
- **Heavy/Selection**: High-value actions (sending gift, joining room).
- **Reference**: `HapticsUtil.lightImpact()`.

### 2. Pulse Effect
- **Speaking**: Avatars should use `_SpeakingPulseEffect` when `isSpeaking` is true.
- **Scale**: Pulse scale factor should stay between `1.0` and `1.2`.

### 3. Visual Payoff (Burst)
- All floating elements must use `ReactionAnimationOverlay` with a small random position jitter to avoid overlap.






