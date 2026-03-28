// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

final Map<String, String> _cachedDataUrls = <String, String>{};

Future<void> playSound(String soundId) async {
  try {
    final audio = html.AudioElement(_resolveDataUrl(soundId))
      ..volume = soundId == 'friend_online' ? 0.34 : 0.42
      ..autoplay = false
      ..preload = 'auto';

    await audio.play();
  } catch (_) {}
}

String _resolveDataUrl(String soundId) {
  return _cachedDataUrls.putIfAbsent(
    soundId,
    () => Uri.dataFromBytes(
      _buildWaveBytes(_segmentsFor(soundId)),
      mimeType: 'audio/wav',
    ).toString(),
  );
}

List<_ToneSegment> _segmentsFor(String soundId) {
  switch (soundId) {
    case 'friend_request':
      return const <_ToneSegment>[
        _ToneSegment(frequency: 784, durationMs: 120, amplitude: 0.42),
        _ToneSegment.silence(durationMs: 40),
        _ToneSegment(frequency: 1047, durationMs: 170, amplitude: 0.48),
      ];
    case 'friend_online':
      return const <_ToneSegment>[
        _ToneSegment(frequency: 659, durationMs: 120, amplitude: 0.28),
        _ToneSegment.silence(durationMs: 35),
        _ToneSegment(frequency: 880, durationMs: 110, amplitude: 0.34),
      ];
    case 'message':
      return const <_ToneSegment>[
        _ToneSegment(frequency: 988, durationMs: 90, amplitude: 0.34),
        _ToneSegment.silence(durationMs: 28),
        _ToneSegment(frequency: 1319, durationMs: 120, amplitude: 0.38),
      ];
    default:
      return const <_ToneSegment>[
        _ToneSegment(frequency: 740, durationMs: 120, amplitude: 0.32),
      ];
  }
}

Uint8List _buildWaveBytes(List<_ToneSegment> segments) {
  const int sampleRate = 44100;
  const int bytesPerSample = 2;
  const int channels = 1;

  final totalSamples = segments.fold<int>(
    0,
    (sum, segment) => sum + ((sampleRate * segment.durationMs) ~/ 1000),
  );
  final dataLength = totalSamples * bytesPerSample * channels;
  final bytes = ByteData(44 + dataLength);

  _writeAscii(bytes, 0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(
    28,
    sampleRate * bytesPerSample * channels,
    Endian.little,
  );
  bytes.setUint16(32, bytesPerSample * channels, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  _writeAscii(bytes, 36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);

  var offset = 44;
  for (final segment in segments) {
    final sampleCount =
        ((sampleRate * segment.durationMs) ~/ 1000).clamp(1, 1 << 30);
    final attackSamples = math.max(1, sampleCount ~/ 10);
    final releaseSamples = math.max(1, sampleCount ~/ 8);

    for (var index = 0; index < sampleCount; index++) {
      var sample = 0.0;
      if (segment.frequency > 0) {
        final position = index / sampleRate;
        var envelope = 1.0;
        if (index < attackSamples) {
          envelope = index / attackSamples;
        } else if (index > sampleCount - releaseSamples) {
          envelope = (sampleCount - index) / releaseSamples;
        }

        sample = math.sin(2 * math.pi * segment.frequency * position) *
            segment.amplitude *
            envelope;
      }

      final pcmValue = (sample * 32767).round().clamp(-32768, 32767);
      bytes.setInt16(offset, pcmValue, Endian.little);
      offset += 2;
    }
  }

  return bytes.buffer.asUint8List();
}

void _writeAscii(ByteData bytes, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    bytes.setUint8(offset + index, value.codeUnitAt(index));
  }
}

class _ToneSegment {
  final double frequency;
  final int durationMs;
  final double amplitude;

  const _ToneSegment({
    required this.frequency,
    required this.durationMs,
    required this.amplitude,
  });

  const _ToneSegment.silence({
    required this.durationMs,
  })  : frequency = 0,
        amplitude = 0;
}
