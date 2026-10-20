import '../db/app_database.dart';
import '../notifications/alert_rules.dart';
import '../notifications/notification_service.dart';
import 'sync_engine.dart';

class BackgroundTasks {
  static const syncTaskName = 'com.duowallet.app.backgroundSync';

  static Future<void> runPeriodicSync({
    required AppDatabase db,
    required SyncEngine syncEngine,
    required NotificationService notifications,
    required String currentUserId,
  }) async {
    await syncEngine.syncNow();
    final alerts = evaluateAlertRules(
      db: db,
      meId: currentUserId,
      now: DateTime.now(),
    );
    for (final alert in alerts) {
      await notifications.showLocalAlert(alert);
    }
  }
}
