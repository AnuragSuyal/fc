import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/constants.dart';

class TimerScreen extends StatefulWidget {
  final String roomId;

  const TimerScreen({super.key, required this.roomId});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const int workDuration = 25 * 60; // 25 minutes
  static const int breakDuration = 5 * 60; // 5 minutes

  int _remainingSeconds = workDuration;
  bool _isRunning = false;
  bool _isWorkMode = true;
  Timer? _timer;

  int _workSessions = 0;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  void _setupListeners() {
    // TODO: Setup socket listeners for timer sync
  }

  void _startTimer() {
    if (_isRunning) return;

    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _switchMode();
        }
      });
    });

    // TODO: Emit socket event
  }

  void _pauseTimer() {
    setState(() => _isRunning = false);
    _timer?.cancel();
    // TODO: Emit socket event
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _isWorkMode ? workDuration : breakDuration;
    });
    // TODO: Emit socket event
  }

  void _switchMode() {
    _timer?.cancel();
    setState(() {
      _isWorkMode = !_isWorkMode;
      _remainingSeconds = _isWorkMode ? workDuration : breakDuration;
      _isRunning = false;

      if (!_isWorkMode) {
        _workSessions++;
      }
    });
    // TODO: Emit socket event
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Timer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Mode indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color:
                    _isWorkMode ? Colors.green.shade50 : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isWorkMode
                      ? Colors.green.shade200
                      : Colors.orange.shade200,
                ),
              ),
              child: Text(
                _isWorkMode ? 'FOCUS TIME' : 'BREAK TIME',
                style: TextStyle(
                  color: _isWorkMode
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Timer display
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isWorkMode
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : [Colors.orange.shade400, Colors.orange.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isWorkMode ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  _formatTime(_remainingSeconds),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 64,
                  icon: Icon(
                    _isRunning
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: AppColors.primaryBlue,
                  ),
                  onPressed: _isRunning ? _pauseTimer : _startTimer,
                ),
                const SizedBox(width: 20),
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.refresh),
                  onPressed: _resetTimer,
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Stats
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Text(
                    'Session Stats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat(
                        'Work Sessions',
                        '$_workSessions',
                        Icons.work,
                        Colors.green,
                      ),
                      _buildStat(
                        'Total Time',
                        '${(_workSessions * 25)}m',
                        Icons.timer,
                        Colors.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}






