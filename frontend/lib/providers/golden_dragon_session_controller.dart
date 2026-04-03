import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/golden_dragon_model.dart';
import '../services/golden_dragon_service.dart';
import '../services/socket_service.dart';

class GoldenDragonSessionController extends ChangeNotifier {
  GoldenDragonSessionController({
    required String roomId,
    required String? currentUserId,
  })  : _roomId = roomId,
        _currentUserId = currentUserId {
    _dragonSubscription =
        SocketService.dragonPacketStream.listen(_handleDragonSocketEvent);
    _resyncSubscription = SocketService.resyncStream.listen((_) {
      unawaited(ensureEventState(force: true));
    });
    _startClock();
  }

  final String _roomId;
  final String? _currentUserId;

  StreamSubscription<Map<String, dynamic>>? _dragonSubscription;
  StreamSubscription<Map<String, dynamic>>? _resyncSubscription;
  Timer? _clockTimer;

  GoldenDragonLiveEvent? _activeEvent;
  GoldenDragonLeaderboard? _leaderboard;
  GoldenDragonEventResult? _result;
  GoldenDragonTapAck? _lastTapAck;
  bool _isLoading = false;
  bool _isFetchingResult = false;
  String? _errorMessage;
  int _clockRevision = 0;
  int _tapSequence = 0;
  int _myAcceptedTapCount = 0;
  String _lastKnownEventId = '';

  String get roomId => _roomId;
  String? get currentUserId => _currentUserId;
  GoldenDragonLiveEvent? get activeEvent => _activeEvent;
  GoldenDragonLeaderboard? get leaderboard => _leaderboard;
  GoldenDragonEventResult? get result => _result;
  GoldenDragonTapAck? get lastTapAck => _lastTapAck;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get clockRevision => _clockRevision;
  int get myAcceptedTapCount => _myAcceptedTapCount;
  String get lastKnownEventId => _lastKnownEventId;

  bool get hasVisibleEvent => _activeEvent != null || _result != null;
  bool get isTapEnabled =>
      _activeEvent?.tapWindowOpen == true && _result == null;
  bool get isWaitingForResult =>
      _activeEvent != null &&
      !(_activeEvent?.tapWindowOpen ?? false) &&
      _result == null;

  int get remainingMs {
    if (_leaderboard != null &&
        _leaderboard!.eventId == _activeEvent?.eventId &&
        _leaderboard!.countdownMs >= 0) {
      return _leaderboard!.countdownMs;
    }
    return _activeEvent?.remainingMs ?? 0;
  }

  int get participantCount =>
      _leaderboard?.totalParticipants ??
      _result?.totalParticipants ??
      _activeEvent?.totalValidClaimants ??
      0;

  List<GoldenDragonClaimParticipant> get topClaimants {
    if (_result != null) {
      return _result!.winners;
    }
    return _leaderboard?.topClaimants ?? const <GoldenDragonClaimParticipant>[];
  }

  GoldenDragonClaimParticipant? get myFinalClaim => _result?.myClaim;

  Future<void> ensureEventState({bool force = false}) async {
    if (_isLoading && !force) return;

    _isLoading = true;
    _clearError(notify: false);
    notifyListeners();
    try {
      final payload = await GoldenDragonService.getActiveEvent(_roomId);
      if (payload.active && payload.event != null) {
        _activeEvent = payload.event;
        _leaderboard = null;
        _result = null;
        _lastKnownEventId = payload.event!.eventId;
        _myAcceptedTapCount = payload.myClaim?.acceptedTapCount ?? 0;
        _lastTapAck = null;
      } else {
        _activeEvent = null;
        _leaderboard = null;
        if (_lastKnownEventId.isNotEmpty) {
          await fetchResult(force: true);
        } else {
          _result = null;
        }
      }
    } catch (error) {
      _setError(
          _normalizeError(error, fallback: 'Could not load Golden Dragon'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void attachActivatedEvent(GoldenDragonLiveEvent event) {
    _activeEvent = event;
    _leaderboard = null;
    _result = null;
    _lastTapAck = null;
    _myAcceptedTapCount = 0;
    _lastKnownEventId = event.eventId;
    notifyListeners();
  }

  void sendTap() {
    final event = _activeEvent;
    if (event == null || !isTapEnabled) {
      return;
    }

    _tapSequence += 1;
    SocketService.sendDragonTap(
      roomId: _roomId,
      eventId: event.eventId,
      seq: _tapSequence,
    );
  }

  Future<void> fetchResult({bool force = false}) async {
    final eventId = _lastKnownEventId.isNotEmpty
        ? _lastKnownEventId
        : _activeEvent?.eventId ?? '';
    if (eventId.isEmpty) return;
    if (_isFetchingResult && !force) return;

    _isFetchingResult = true;
    try {
      final result = await GoldenDragonService.getEventResult(
        roomId: _roomId,
        eventId: eventId,
      );
      _result = result;
      _activeEvent = null;
      _leaderboard = null;
      _myAcceptedTapCount =
          result.myClaim?.acceptedTapCount ?? _myAcceptedTapCount;
      notifyListeners();
    } catch (_) {
      // silent; live socket path or reconcile will retry
    } finally {
      _isFetchingResult = false;
    }
  }

  void dismissResult() {
    if (_result == null) return;
    _result = null;
    notifyListeners();
  }

  void clearError() => _clearError();

  void _handleDragonSocketEvent(Map<String, dynamic> data) {
    final eventType = data['_eventType']?.toString() ?? '';
    final eventRoomId = data['roomId']?.toString() ?? '';
    final eventId = data['eventId']?.toString() ?? '';

    switch (eventType) {
      case 'dragon_created':
        if (eventRoomId != _roomId) return;
        final event = GoldenDragonLiveEvent.fromJson(data);
        _activeEvent = event;
        _leaderboard = null;
        _result = null;
        _lastTapAck = null;
        _myAcceptedTapCount = 0;
        _lastKnownEventId = event.eventId;
        notifyListeners();
        return;
      case 'dragon_leaderboard':
        if (eventRoomId != _roomId) return;
        _leaderboard = GoldenDragonLeaderboard.fromJson(data);
        if (_activeEvent == null || _activeEvent!.eventId == eventId) {
          _lastKnownEventId = eventId;
        }
        notifyListeners();
        return;
      case 'dragon_closing':
        if (eventRoomId != _roomId) return;
        notifyListeners();
        return;
      case 'dragon_result':
        if (eventRoomId != _roomId) return;
        final result = GoldenDragonEventResult.fromJson(data);
        _result = result;
        _activeEvent = null;
        _leaderboard = null;
        _lastKnownEventId = result.eventId;
        _myAcceptedTapCount =
            result.myClaim?.acceptedTapCount ?? _myAcceptedTapCount;
        notifyListeners();
        return;
      case 'dragon_tap_ack':
        if (eventId.isEmpty || eventId != _lastKnownEventId) return;
        final ack = GoldenDragonTapAck.fromJson(data);
        _lastTapAck = ack;
        if (ack.tapCounted) {
          _myAcceptedTapCount = ack.currentCountedTaps;
        }
        notifyListeners();
        return;
      default:
        return;
    }
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_activeEvent == null) return;
      _clockRevision += 1;
      if (_activeEvent!.remainingMs <= 0 && _result == null) {
        unawaited(fetchResult());
      }
      notifyListeners();
    });
  }

  void _clearError({bool notify = true}) {
    if (_errorMessage == null) return;
    _errorMessage = null;
    if (notify) notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  String _normalizeError(Object error, {required String fallback}) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    return message.isEmpty ? fallback : message;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _dragonSubscription?.cancel();
    _resyncSubscription?.cancel();
    super.dispose();
  }
}
