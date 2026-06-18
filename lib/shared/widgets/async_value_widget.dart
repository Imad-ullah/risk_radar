import 'package:flutter/material.dart';
import 'package:riskradar/utils/responsive.dart';
import 'package:riskradar/shared/widgets/error_retry_widget.dart';
import 'package:riskradar/shared/widgets/risk_radar_loader.dart';

typedef AsyncDataBuilder<T> = Widget Function(BuildContext context, T value);

sealed class RiskRadarAsyncValue<T> {
  const RiskRadarAsyncValue();

  const factory RiskRadarAsyncValue.loading() = RiskRadarAsyncLoading<T>;

  const factory RiskRadarAsyncValue.data(T value) = RiskRadarAsyncData<T>;

  const factory RiskRadarAsyncValue.error(
    Object error, [
    StackTrace? stackTrace,
  ]) = RiskRadarAsyncError<T>;
}

class RiskRadarAsyncLoading<T> extends RiskRadarAsyncValue<T> {
  const RiskRadarAsyncLoading();
}

class RiskRadarAsyncData<T> extends RiskRadarAsyncValue<T> {
  const RiskRadarAsyncData(this.value);

  final T value;
}

class RiskRadarAsyncError<T> extends RiskRadarAsyncValue<T> {
  const RiskRadarAsyncError(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}

class AsyncValueWidget<T> extends StatelessWidget {
  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.onRetry,
    this.loadingMessage,
  });

  final RiskRadarAsyncValue<T> value;
  final AsyncDataBuilder<T> data;
  final VoidCallback? onRetry;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    return switch (value) {
      RiskRadarAsyncLoading<T>() => _LoadingState(message: loadingMessage),
      RiskRadarAsyncData<T>(value: final T result) => data(context, result),
      RiskRadarAsyncError<T>(error: final Object error) => ErrorRetryWidget(
        message: error.toString(),
        onRetry: onRetry,
      ),
    };
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    R.init(context);
    if (message == null || message!.isEmpty) {
      return RiskRadarLoader();
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RiskRadarLoader(),
          SizedBox(height: R.blockV * 2),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: R.blockH * 3.25,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
