import 'package:flutter/material.dart';
import '../../widgets/error_boundary.dart';

class WhiteboardScreen extends StatefulWidget {
  final String roomId;

  const WhiteboardScreen({super.key, required this.roomId});

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final List<DrawingPoint> _points = [];
  Color _currentColor = Colors.black;
  double _strokeWidth = 3.0;
  bool _isDrawing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whiteboard'),
        actions: [
          // Color picker
          PopupMenuButton<Color>(
            icon: const Icon(Icons.color_lens),
            onSelected: (color) => setState(() => _currentColor = color),
            itemBuilder: (context) => [
              const PopupMenuItem(value: Colors.black, child: Text('Black')),
              const PopupMenuItem(value: Colors.red, child: Text('Red')),
              const PopupMenuItem(value: Colors.blue, child: Text('Blue')),
              const PopupMenuItem(value: Colors.green, child: Text('Green')),
              const PopupMenuItem(value: Colors.orange, child: Text('Orange')),
              const PopupMenuItem(value: Colors.purple, child: Text('Purple')),
            ],
          ),

          // Stroke width
          PopupMenuButton<double>(
            icon: const Icon(Icons.line_weight),
            onSelected: (width) => setState(() => _strokeWidth = width),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 2.0, child: Text('Thin')),
              const PopupMenuItem(value: 4.0, child: Text('Medium')),
              const PopupMenuItem(value: 6.0, child: Text('Thick')),
            ],
          ),

          // Clear
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              setState(() => _points.clear());
              // TODO: Emit clear event
            },
          ),
        ],
      ),
      body: ErrorBoundary(
        child: GestureDetector(
          onPanStart: (details) {
            setState(() => _isDrawing = true);
          },
          onPanUpdate: (details) {
            if (!_isDrawing) return;

            setState(() {
              _points.add(DrawingPoint(
                details.localPosition,
                Paint()
                  ..color = _currentColor
                  ..strokeWidth = _strokeWidth
                  ..strokeCap = StrokeCap.round,
              ));
            });

            // TODO: Emit drawing point to room
          },
          onPanEnd: (details) {
            setState(() => _isDrawing = false);
          },
          child: Container(
            color: Colors.white,
            child: CustomPaint(
              painter: _WhiteboardPainter(_points),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _WhiteboardPainter extends CustomPainter {
  final List<DrawingPoint> points;

  _WhiteboardPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i].paint != null && points[i + 1].paint != null) {
        canvas.drawLine(
          points[i].point,
          points[i + 1].point,
          points[i].paint!,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DrawingPoint {
  final Offset point;
  final Paint? paint;

  DrawingPoint(this.point, [this.paint]);
}






