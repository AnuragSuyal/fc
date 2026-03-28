// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class RecordedVoiceNote {
  final XFile file;
  final Duration duration;
  final String mimeType;

  const RecordedVoiceNote({
    required this.file,
    required this.duration,
    required this.mimeType,
  });
}

class ChatVoiceNoteRecorder {
  static const html.EventStreamProvider<html.BlobEvent> _dataAvailableProvider =
      html.EventStreamProvider<html.BlobEvent>('dataavailable');
  static const html.EventStreamProvider<html.Event> _stopProvider =
      html.EventStreamProvider<html.Event>('stop');
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final List<html.Blob> _chunks = <html.Blob>[];

  html.MediaRecorder? _recorder;
  html.MediaStream? _stream;
  Timer? _ticker;
  DateTime? _startedAt;
  String _mimeType = 'audio/webm';

  bool get isRecording => _recorder?.state == 'recording';
  bool get supportsPressAndHold => true;
  Stream<Duration> get durationStream => _durationController.stream;

  Future<bool> start() async {
    if (isRecording) return true;

    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      return false;
    }

    try {
      _chunks.clear();
      _mimeType = _pickMimeType();
      _stream = await mediaDevices.getUserMedia(<String, dynamic>{
        'audio': true,
      });

      final recorderOptions = <String, dynamic>{};
      if (_mimeType.isNotEmpty) {
        recorderOptions['mimeType'] = _mimeType;
      }

      final recorder = recorderOptions.isEmpty
          ? html.MediaRecorder(_stream!)
          : html.MediaRecorder(_stream!, recorderOptions);

      _dataAvailableProvider.forTarget(recorder).listen((event) {
        final data = event.data;
        if (data != null && data.size > 0) {
          _chunks.add(data);
        }
      });

      _recorder = recorder;
      _startedAt = DateTime.now();
      _durationController.add(Duration.zero);
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_startedAt == null) return;
        _durationController.add(DateTime.now().difference(_startedAt!));
      });

      recorder.start(200);
      return true;
    } catch (_) {
      await cancel();
      return false;
    }
  }

  Future<RecordedVoiceNote?> stop() => _finishRecording(discard: false);

  Future<void> cancel() async {
    await _finishRecording(discard: true);
  }

  Future<RecordedVoiceNote?> _finishRecording({
    required bool discard,
  }) async {
    final recorder = _recorder;
    if (recorder == null) {
      _teardown();
      return null;
    }

    if (recorder.state == 'inactive') {
      _teardown();
      return null;
    }

    final duration = _startedAt == null
        ? Duration.zero
        : DateTime.now().difference(_startedAt!);
    final completer = Completer<RecordedVoiceNote?>();

    late StreamSubscription<html.Event> stopSubscription;
    stopSubscription = _stopProvider.forTarget(recorder).listen((_) async {
      await stopSubscription.cancel();

      try {
        if (discard || _chunks.isEmpty) {
          completer.complete(null);
          return;
        }

        final blob = html.Blob(_chunks, _mimeType);
        final bytes = await _blobToBytes(blob);
        if (bytes.isEmpty) {
          completer.complete(null);
          return;
        }

        final extension = _extensionForMime(_mimeType);
        completer.complete(
          RecordedVoiceNote(
            file: XFile.fromData(
              bytes,
              name:
                  'voice-note-${DateTime.now().millisecondsSinceEpoch}.$extension',
              mimeType: _mimeType,
            ),
            duration: duration,
            mimeType: _mimeType,
          ),
        );
      } finally {
        _teardown();
      }
    });

    recorder.stop();
    return completer.future;
  }

  Future<Uint8List> _blobToBytes(html.Blob blob) {
    final completer = Completer<Uint8List>();
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(result.asUint8List());
        return;
      }
      if (result is Uint8List) {
        completer.complete(result);
        return;
      }
      completer.complete(Uint8List(0));
    });

    reader.readAsArrayBuffer(blob);
    return completer.future;
  }

  String _pickMimeType() {
    const candidates = <String>[
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
    ];

    for (final candidate in candidates) {
      try {
        if (html.MediaRecorder.isTypeSupported(candidate)) {
          return candidate;
        }
      } catch (_) {}
    }

    return 'audio/webm';
  }

  String _extensionForMime(String mimeType) {
    if (mimeType.contains('ogg')) {
      return 'ogg';
    }
    if (mimeType.contains('aac')) {
      return 'aac';
    }
    if (mimeType.contains('wav')) {
      return 'wav';
    }
    return 'webm';
  }

  void _teardown() {
    _ticker?.cancel();
    _ticker = null;
    _recorder = null;
    _startedAt = null;

    final stream = _stream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
    }
    _stream = null;
    _chunks.clear();
  }

  void dispose() {
    _ticker?.cancel();
    for (final track in _stream?.getTracks() ?? const <html.MediaStreamTrack>[]) {
      track.stop();
    }
    _stream = null;
    _recorder = null;
    _chunks.clear();
    _durationController.close();
  }
}
