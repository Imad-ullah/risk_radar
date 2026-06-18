import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'logger_service.dart';

class ConnectivityService {
  ConnectivityService._() {
    _startMonitoring();
  }

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _onlineController =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = true;

  Stream<bool> get isOnlineStream => _onlineController.stream;

  bool get isOnline => _isOnline;

  Future<void> refresh() async {
    try {
      final List<ConnectivityResult> results = await _connectivity
          .checkConnectivity();
      _setOnline(_hasNetwork(results));
    } catch (e, s) {
      LoggerService.error('Failed to check connectivity state', e, s);
      _setOnline(false);
    }
  }

  void _startMonitoring() {
    unawaited(refresh());
    _subscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _setOnline(_hasNetwork(results));
      },
      onError: (Object error, StackTrace stackTrace) {
        LoggerService.error('Connectivity stream failed', error, stackTrace);
        _setOnline(false);
      },
    );
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }

  void _setOnline(bool value) {
    if (_isOnline == value) {
      return;
    }
    _isOnline = value;
    if (!_onlineController.isClosed) {
      _onlineController.add(value);
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _onlineController.close();
  }
}
