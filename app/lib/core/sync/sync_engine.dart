import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';
import '../db/tables/tables.dart';

abstract class RemoteSyncAdapter {
  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows);
  Future<List<Map<String, dynamic>>> fetchChangedRows(
    String table,
    DateTime? since,
  );
}

class SyncEngine {
  final AppDatabase db;
  final RemoteSyncAdapter? remote;
  static const _uuid = Uuid();

  SyncEngine({required this.db, this.remote});

  /// Deterministic UUIDv5 for recurring transactions (`rule_id + due_date`)
  /// so server cron and offline phones merge into the exact same transaction row.
  static String deterministicRecurringTxnId(String ruleId, DateTime dueDate) {
    final dayIso = dueDate.toIso8601String().split('T').first;
    return _uuid.v5(Namespace.url.value, 'duo-wallet:recurring:$ruleId:$dayIso');
  }

  Future<int> pushOutbox() async {
    final pending = db.pendingOutbox;
    if (pending.isEmpty) return 0;
    if (remote != null) {
      final byTable = <String, List<Map<String, dynamic>>>{};
      for (final item in pending) {
        byTable.putIfAbsent(item.tableName, () => []).add(item.payload);
      }
      for (final entry in byTable.entries) {
        await remote!.upsertRows(entry.key, entry.value);
      }
    }
    db.clearOutboxIds(pending.map((e) => e.id));
    return pending.length;
  }

  Future<void> pullUpdates() async {
    if (remote == null) return;
    final since = db.lastPulledAt;
    final txns = await remote!.fetchChangedRows('transactions', since);
    for (final raw in txns) {
      db.saveTransaction(Txn.fromJson(raw), fromSync: true);
    }
    final accounts = await remote!.fetchChangedRows('accounts', since);
    for (final raw in accounts) {
      db.upsertAccount(Account.fromJson(raw), fromSync: true);
    }
    final settlements = await remote!.fetchChangedRows('settlements', since);
    for (final raw in settlements) {
      db.upsertSettlement(Settlement.fromJson(raw), fromSync: true);
    }
    db.lastPulledAt = DateTime.now();
  }

  Future<void> syncNow() async {
    await pushOutbox();
    await pullUpdates();
  }
}

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(db: ref.watch(appDatabaseProvider));
});
