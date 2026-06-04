import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riskradar/services/logger_service.dart';
import 'package:riskradar/services/connectivity_service.dart';
import 'package:riskradar/services/providers/realtime_connection_provider.dart';
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/services/repositories/hazard_repository.dart';
import 'package:riskradar/shared/models/hazard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final hazardProvider =
    AsyncNotifierProvider.autoDispose<HazardNotifier, List<Hazard>>(
      HazardNotifier.new,
    );

class HazardNotifier extends AsyncNotifier<List<Hazard>>
    with WidgetsBindingObserver {
  HazardNotifier();

  static const Duration _refreshInterval = Duration(seconds: 45);
  static const String _hazardsChannelName = 'riskradar-hazards-provider';
  static const String _assignHazardsChannelName =
      'riskradar-assign-hazards-provider';
  static const String _hazardsTable = 'hazards';
  static const String _assignHazardsTable = 'assign_hazards';
  static const String _publicSchema = 'public';
  static const String _subscriptionErrorMessage =
      'Hazard realtime subscription failed';

  final AuthRepository _authRepository = AuthRepository();
  final HazardRepository _hazardRepository = HazardRepository();
  final SupabaseClient _supabase = Supabase.instance.client;
  Timer? _refreshTimer;
  RealtimeChannel? _hazardsChannel;
  RealtimeChannel? _assignHazardsChannel;
  bool _isDisposed = false;

  @override
  Future<List<Hazard>> build() async {
    _isDisposed = false;
    WidgetsBinding.instance.addObserver(this);
    _subscribeToRealtimeChanges();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(refresh(silent: true));
    });
    ref.onDispose(() {
      _isDisposed = true;
      WidgetsBinding.instance.removeObserver(this);
      _refreshTimer?.cancel();
      unawaited(_unsubscribeFromRealtimeChanges());
    });
    return _loadHazards();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_canUseRef) {
      return;
    }

    _subscribeToRealtimeChanges();
    unawaited(refresh(silent: true));
  }

  Future<void> refresh({bool silent = false, bool bypassCache = false}) async {
    if (!_canUseRef) {
      return;
    }

    if (!silent) {
      state = const AsyncValue<List<Hazard>>.loading();
    }

    try {
      if (bypassCache) {
        await ConnectivityService.instance.refresh();
      }
      final bool liveOnly =
          bypassCache && ConnectivityService.instance.isOnline;
      final List<Hazard> hazards = await _loadHazards(
        allowCacheFallback: !liveOnly,
      );
      if (!_canUseRef) {
        return;
      }
      state = AsyncValue<List<Hazard>>.data(hazards);
    } catch (e, s) {
      if (!_canUseRef) {
        return;
      }
      state = AsyncValue<List<Hazard>>.error(e, s);
    }
  }

  Future<List<Hazard>> _loadHazards({bool allowCacheFallback = true}) async {
    final String? role = _authRepository.getRole();
    if (role == null) {
      final List<Map<String, dynamic>> cachedRows = await _hazardRepository
          .getCachedActiveHazardsForRole(role);
      return _toHazards(cachedRows);
    }

    final List<Map<String, dynamic>> freshRows = await _hazardRepository
        .fetchActiveHazardsForCurrentUser(
          role: role,
          allowCacheFallback: allowCacheFallback,
        );
    return _toHazards(freshRows);
  }

  List<Hazard> _toHazards(List<Map<String, dynamic>> rows) {
    return rows
        .map((Map<String, dynamic> row) => Hazard.fromMap(row))
        .toList(growable: false);
  }

  void _subscribeToRealtimeChanges() {
    if (!_canUseRef) {
      return;
    }

    final RealtimeConnectionNotifier connectionNotifier = ref.read(
      realtimeConnectionProvider.notifier,
    );
    connectionNotifier.markConnecting();

    unawaited(
      _unsubscribeFromRealtimeChanges().then((_) {
        if (!_canUseRef) {
          return;
        }

        _hazardsChannel = _buildChannel(
          channelName: _hazardsChannelName,
          tableName: _hazardsTable,
        );
        _assignHazardsChannel = _buildChannel(
          channelName: _assignHazardsChannelName,
          tableName: _assignHazardsTable,
        );
      }),
    );
  }

  RealtimeChannel _buildChannel({
    required String channelName,
    required String tableName,
  }) {
    return _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: _publicSchema,
          table: tableName,
          callback: (PostgresChangePayload payload) {
            if (!_canUseRef) {
              return;
            }
            unawaited(refresh(silent: true));
          },
        )
        .subscribe(_handleRealtimeStatus);
  }

  void _handleRealtimeStatus(RealtimeSubscribeStatus status, [Object? error]) {
    if (!_canUseRef) {
      return;
    }

    final RealtimeConnectionNotifier connectionNotifier = ref.read(
      realtimeConnectionProvider.notifier,
    );

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
    final List<RealtimeChannel> channels = <RealtimeChannel>[
      ?_hazardsChannel,
      ?_assignHazardsChannel,
    ];
    _hazardsChannel = null;
    _assignHazardsChannel = null;

    for (final RealtimeChannel channel in channels) {
      await channel.unsubscribe();
    }
  }

  bool get _canUseRef => !_isDisposed && ref.mounted;
}
