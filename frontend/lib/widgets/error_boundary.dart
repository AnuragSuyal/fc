import 'package:flutter/material.dart';

class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget? fallback;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.fallback,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // In Flutter, errors in build methods are usually caught by the framework
    // and displayed using ErrorWidget.builder. We can locally override this
    // if we want to catch build errors within this subtree, but catching generic
    // async errors or exceptions might require different approaches like runZoned.
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.fallback ??
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong here limit damage to this component.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                    });
                  },
                  child: const Text('Try Again'),
                )
              ],
            ),
          );
    }

    return ErrorWidgetBuilder(
      builder: (context, details) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hasError) {
            setState(() {
              _hasError = true;
            });
          }
        });
      },
      child: widget.child,
    );
  }
}

class ErrorWidgetBuilder extends StatelessWidget {
  final Widget child;
  final void Function(BuildContext context, FlutterErrorDetails details)
      builder;

  const ErrorWidgetBuilder({
    super.key,
    required this.child,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    // Note: To properly isolate errors, you'd combine this with a custom ErrorWidget.builder globally,
    // or wrap specific risk prone areas using Builder and try/catch around their state updates.
    // For standard widget tree exceptions, ErrorWidget.builder is standard.
    final originalBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      builder(context, details);
      return const SizedBox.shrink();
    };

    // We render the child, and if it fails, ErrorWidget.builder catches it
    Widget result = child;

    // Restore the original builder synchronously immediately after building
    // Note: Due to Flutter's asynchronous build phases, this approach is simplified
    // for standard sync errors during this widget's specific build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ErrorWidget.builder = originalBuilder;
    });

    return result;
  }
}






