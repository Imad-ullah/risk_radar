import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/providers/realtime_connection_provider.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/models/hazard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final hseTaskProvider =
    AsyncNotifierProvider.autoDispose<HseTaskNotifier, List<Hazard>>(
  HseTaskNotifier.new,
);

class HseTaskNotifier extends AsyncNotifier<List<Hazard>>
    with WidgetsBindingObserver {
  HseTaskNotifier();

  static const String _channelName = 'riskradar-hse-task-provider';
  static const String _assignHazardsTable = 'assign_hazards';
  static const String _assignedToColumn = 'assigned_to';
  static const String _hseWorkerRole = 'hse_worker';
  static const String _publicSchema = 'public';
  static const String _subscriptionErrorMessage =
      'HSE task realtime subscription failed';

  final HazardRepository _hazardRepository = HazardRepository();
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _assignHazardsChannel;
  bool _isDisposed = false;

  @override
  Future<List<Hazard>> build() async {
    _isDisposed = false;
    WidgetsBinding.instance.addObserver(this);
    _subscribeToRealtimeChanges();
    ref.onDispose(() {
      _isDisposed = true;
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_unsubscribeFromRealtimeChanges());
    });
    return _loadTasks();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_canUseRef) {
      return;
    }

    _subscribeToRealtimeChanges();
    unawaited(refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (!_canUseRef) {
      return;
    }

    if (!silent) {
      state = const AsyncValue<List<Hazard>>.loading();
    }

    try {
      final List<Hazard> tasks = await _loadTasks();
      if (!_canUseRef) {
        return;
      }
      state = AsyncValue<List<Hazard>>.data(tasks);
    } catch (e, s) {
      if (!_canUseRef) {
        return;
      }
      state = AsyncValue<List<Hazard>>.error(e, s);
    }
  }

  Future<List<Hazard>> _loadTasks() async {
    final rows = await _hazardRepository.fetchActiveHazardsForCurrentUser(
      role: _hseWorkerRole,
    );
    return rows.map(Hazard.fromMap).toList(growable: false);
  }

  void _subscribeToRealtimeChanges() {
    if (!_canUseRef) {
      return;
    }

    final RealtimeConnectionNotifier connectionNotifier =
        ref.read(realtimeConnectionProvider.notifier);
    final String? userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      connectionNotifier.markDisconnected();
      return;
    }

    connectionNotifier.markConnecting();

    unawaited(_unsubscribeFromRealtimeChanges().then((_) {
      if (!_canUseRef) {
        return;
      }

      _assignHazardsChannel = _supabase
          .channel(_channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: _publicSchema,
            table: _assignHazardsTable,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: _assignedToColumn,
              value: userId,
            ),
            callback: (PostgresChangePayload payload) {
              if (!_canUseRef) {
                return;
              }
              unawaited(refresh(silent: true));
            },
          )
          .subscribe(_handleRealtimeStatus);
    }));
  }

  void _handleRealtimeStatus(
    RealtimeSubscribeStatus status, [
    Object? error,
  ]) {
    if (!_canUseRef) {
      return;
    }

    final RealtimeConnectionNotifier connectionNotifier =
        ref.read(realtimeConnectionProvider.notifier);

    if (status == RealtimeSubscribeStatus.subscribed) {
      connectionNotifier.markConnected();
      return;
    }

    if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      LoggerService.error(_subscriptionErrorMessage, error);
      connectionNotifier.markError();
      return;
    }

    if (status == RealtimeSubscribeStatus.closed) {
      connectionNotifier.markDisconnected();
    }
  }

  Future<void> _unsubscribeFromRealtimeChanges() async {
    final RealtimeChannel? channel = _assignHazardsChannel;
    _assignHazardsChannel = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  bool get _canUseRef => !_isDisposed && ref.mounted;
}
