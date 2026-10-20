import 'alert_rules.dart';

class NotificationService {
  final List<LocalAlert> sentAlerts = [];

  Future<void> initialize() async {}

  Future<void> showLocalAlert(LocalAlert alert) async {
    if (sentAlerts.any((a) => a.dedupKey == alert.dedupKey)) return;
    sentAlerts.add(alert);
  }
}
