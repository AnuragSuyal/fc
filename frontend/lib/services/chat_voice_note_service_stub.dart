import 'dart:async';

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
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();

  bool get isRecording => false;
  bool get supportsPressAndHold => false;
  Stream<Duration> get durationStream => _durationController.stream;

  Future<bool> start() async => false;

  Future<RecordedVoiceNote?> stop() async => null;

  Future<void> cancel() async {}

  void dispose() {
    _durationController.close();
  }
}
