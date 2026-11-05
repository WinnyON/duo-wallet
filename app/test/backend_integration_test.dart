import 'dart:convert';
import 'dart:io';
import 'package:duo_wallet/core/auth/backend_session.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/money/currency.dart';
import 'package:duo_wallet/core/sync/supabase_adapter.dart';
import 'package:duo_wallet/core/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'backend_security_test.dart' show MemorySecureStore;

void main() {
  const file = String.fromEnvironment('SUPABASE_TEST_STATUS_FILE');
  test(
      'real Supabase adapter and secure-cache restart round trip all app record types',
      () async {
    final config =
        jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>;
    final url = config['API_URL'] as String;
    final public = (config['PUBLISHABLE_KEY'] ?? config['ANON_KEY']) as String;
    final adminKey = config['SERVICE_ROLE_KEY'] as String;
    final admin = SupabaseClient(url, adminKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final a = SupabaseClient(url, public,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final b = SupabaseClient(url, public,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final id = const Uuid().v4();
    final password = 'Duo!aA9-${const Uuid().v4()}';
    final emails = ['duo-sdk-$id-a@example.com', 'duo-sdk-$id-b@example.com'];
    final userIds = <String>[];
    final store = MemorySecureStore();
    BackendSession? backend;
    String? household;
    try {
      for (final email in emails) {
        final res = await admin.auth.admin.createUser(AdminUserAttributes(
            email: email, password: password, emailConfirm: true));
        userIds.add(res.user!.id);
      }
      await a.auth.signInWithPassword(email: emails[0], password: password);
      await b.auth.signInWithPassword(email: emails[1], password: password);
      backend = BackendSession(client: a, store: store, projectUrl: url);
      await backend.initialize();
      expect(backend.verified, isTrue);
      expect(backend.db.accounts, isEmpty);
      await backend.onboard(
          displayName: 'SDK A', householdName: 'SDK integration $id');
      household = backend.db.household!.id;
      await b.rpc('join_household', params: {
        'p_invite_code': backend.db.household!.inviteCode,
        'p_display_name': 'SDK B',
        'p_color': '#EC4899'
      });
      await backend.syncNow();
      expect(backend.partnerId, userIds[1]);
      final db = backend.db;
      final uid = userIds[0];
      final now = DateTime.now();
      final account = Account(
          id: const Uuid().v4(),
          householdId: household,
          name: 'SDK EUR account',
          type: AccountType.bank,
          ownership: AccountOwnership.personal,
          ownerId: uid,
          currency: CurrencyCode.eur,
          openingBalanceMinor: 100000,
          openingDate: now,
          updatedAt: now);
      db.upsertAccount(account);
      final category = Category(
          id: const Uuid().v4(),
          householdId: household,
          nameEn: 'SDK category',
          nameHu: 'SDK kategória',
          kind: 'expense',
          updatedAt: now);
      db.upsertCategory(category);
      final profile = db.findProfile(uid)!;
      db.upsertProfile(Profile.fromJson({
        ...profile.toJson(),
        'display_name': 'SDK renamed',
        'avatar_type': 'initials'
      }));
      final budget = Budget(
          id: const Uuid().v4(),
          householdId: household,
          scope: Scope.individual,
          ownerId: uid,
          categoryId: category.id,
          amountMinor: 900000,
          updatedAt: now);
      db.upsertBudget(budget);
      final goal = Goal(
          id: const Uuid().v4(),
          householdId: household,
          name: 'SDK goal',
          scope: 'personal',
          ownerId: uid,
          targetAmountMinor: 250000,
          savedAmountMinor: 2500,
          currency: CurrencyCode.eur,
          linkedAccountIds: [account.id],
          contributionsByUser: {uid: 2500},
          updatedAt: now);
      db.upsertGoal(goal);
      final rule = RecurringRule(
          id: const Uuid().v4(),
          householdId: household,
          title: 'SDK future bill',
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          amountMinor: 1234,
          currency: CurrencyCode.eur,
          accountId: account.id,
          categoryId: category.id,
          nextDueOn: DateTime(2099, 1, 31),
          autoCreate: false,
          createdBy: uid,
          updatedAt: now);
      db.upsertRecurringRule(rule);
      final txn = Txn(
          id: const Uuid().v4(),
          householdId: household,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: now,
          amountMinor: 1234,
          currency: CurrencyCode.eur,
          fxRateToBase: 395,
          baseAmountMinor: 487430,
          paidBy: uid,
          paidFromCommon: false,
          accountId: account.id,
          accountAmountMinor: 1234,
          categoryId: category.id,
          createdBy: uid,
          createdAt: now,
          updatedAt: now,
          shares: {uid: 1234},
          baseShares: {uid: 487430},
          tags: ['sdk']);
      db.saveTransaction(txn);
      final valuation = AccountValuation(
          id: const Uuid().v4(),
          accountId: account.id,
          valuedOn: now,
          valueMinor: 99000,
          createdAt: now);
      db.upsertValuation(valuation);
      final settlement = Settlement(
          id: const Uuid().v4(),
          householdId: household,
          fromUser: uid,
          toUser: userIds[1],
          amountMinor: 200,
          currency: CurrencyCode.eur,
          baseAmountMinor: 79000,
          fromConfirmed: true,
          createdBy: uid,
          updatedAt: now);
      db.upsertSettlement(settlement,
          ownPosting: SettlementPosting(
              settlementId: settlement.id,
              userId: uid,
              accountId: account.id,
              amountMinor: -200));
      await backend.syncNow();
      if (backend.error != null) {
        await SyncEngine(db: db, remote: SupabaseSyncAdapter(a)).syncNow();
      }
      expect(backend.error, isNull);
      expect(db.pendingOutbox, isEmpty);
      expect(db.findAccount(account.id)!.currency, CurrencyCode.eur);
      expect(db.findProfile(uid)!.displayName, 'SDK renamed');
      expect(db.transactions.singleWhere((e) => e.id == txn.id).shares,
          txn.shares);
      expect(db.budgets.single.amountMinor, budget.amountMinor);
      expect(db.goals.single.savedAmountMinor, 2500);
      expect(db.goals.single.linkedAccountIds, [account.id]);
      expect(db.recurringRules.single.nextDueOn, DateTime(2099, 1, 31));
      expect(db.valuations.single.valueMinor, 99000);
      expect(db.settlementPostings.single.amountMinor, -200);
      expect(db.activities.any((e) => e.eventType == 'settlement_proposed'),
          isTrue);
      expect(db.activities.any((e) => e.eventType == 'expense_added'), isFalse);
      final adapter = SupabaseSyncAdapter(a);
      final partnerAdapter = SupabaseSyncAdapter(b);
      await partnerAdapter.upsertRows('settlements', [
        {...settlement.toJson(), 'to_confirmed': true}
      ]);
      final confirmed =
          await a.from('settlements').select().eq('id', settlement.id).single();
      expect(confirmed['from_confirmed'], isTrue);
      expect(confirmed['to_confirmed'], isTrue);
      await expectLater(
          partnerAdapter.upsertRows('settlements', [
            {
              ...settlement.toJson(),
              'to_confirmed': true,
              'created_by': userIds[1]
            }
          ]),
          throwsA(isA<PostgrestException>()));

      final sharedTxn = {
        ...txn.toJson(),
        'id': const Uuid().v4(),
        'scope': 'together',
        'visibility': 'shared',
        'shares': {uid: 617, userIds[1]: 617},
        'base_shares': {uid: 243715, userIds[1]: 243715}
      };
      await adapter.upsertRows('transactions', [sharedTxn]);
      final editedTxn = {
        ...sharedTxn,
        'note': 'Edited by partner',
        'shares': {uid: 600, userIds[1]: 634},
        'base_shares': {uid: 237000, userIds[1]: 250430}
      };
      await partnerAdapter.upsertRows('transactions', [editedTxn]);
      final edited = await a
          .from('transactions')
          .select('*,transaction_shares(*)')
          .eq('id', sharedTxn['id'] as String)
          .single();
      expect(edited['note'], 'Edited by partner');
      expect(edited['created_by'], uid);
      expect(
          (edited['transaction_shares'] as List)
              .singleWhere((s) => s['user_id'] == userIds[1])['share_minor'],
          634);
      for (final key in ['created_by', 'paid_by', 'household_id']) {
        await expectLater(
            partnerAdapter.upsertRows('transactions', [
              {
                ...editedTxn,
                key: key == 'household_id' ? const Uuid().v4() : userIds[1]
              }
            ]),
            throwsA(isA<PostgrestException>()));
      }
      await expectLater(
          partnerAdapter.upsertRows('transactions', [
            {
              ...editedTxn,
              'note': 'Must roll back',
              'shares': {uid: 1}
            }
          ]),
          throwsA(isA<PostgrestException>()));
      expect(
          (await a
              .from('transactions')
              .select('note')
              .eq('id', sharedTxn['id'] as String)
              .single())['note'],
          'Edited by partner');
      final sharedRule = {
        ...rule.toJson(),
        'id': const Uuid().v4(),
        'scope': 'together',
        'visibility': 'shared'
      };
      await adapter.upsertRows('recurring_rules', [sharedRule]);
      await partnerAdapter.upsertRows('recurring_rules', [
        {...sharedRule, 'title': 'Partner updated bill'}
      ]);
      expect(
          (await a
              .from('recurring_rules')
              .select('title')
              .eq('id', sharedRule['id'] as String)
              .single())['title'],
          'Partner updated bill');
      await expectLater(
          partnerAdapter.upsertRows('recurring_rules', [
            {...sharedRule, 'created_by': userIds[1]}
          ]),
          throwsA(isA<PostgrestException>()));
      await adapter.uploadBackup(db.exportVisibleJson(meId: uid));
      final downloaded = await adapter.downloadBackup();
      expect((downloaded['accounts'] as List).any((e) => e['id'] == account.id),
          isTrue);
      await backend.flushLocal();
      expect(store.values.keys.any((k) => k.endsWith('.data.$uid')), isTrue);
      expect(
          store.values.values
              .any((v) => v.contains(a.auth.currentSession!.accessToken)),
          isFalse);
      db.softDeleteTransaction(txn.id);
      await backend.syncNow();
      expect(backend.error, isNull);
      await backend.signOut();
      expect(db.accounts, isEmpty);
      expect(backend.user, isNull);
      backend.dispose();
      backend = null;
      await a.auth.signInWithPassword(email: emails[0], password: password);
      backend = BackendSession(client: a, store: store, projectUrl: url);
      await backend.initialize();
      expect(backend.error, isNull);
      expect(backend.db.findAccount(account.id), isNotNull);
      expect(backend.db.transactions.any((e) => e.id == txn.id), isFalse);
      await a.storage.from('backups').remove(['$uid/latest.json']);
    } finally {
      backend?.dispose();
      if (household != null) {
        final txs = await admin
            .from('transactions')
            .select('id')
            .eq('household_id', household);
        final accounts = await admin
            .from('accounts')
            .select('id')
            .eq('household_id', household);
        final goals = await admin
            .from('goals')
            .select('id')
            .eq('household_id', household);
        final settlements = await admin
            .from('settlements')
            .select('id')
            .eq('household_id', household);
        await admin
            .from('transactions')
            .update({'deleted_at': DateTime.now().toIso8601String()}).eq(
                'household_id', household);
        for (final entry in [
          ('transaction_tags', 'transaction_id', txs),
          ('transaction_shares', 'transaction_id', txs),
          ('goal_accounts', 'goal_id', goals),
          ('goal_contributions', 'goal_id', goals),
          ('settlement_postings', 'settlement_id', settlements),
          ('account_valuations', 'account_id', accounts)
        ]) {
          final ids = entry.$3.map((e) => e['id'] as String).toList();
          if (ids.isNotEmpty) {
            await admin.from(entry.$1).delete().inFilter(entry.$2, ids);
          }
        }
        for (final table in [
          'activity',
          'transactions',
          'recurring_rules',
          'settlements',
          'budgets',
          'goals',
          'accounts',
          'categories',
          'tags'
        ]) {
          await admin.from(table).delete().eq('household_id', household);
        }
        await admin.from('profiles').delete().eq('household_id', household);
        await admin.from('households').delete().eq('id', household);
      }
      for (final uid in userIds) {
        await admin.auth.admin.deleteUser(uid);
      }
      await a.dispose();
      await b.dispose();
      await admin.dispose();
    }
  },
      skip: file.isEmpty
          ? 'Opt in with SUPABASE_TEST_STATUS_FILE to verify real Supabase services.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
