import 'package:flutter/material.dart';
import 'package:riskradar/services/error_service.dart';
import 'package:riskradar/shared/widgets/error_retry_widget.dart';

class ErrorBoundary extends StatefulWidget {
  const ErrorBoundary({
    super.key,
    required this.child,
    this.onRetry,
  });

  final Widget child;
  final VoidCallback? onRetry;

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  ErrorWidgetBuilder? _previousBuilder;

  @override
  void initState() {
    super.initState();
    _previousBuilder = ErrorWidget.builder;
    ErrorWidget.builder = _buildErrorWidget;
  }

  @override
  void dispose() {
    if (_previousBuilder != null) {
      ErrorWidget.builder = _previousBuilder!;
    }
    super.dispose();
  }

  Widget _buildErrorWidget(FlutterErrorDetails details) {
    ErrorService.reportFlutterError(details);
    return ErrorRetryWidget(
      message: details.exceptionAsString(),
      onRetry: widget.onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
