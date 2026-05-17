import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riskradar/hse_worker/screens/hse_worker_hazard_notifier.dart'
    as hse_notifications;
import 'package:riskradar/officers/notifications/officer_hazard_notifier.dart'
    as officer_notifications;
import 'package:riskradar/services/repositories/auth_repository.dart';
import 'package:riskradar/workers/settings/worker_hazard_notifier.dart'
    as worker_notifications;

final notificationCountProvider = StreamProvider.autoDispose<int>((Ref ref) {
  final StreamController<int> controller = StreamController<int>.broadcast();
  final String? role = AuthRepository().getRole();
  final ChangeNotifier? notifier = _notifierForRole(role);

  if (notifier == null) {
    controller.add(0);
    ref.onDispose(controller.close);
    return controller.stream;
  }

  void publishCount() {
    if (!controller.isClosed) {
      controller.add(_countForRole(role));
    }
  }

  publishCount();
  notifier.addListener(publishCount);

  ref.onDispose(() {
    notifier.removeListener(publishCount);
    controller.close();
  });

  return controller.stream;
});

ChangeNotifier? _notifierForRole(String? role) {
  switch (role) {
    case 'officer':
      return officer_notifications.officerHazardNotifier;
    case 'worker':
      return worker_notifications.workerHazardNotifier;
    case 'hse_worker':
      return hse_notifications.workerHazardNotifier;
    default:
      return null;
  }
}

int _countForRole(String? role) {
  switch (role) {
    case 'officer':
      return officer_notifications.officerHazardNotifier.unreadCount;
    case 'worker':
      return worker_notifications.workerHazardNotifier.unreadCount;
    case 'hse_worker':
      return hse_notifications.workerHazardNotifier.unreadCount;
    default:
      return 0;
  }
}
