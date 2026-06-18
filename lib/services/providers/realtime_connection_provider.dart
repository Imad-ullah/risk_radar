import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RealtimeConnectionStatus { connecting, connected, disconnected, error }

final realtimeConnectionProvider =
    NotifierProvider<RealtimeConnectionNotifier, RealtimeConnectionStatus>(
      RealtimeConnectionNotifier.new,
    );

class RealtimeConnectionNotifier extends Notifier<RealtimeConnectionStatus> {
  @override
  RealtimeConnectionStatus build() {
    return RealtimeConnectionStatus.disconnected;
  }

  void markConnecting() {
    state = RealtimeConnectionStatus.connecting;
  }

  void markConnected() {
    state = RealtimeConnectionStatus.connected;
  }

  void markDisconnected() {
    state = RealtimeConnectionStatus.disconnected;
  }

  void markError() {
    state = RealtimeConnectionStatus.error;
  }
}
