import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRemoteSyncAdapter implements RemoteSyncAdapter {
  final Map<String, List<Map<String, dynamic>>> pushedByTable = {};
  final Map<String, List<Map<String, dynamic>>> remoteRowsByTable = {};

  @override
  Future<void> upsertRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    pushedByTable.putIfAbsent(table, () => []).addAll(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedRows(
    String table,
    DateTime? since,
  ) async {
    return remoteRowsByTable[table] ?? const [];
  }
}

void main() {
  const sam = 'user-sam';
  const anna = 'user-anna';
  const hh = 'hh-default-001';
  final now = DateTime(2026, 10, 20);

  group('SyncEngine & Privacy Invariants', () {
    test('Offline transaction creation queues outbox entries and pushOutbox() clears them idempotently', () async {
      final db = AppDatabase(seedDemo: false);
      final remote = FakeRemoteSyncAdapter();
      final sync = SyncEngine(db: db, remote: remote);

      final txn = Txn(
        id: 'txn-offline-1',
        householdId: hh,
        kind: TxnKind.expense,
        scope: Scope.individual,
        visibility: VisibilityLevel.private,
        occurredOn: now,
        amountMinor: 350000,
        baseAmountMinor: 350000,
        paidBy: sam,
        paidFromCommon: false,
        accountId: 'acc-sam-bank',
        accountAmountMinor: 350000,
        createdBy: sam,
        createdAt: now,
        updatedAt: now,
        baseShares: const {sam: 350000},
      );

      db.saveTransaction(txn);
      expect(db.pendingOutbox.length, 1);
      expect(db.pendingOutbox.first.tableName, 'transactions');
      expect(db.pendingOutbox.first.recordId, 'txn-offline-1');
      expect(db.pendingOutbox.first.operation, 'upsert');

      final pushedCount1 = await sync.pushOutbox();
      expect(pushedCount1, 1);
      expect(db.pendingOutbox, isEmpty);
      expect(remote.pushedByTable['transactions']?.length, 1);

      // Idempotent re-push: nothing left in outbox
      final pushedCount2 = await sync.pushOutbox();
      expect(pushedCount2, 0);
    });

    test('Common-account expense forces Scope.together and VisibilityLevel.shared', () {
      final db = AppDatabase(seedDemo: false);

      // Attempt to save an individual/private expense paid from common account
      final saved = db.saveTransaction(
        Txn(
          id: 'txn-common-forced',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: now,
          amountMinor: 500000,
          baseAmountMinor: 500000,
          paidBy: sam,
          paidFromCommon: true,
          accountId: 'acc-common',
          accountAmountMinor: 500000,
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(saved.scope, Scope.together);
      expect(saved.visibility, VisibilityLevel.shared);
    });

    test('Scope change (Individual <-> Together) soft-deletes old ID and creates a brand-new UUID row', () {
      final db = AppDatabase(seedDemo: false);

      final initial = db.saveTransaction(
        Txn(
          id: 'txn-orig-private',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: now,
          amountMinor: 420000,
          baseAmountMinor: 420000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam-bank',
          accountAmountMinor: 420000,
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 420000},
        ),
      );
      expect(initial.id, 'txn-orig-private');
      expect(initial.scope, Scope.individual);
      expect(initial.visibility, VisibilityLevel.private);

      // Now change scope from Individual -> Together
      final toggled = db.saveTransaction(
        initial.copyWith(
          scope: Scope.together,
          baseShares: const {sam: 210000, anna: 210000},
        ),
      );

      // Must have a new UUID and shared visibility
      expect(toggled.id, isNot('txn-orig-private'));
      expect(toggled.scope, Scope.together);
      expect(toggled.visibility, VisibilityLevel.shared);

      // Active transactions list contains only the new row, not the soft-deleted old ID
      expect(db.transactions.map((t) => t.id), [toggled.id]);

      // Outbox contains soft_delete for old ID and upsert for new ID
      final ops = {
        for (final e in db.pendingOutbox) e.recordId: e.operation,
      };
      expect(ops['txn-orig-private'], 'soft_delete');
      expect(ops[toggled.id], 'upsert');
    });

    test('Deterministic recurring UUID (SyncEngine.deterministicRecurringTxnId) prevents duplicates', () {
      final due = DateTime(2026, 11, 5);
      final idServer = SyncEngine.deterministicRecurringTxnId('rule-netflix', due);
      final idPhoneA = SyncEngine.deterministicRecurringTxnId(
        'rule-netflix',
        DateTime(2026, 11, 5, 14, 30),
      );
      final idNextMonth = SyncEngine.deterministicRecurringTxnId(
        'rule-netflix',
        DateTime(2026, 12, 5),
      );

      expect(idServer, equals(idPhoneA));
      expect(idServer, isNot(equals(idNextMonth)));
    });

    test('Settlement postings adjust only the owner\'s account balance privately after confirmation', () {
      final db = AppDatabase(seedDemo: true);
      final initialSamBank = db.computeAccountBalanceMinor(
        'acc-sam-bank',
        currentUserId: sam,
      );

      // Pending settlement with private posting for Sam (-4 000 Ft)
      final pendingSettlement = Settlement(
        id: 'settle-1',
        householdId: hh,
        fromUser: sam,
        toUser: anna,
        amountMinor: 400000,
        baseAmountMinor: 400000,
        fromConfirmed: true,
        toConfirmed: false,
        createdBy: sam,
        updatedAt: now,
      );
      const samPosting = SettlementPosting(
        settlementId: 'settle-1',
        userId: sam,
        accountId: 'acc-sam-bank',
        amountMinor: -400000,
      );

      db.upsertSettlement(pendingSettlement, ownPosting: samPosting);

      // While pending, account balance is unchanged
      expect(
        db.computeAccountBalanceMinor('acc-sam-bank', currentUserId: sam),
        initialSamBank,
      );

      // Once confirmed by both, Sam's private account reflects the posting
      final confirmedSettlement = Settlement(
        id: 'settle-1',
        householdId: hh,
        fromUser: sam,
        toUser: anna,
        amountMinor: 400000,
        baseAmountMinor: 400000,
        fromConfirmed: true,
        toConfirmed: true,
        createdBy: sam,
        updatedAt: now,
      );
      db.upsertSettlement(confirmedSettlement);

      expect(
        db.computeAccountBalanceMinor('acc-sam-bank', currentUserId: sam),
        initialSamBank - 400000,
      );
      // Viewing as Anna does not apply Sam's private posting
      expect(
        db.computeAccountBalanceMinor('acc-sam-bank', currentUserId: anna),
        initialSamBank,
      );
    });
  });
}
