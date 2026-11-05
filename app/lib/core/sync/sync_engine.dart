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

abstract class SnapshotSyncAdapter implements RemoteSyncAdapter {
  Future<Map<String, dynamic>> fetchSnapshot();
}

class SyncEngine {
  final AppDatabase db;
  final RemoteSyncAdapter? remote;
  final bool Function()? isCurrent;
  void _checkSession() {
    if (isCurrent != null && !isCurrent!()) throw StateError('Session changed');
  }

  static const _uuid = Uuid();

  SyncEngine({required this.db, this.remote, this.isCurrent});

  /// Deterministic UUIDv5 for recurring transactions (`rule_id + due_date`)
  /// so server cron and offline phones merge into the exact same transaction row.
  static String deterministicRecurringTxnId(String ruleId, DateTime dueDate) {
    final dayIso = dueDate.toIso8601String().split('T').first;
    return _uuid.v5(
        Namespace.url.value, 'duo-wallet:recurring:$ruleId:$dayIso');
  }

  Future<int> pushOutbox() async {
    _checkSession();
    final pending = db.pendingOutbox;
    if (pending.isEmpty) return 0;
    if (remote == null) return 0;
    const order = [
      'households',
      'profiles',
      'categories',
      'accounts',
      'budgets',
      'goals',
      'recurring_rules',
      'transactions',
      'settlements',
      'settlement_postings',
      'account_valuations',
      'activity'
    ];
    final sorted = [...pending]..sort((a, b) =>
        order.indexOf(a.tableName).compareTo(order.indexOf(b.tableName)));
    for (final item in sorted) {
      await remote!.upsertRows(item.tableName, [item.payload]);
      // Acknowledge only this exact queued version after the server accepted it.
      _checkSession();
      db.clearOutboxIds([item.id]);
    }
    return pending.length;
  }

  Future<void> pullUpdates() async {
    if (remote == null) return;
    if (remote is SnapshotSyncAdapter) {
      final data = await (remote as SnapshotSyncAdapter).fetchSnapshot();
      _checkSession();
      db.replaceRemoteSnapshot(data);
      db.lastPulledAt = DateTime.now();
      return;
    }
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
