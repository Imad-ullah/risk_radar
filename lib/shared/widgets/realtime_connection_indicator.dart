import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riskradar/services/providers/hazard_provider.dart';
import 'package:riskradar/services/providers/hse_task_provider.dart';
import 'package:riskradar/services/providers/realtime_connection_provider.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/shared/theme/app_colors.dart';

class RealtimeConnectionIndicator extends ConsumerWidget {
  const RealtimeConnectionIndicator({super.key});

  static const double _indicatorSize = 10;
  static const double _containerSize = 32;
  static const Duration _animationDuration = Duration(milliseconds: 250);
  static const String _connectedLabel = 'Realtime connected';
  static const String _connectingLabel = 'Realtime connecting';
  static const String _errorLabel = 'Realtime connection error';
  static const String _disconnectedLabel = 'Realtime disconnected';
  static const String _hseWorkerRole = 'hse_worker';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _keepRealtimeProviderAlive(ref);
    final RealtimeConnectionStatus status = ref.watch(
      realtimeConnectionProvider,
    );
    final Color color = _colorForStatus(status);
    final String label = _labelForStatus(status);

    return Tooltip(
      message: label,
      child: SizedBox(
        width: _containerSize,
        height: _containerSize,
        child: Center(
          child: AnimatedContainer(
            duration: _animationDuration,
            width: _indicatorSize,
            height: _indicatorSize,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _keepRealtimeProviderAlive(WidgetRef ref) {
    final String? role = AuthRepository().getRole();
    if (role == _hseWorkerRole) {
      ref.watch(hseTaskProvider);
      return;
    }

    ref.watch(hazardProvider);
  }

  Color _colorForStatus(RealtimeConnectionStatus status) {
    switch (status) {
      case RealtimeConnectionStatus.connected:
        return Colors.green.shade400;
      case RealtimeConnectionStatus.connecting:
        return AppColors.accentGold;
      case RealtimeConnectionStatus.error:
        return Colors.red.shade300;
      case RealtimeConnectionStatus.disconnected:
        return Colors.grey.shade400;
    }
  }

  String _labelForStatus(RealtimeConnectionStatus status) {
    switch (status) {
      case RealtimeConnectionStatus.connected:
        return _connectedLabel;
      case RealtimeConnectionStatus.connecting:
        return _connectingLabel;
      case RealtimeConnectionStatus.error:
        return _errorLabel;
      case RealtimeConnectionStatus.disconnected:
        return _disconnectedLabel;
    }
  }
}
