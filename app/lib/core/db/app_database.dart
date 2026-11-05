import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/splits.dart';
import '../money/currency.dart';
import '../money/fx_service.dart';
import 'tables/tables.dart';

/// Offline-first local database & outbox store.
/// Mirrors visible Postgres rows (enforced by server RLS on sync) with no foreign key on `account_id`
/// so Together expenses paid from a partner's private account never fail referential checks.
class AppDatabase {
  final _uuid = const Uuid();
  final _changeController = StreamController<void>.broadcast();

  Household? _household;
  final Map<String, Profile> _profiles = {};
  final Map<String, Account> _accounts = {};
  final Map<String, Txn> _transactions = {};
  final Map<String, Category> _categories = {};
  final Map<String, Budget> _budgets = {};
  final Map<String, Settlement> _settlements = {};
  final Map<String, SettlementPosting> _settlementPostings = {};
  final Map<String, RecurringRule> _recurringRules = {};
  final Map<String, AccountValuation> _valuations = {};
  final Map<String, Goal> _goals = {};
  final Map<String, ActivityEvent> _activities = {};
  final List<OutboxEntry> _outbox = [];
  DateTime? lastPulledAt;

  final bool serverManagedActivity;

  AppDatabase({bool seedDemo = true, this.serverManagedActivity = false}) {
    if (seedDemo) _seedDefaultData();
  }

  Stream<void> get changes => _changeController.stream;

  void _notify() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  void _enqueueOutbox(
      String table, String id, String op, Map<String, dynamic> payload) {
    _outbox.removeWhere((e) => e.tableName == table && e.recordId == id);
    _outbox.add(
      OutboxEntry(
        id: _uuid.v4(),
        tableName: table,
        recordId: id,
        operation: op,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<OutboxEntry> get pendingOutbox => List.unmodifiable(_outbox);
  void clearOutboxIds(Iterable<String> ids) {
    final set = ids.toSet();
    _outbox.removeWhere((e) => set.contains(e.id));
  }

  Household? get household => _household;
  List<Profile> get profiles => _profiles.values.toList();
  List<Account> get accounts =>
      _accounts.values.where((a) => a.deletedAt == null).toList();
  List<Txn> get transactions =>
      _transactions.values.where((t) => t.deletedAt == null).toList()
        ..sort((a, b) => b.occurredOn.compareTo(a.occurredOn));
  List<Category> get categories =>
      _categories.values.where((c) => c.deletedAt == null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Category> get retiredCategories =>
      _categories.values.where((c) => c.deletedAt != null).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  List<Budget> get budgets =>
      _budgets.values.where((b) => b.deletedAt == null).toList();
  List<Settlement> get settlements =>
      _settlements.values.where((s) => s.deletedAt == null).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  List<SettlementPosting> get settlementPostings =>
      _settlementPostings.values.toList();
  List<RecurringRule> get recurringRules =>
      _recurringRules.values.where((r) => r.deletedAt == null).toList();
  List<AccountValuation> get valuations => _valuations.values.toList();
  List<Goal> get goals =>
      _goals.values.where((g) => g.deletedAt == null).toList();
  List<ActivityEvent> get activities => _activities.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Account? findAccount(String id) => _accounts[id];
  Category? findCategory(String id) => _categories[id];
  Profile? findProfile(String id) => _profiles[id];

  /// Computes live balance of [accountId] in its native currency minor units,
  /// including opening balance, expenses, income, transfers, and private settlement postings.
  int computeAccountBalanceMinor(String accountId, {String? currentUserId}) {
    final acc = _accounts[accountId];
    if (acc == null) return 0;

    if (acc.type == AccountType.investment) {
      final snaps = _valuations.values
          .where((v) => v.accountId == accountId)
          .toList()
        ..sort((a, b) => b.valuedOn.compareTo(a.valuedOn));
      if (snaps.isNotEmpty) return snaps.first.valueMinor;
    }

    var bal = acc.openingBalanceMinor;
    for (final t in transactions) {
      if (t.kind == TxnKind.expense && t.accountId == accountId) {
        bal -= t.accountAmountMinor;
      } else if (t.kind == TxnKind.income && t.accountId == accountId) {
        bal += t.accountAmountMinor;
      } else if (t.kind == TxnKind.transfer) {
        if (t.accountId == accountId) {
          bal -= t.accountAmountMinor;
        }
        if (t.toAccountId == accountId) {
          bal += (t.toAccountAmountMinor ?? t.accountAmountMinor);
        }
      }
    }
    for (final sp in _settlementPostings.values) {
      if (sp.accountId == accountId &&
          (currentUserId == null || sp.userId == currentUserId)) {
        final s = _settlements[sp.settlementId];
        if (s != null && s.isConfirmed) {
          bal += sp.amountMinor;
        }
      }
    }
    return bal;
  }

  void upsertHousehold(Household h, {bool fromSync = false}) {
    _household = h;
    if (!fromSync) _enqueueOutbox('households', h.id, 'upsert', h.toJson());
    _notify();
  }

  void upsertProfile(Profile p, {bool fromSync = false}) {
    _profiles[p.id] = p;
    if (!fromSync) _enqueueOutbox('profiles', p.id, 'upsert', p.toJson());
    _notify();
  }

  void upsertAccount(Account a, {bool fromSync = false}) {
    _accounts[a.id] = a;
    if (!fromSync) _enqueueOutbox('accounts', a.id, 'upsert', a.toJson());
    _notify();
  }

  void upsertCategory(Category c, {bool fromSync = false}) {
    _categories[c.id] = c;
    if (!fromSync) _enqueueOutbox('categories', c.id, 'upsert', c.toJson());
    _notify();
  }

  void upsertBudget(Budget b, {bool fromSync = false}) {
    _budgets[b.id] = b;
    if (!fromSync) _enqueueOutbox('budgets', b.id, 'upsert', b.toJson());
    _notify();
  }

  void upsertGoal(Goal g, {bool fromSync = false}) {
    _goals[g.id] = g;
    if (!fromSync) _enqueueOutbox('goals', g.id, 'upsert', g.toJson());
    _notify();
  }

  void upsertRecurringRule(RecurringRule r, {bool fromSync = false}) {
    _recurringRules[r.id] = r;
    if (!fromSync) {
      _enqueueOutbox('recurring_rules', r.id, 'upsert', r.toJson());
    }
    _notify();
  }

  void upsertValuation(AccountValuation v, {bool fromSync = false}) {
    _valuations[v.id] = v;
    if (!fromSync) {
      _enqueueOutbox('account_valuations', v.id, 'upsert', v.toJson());
    }
    _notify();
  }

  void upsertSettlement(
    Settlement s, {
    SettlementPosting? ownPosting,
    bool fromSync = false,
  }) {
    _settlements[s.id] = s;
    if (!fromSync) _enqueueOutbox('settlements', s.id, 'upsert', s.toJson());
    if (ownPosting != null) {
      final key = '${ownPosting.settlementId}_${ownPosting.userId}';
      _settlementPostings[key] = ownPosting;
      if (!fromSync) {
        _enqueueOutbox(
          'settlement_postings',
          key,
          'upsert',
          ownPosting.toJson(),
        );
      }
    }
    _notify();
  }

  void addActivity(ActivityEvent event, {bool fromSync = false}) {
    if (serverManagedActivity && !fromSync) return;
    _activities[event.id] = event;
    if (!fromSync) {
      _enqueueOutbox('activity', event.id, 'upsert', event.toJson());
    }
    _notify();
  }

  /// Inserts or updates a transaction, enforcing privacy rules:
  /// 1. Common-account expenses are ALWAYS forced to `Scope.together` and `VisibilityLevel.shared`.
  /// 2. Changing `scope` (Individual <-> Together) NEVER mutates in-place: it soft-deletes the old row
  ///    and creates a brand-new UUID row so private history never leaks via row updates.
  Txn saveTransaction(Txn draft, {bool fromSync = false}) {
    final effectiveScope = draft.paidFromCommon ? Scope.together : draft.scope;
    final effectiveVisibility = switch (draft.kind) {
      TxnKind.expense => effectiveScope == Scope.together
          ? VisibilityLevel.shared
          : VisibilityLevel.private,
      TxnKind.income ||
      TxnKind.transfer =>
        (draft.paidFromCommon || draft.isContribution)
            ? VisibilityLevel.shared
            : VisibilityLevel.private,
    };

    final existing = _transactions[draft.id];
    if (!fromSync && existing != null && existing.scope != effectiveScope) {
      // Scope changed: soft-delete existing and create a new UUID
      final tombstone = existing.copyWith(
        deletedAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      _transactions[existing.id] = tombstone;
      _enqueueOutbox(
        'transactions',
        existing.id,
        'soft_delete',
        tombstone.toJson(),
      );

      final replacement = draft.copyWith(
        id: _uuid.v4(),
        scope: effectiveScope,
        visibility: effectiveVisibility,
        updatedAt: DateTime.now(),
      );
      _transactions[replacement.id] = replacement;
      _enqueueOutbox(
        'transactions',
        replacement.id,
        'upsert',
        replacement.toJson(),
      );
      _notify();
      return replacement;
    }

    final saved = draft.copyWith(
      scope: effectiveScope,
      visibility: effectiveVisibility,
      updatedAt: DateTime.now(),
    );
    _transactions[saved.id] = saved;
    if (!fromSync) {
      _enqueueOutbox('transactions', saved.id, 'upsert', saved.toJson());
    }
    _notify();
    return saved;
  }

  void softDeleteTransaction(String id) {
    final existing = _transactions[id];
    if (existing == null) return;
    final deleted = existing.copyWith(
      deletedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _transactions[id] = deleted;
    _enqueueOutbox('transactions', id, 'soft_delete', deleted.toJson());
    _notify();
  }

  Map<String, dynamic> exportVisibleJson({String? meId}) {
    final visibleAccounts = accounts
        .where((a) => meId == null || a.isCommon || a.ownerId == meId)
        .toList();
    final accountIds = visibleAccounts.map((a) => a.id).toSet();
    return {
      'schema_version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'household': _household?.toJson(),
      'profiles': profiles.map((e) => e.toJson()).toList(),
      'accounts': visibleAccounts.map((e) => e.toJson()).toList(),
      'categories': _categories.values.map((e) => e.toJson()).toList(),
      'transactions': transactions
          .where((e) =>
              meId == null ||
              e.visibility == VisibilityLevel.shared ||
              e.createdBy == meId)
          .map((e) => e.toJson())
          .toList(),
      'budgets': budgets
          .where((e) =>
              meId == null || e.scope == Scope.together || e.ownerId == meId)
          .map((e) => e.toJson())
          .toList(),
      'settlements': settlements.map((e) => e.toJson()).toList(),
      'settlement_postings': settlementPostings
          .where((e) => meId == null || e.userId == meId)
          .map((e) => e.toJson())
          .toList(),
      'recurring_rules': recurringRules
          .where((e) =>
              meId == null ||
              e.visibility == VisibilityLevel.shared ||
              e.createdBy == meId)
          .map((e) => e.toJson())
          .toList(),
      'goals': goals
          .where((e) => meId == null || e.isShared || e.ownerId == meId)
          .map((e) => e.toJson())
          .toList(),
      'valuations': valuations
          .where((e) => accountIds.contains(e.accountId))
          .map((e) => e.toJson())
          .toList(),
      'activities': activities.map((e) => e.toJson()).toList(),
    };
  }

  /// Validates the whole backup before merging by ID. No live data changes on failure.
  void restoreFromJson(Map<String, dynamic> data,
      {String? meId, bool validateOnly = false, bool queueWrites = false}) {
    if (queueWrites && meId == null) {
      throw const FormatException('Authenticated owner required');
    }
    if ((data['schema_version'] != null && data['schema_version'] != 1) ||
        data['accounts'] is! List ||
        data['transactions'] is! List) {
      throw const FormatException('Unsupported backup');
    }
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) parse) {
      final value = data[key];
      if (value == null) return [];
      if (value is! List) throw const FormatException('Invalid table');
      return value.map((raw) {
        if (raw is! Map) throw const FormatException('Invalid row');
        final row = Map<String, dynamic>.from(raw);
        if (key != 'settlement_postings' &&
            (row['id'] is! String || (row['id'] as String).isEmpty)) {
          throw const FormatException('Missing ID');
        }
        for (final entry in row.entries) {
          if ((entry.key.endsWith('_at') || entry.key.endsWith('_on')) &&
              entry.value != null &&
              (entry.value is! String ||
                  DateTime.tryParse(entry.value as String) == null)) {
            throw const FormatException('Invalid date');
          }
          if (entry.key.endsWith('_minor') &&
              entry.value != null &&
              (entry.value is! num ||
                  !(entry.value as num).isFinite ||
                  (entry.value as num).abs() > 9007199254740991 ||
                  entry.value != (entry.value as num).round())) {
            throw const FormatException('Invalid amount');
          }
        }
        return parse(row);
      }).toList();
    }

    final household = data['household'] == null
        ? _household
        : Household.fromJson(
            Map<String, dynamic>.from(data['household'] as Map));
    if (_household != null && household?.id != _household!.id) {
      throw const FormatException('Different household');
    }
    final importedProfiles = rows('profiles', Profile.fromJson);
    final importedAccounts = rows('accounts', Account.fromJson);
    final importedCategories = rows('categories', Category.fromJson);
    final importedTransactions = rows('transactions', Txn.fromJson);
    final importedBudgets = rows('budgets', Budget.fromJson);
    final importedGoals = rows('goals', Goal.fromJson);
    final importedSettlements = rows('settlements', Settlement.fromJson);
    final importedRules = rows('recurring_rules', RecurringRule.fromJson);
    final importedPostings =
        rows('settlement_postings', SettlementPosting.fromJson);
    final importedValuations = rows('valuations', AccountValuation.fromJson);
    final importedActivities = rows('activities', ActivityEvent.fromJson);
    final householdIds = [
      ...importedProfiles.map((e) => e.householdId),
      ...importedAccounts.map((e) => e.householdId),
      ...importedCategories.map((e) => e.householdId),
      ...importedTransactions.map((e) => e.householdId),
      ...importedBudgets.map((e) => e.householdId),
      ...importedGoals.map((e) => e.householdId),
      ...importedSettlements.map((e) => e.householdId),
      ...importedRules.map((e) => e.householdId),
      ...importedActivities.map((e) => e.householdId),
    ];
    if (householdIds.any((id) => id != household?.id) ||
        (meId != null &&
            (importedAccounts.any((e) => !e.isCommon && e.ownerId != meId) ||
                importedTransactions.any((e) =>
                    e.visibility == VisibilityLevel.private &&
                    e.createdBy != meId) ||
                importedBudgets.any(
                    (e) => e.scope != Scope.together && e.ownerId != meId) ||
                importedGoals.any((e) => !e.isShared && e.ownerId != meId) ||
                importedRules.any((e) =>
                    e.visibility == VisibilityLevel.private &&
                    e.createdBy != meId) ||
                importedPostings.any((e) => e.userId != meId)))) {
      throw const FormatException('Backup contains inaccessible records');
    }
    final accessibleAccountIds = {
      ...accounts
          .where((e) => meId == null || e.isCommon || e.ownerId == meId)
          .map((e) => e.id),
      ...importedAccounts.map((e) => e.id),
    };
    if (importedValuations
        .any((e) => !accessibleAccountIds.contains(e.accountId))) {
      throw const FormatException('Inaccessible valuation');
    }
    if (validateOnly) return;
    _household = household;
    for (final e in importedProfiles) {
      _profiles[e.id] = e;
    }
    for (final e in importedAccounts) {
      _accounts[e.id] = e;
    }
    for (final e in importedCategories) {
      _categories[e.id] = e;
    }
    for (final e in importedTransactions) {
      _transactions[e.id] = e;
    }
    for (final e in importedBudgets) {
      _budgets[e.id] = e;
    }
    for (final e in importedGoals) {
      _goals[e.id] = e;
    }
    for (final e in importedSettlements) {
      _settlements[e.id] = e;
    }
    for (final e in importedRules) {
      _recurringRules[e.id] = e;
    }
    for (final e in importedPostings) {
      _settlementPostings['${e.settlementId}_${e.userId}'] = e;
    }
    for (final e in importedValuations) {
      _valuations[e.id] = e;
    }
    for (final e in importedActivities) {
      _activities[e.id] = e;
    }
    if (queueWrites) {
      if (meId == null) {
        throw const FormatException('Authenticated owner required');
      }
      for (final e in importedProfiles.where((e) => e.id == meId)) {
        _enqueueOutbox('profiles', e.id, 'upsert', e.toJson());
      }
      for (final e in importedAccounts) {
        _enqueueOutbox('accounts', e.id, 'upsert', e.toJson());
      }
      for (final e in importedCategories) {
        _enqueueOutbox('categories', e.id, 'upsert', e.toJson());
      }
      for (final e in importedTransactions) {
        _enqueueOutbox('transactions', e.id, 'upsert', e.toJson());
      }
      for (final e in importedBudgets) {
        _enqueueOutbox('budgets', e.id, 'upsert', e.toJson());
      }
      for (final e in importedGoals) {
        _enqueueOutbox('goals', e.id, 'upsert', e.toJson());
      }
      for (final e in importedSettlements) {
        _enqueueOutbox('settlements', e.id, 'upsert', e.toJson());
      }
      for (final e in importedRules) {
        _enqueueOutbox('recurring_rules', e.id, 'upsert', e.toJson());
      }
      for (final e in importedPostings) {
        _enqueueOutbox('settlement_postings', '${e.settlementId}_${e.userId}',
            'upsert', e.toJson());
      }
      for (final e in importedValuations) {
        _enqueueOutbox('account_valuations', e.id, 'upsert', e.toJson());
      }
    }
    _notify();
  }

  /// Includes tombstones and unacknowledged writes so a restart cannot resurrect
  /// deleted records or silently lose pending changes.
  Map<String, dynamic> exportLocalState() => {
        'data': {
          ...exportVisibleJson(),
          'accounts': _accounts.values.map((e) => e.toJson()).toList(),
          'transactions': _transactions.values.map((e) => e.toJson()).toList(),
          'budgets': _budgets.values.map((e) => e.toJson()).toList(),
          'goals': _goals.values.map((e) => e.toJson()).toList(),
          'recurring_rules':
              _recurringRules.values.map((e) => e.toJson()).toList(),
          'settlements': _settlements.values.map((e) => e.toJson()).toList(),
        },
        'outbox': _outbox
            .map((e) => {
                  'id': e.id,
                  'table': e.tableName,
                  'record_id': e.recordId,
                  'operation': e.operation,
                  'payload': e.payload,
                  'created_at': e.createdAt.toIso8601String()
                })
            .toList(),
        'last_pulled_at': lastPulledAt?.toIso8601String(),
      };

  void restoreLocalState(Map<String, dynamic> state, {required String meId}) {
    final entries = (state['outbox'] as List? ?? [])
        .map((e) => OutboxEntry(
            id: e['id'] as String,
            tableName: e['table'] as String,
            recordId: e['record_id'] as String,
            operation: e['operation'] as String,
            payload: Map<String, dynamic>.from(e['payload'] as Map),
            createdAt: DateTime.parse(e['created_at'] as String)))
        .toList();
    restoreFromJson(Map<String, dynamic>.from(state['data'] as Map),
        meId: meId);
    _outbox.addAll(entries);
    lastPulledAt = DateTime.tryParse(state['last_pulled_at'] as String? ?? '');
  }

  void clear() {
    _household = null;
    _profiles.clear();
    _accounts.clear();
    _transactions.clear();
    _categories.clear();
    _budgets.clear();
    _settlements.clear();
    _settlementPostings.clear();
    _recurringRules.clear();
    _valuations.clear();
    _goals.clear();
    _activities.clear();
    _outbox.clear();
    lastPulledAt = null;
    _notify();
  }

  void replaceRemoteSnapshot(Map<String, dynamic> data) {
    final merged = Map<String, dynamic>.from(data);
    const keys = {
      'households': 'household',
      'profiles': 'profiles',
      'accounts': 'accounts',
      'transactions': 'transactions',
      'categories': 'categories',
      'budgets': 'budgets',
      'settlements': 'settlements',
      'settlement_postings': 'settlement_postings',
      'recurring_rules': 'recurring_rules',
      'account_valuations': 'valuations',
      'goals': 'goals',
      'activity': 'activities'
    };
    final pending = [..._outbox];
    for (final entry in pending) {
      final key = keys[entry.tableName];
      if (key == null) throw StateError('Unsupported pending table');
      if (key == 'household') {
        merged[key] = entry.payload;
        continue;
      }
      final rows = [...(merged[key] as List? ?? [])];
      rows.removeWhere((e) => key == 'settlement_postings'
          ? e['settlement_id'] == entry.payload['settlement_id'] &&
              e['user_id'] == entry.payload['user_id']
          : e['id'] == entry.payload['id']);
      rows.add(entry.payload);
      merged[key] = rows;
    }
    restoreFromJson(merged, validateOnly: true);
    clear();
    restoreFromJson(merged);
    _outbox.addAll(pending);
  }

  void _seedDefaultData() {
    final now = DateTime.now();
    const hhId = 'hh-default-001';
    const samId = 'user-sam';
    const annaId = 'user-anna';

    _household = Household(
      id: hhId,
      name: 'Sam & Anna',
      baseCurrency: CurrencyCode.huf,
      defaultSplitPct: 50,
      inviteCode: 'DUO-2026',
      emergencyFundMonths: 6,
      createdAt: now,
    );

    _profiles[samId] = Profile(
      id: samId,
      householdId: hhId,
      displayName: 'Sam',
      color: '#013328',
      locale: 'en',
      avatarType: 'man',
      monthlyCommonContributionMinor: 15000000, // 150 000 Ft
      updatedAt: now,
    );
    _profiles[annaId] = Profile(
      id: annaId,
      householdId: hhId,
      displayName: 'Anna',
      color: '#CC8B65',
      locale: 'hu',
      avatarType: 'woman',
      monthlyCommonContributionMinor: 15000000, // 150 000 Ft
      updatedAt: now,
    );

    // Accounts: Common bank, Sam's personal bank, Sam's personal cash, Sam's savings
    _accounts['acc-common'] = Account(
      id: 'acc-common',
      householdId: hhId,
      name: 'Common Bank Account',
      type: AccountType.bank,
      ownership: AccountOwnership.common,
      currency: CurrencyCode.huf,
      openingBalanceMinor: 32000000, // 320 000 Ft
      openingDate: DateTime(now.year, 1, 1),
      updatedAt: now,
    );
    _accounts['acc-sam-bank'] = Account(
      id: 'acc-sam-bank',
      householdId: hhId,
      name: 'Sam Personal Card',
      type: AccountType.bank,
      ownership: AccountOwnership.personal,
      ownerId: samId,
      currency: CurrencyCode.huf,
      openingBalanceMinor: 48000000, // 480 000 Ft
      openingDate: DateTime(now.year, 1, 1),
      updatedAt: now,
    );
    _accounts['acc-sam-cash'] = Account(
      id: 'acc-sam-cash',
      householdId: hhId,
      name: 'Sam Cash',
      type: AccountType.cash,
      ownership: AccountOwnership.personal,
      ownerId: samId,
      currency: CurrencyCode.huf,
      openingBalanceMinor: 2500000, // 25 000 Ft
      openingDate: DateTime(now.year, 1, 1),
      updatedAt: now,
    );
    _accounts['acc-sam-savings'] = Account(
      id: 'acc-sam-savings',
      householdId: hhId,
      name: 'PMÁP / Savings',
      type: AccountType.savings,
      ownership: AccountOwnership.personal,
      ownerId: samId,
      currency: CurrencyCode.huf,
      openingBalanceMinor: 150000000, // 1 500 000 Ft
      openingDate: DateTime(now.year, 1, 1),
      interestRatePct: 6.5,
      compounding: Compounding.monthly,
      interestTaxPct: 0,
      updatedAt: now,
    );

    final defaultCats = [
      (
        'cat-groceries',
        'Groceries',
        'Élelmiszer',
        'expense',
        'shopping_cart',
        '#10B981',
        true,
        1
      ),
      (
        'cat-housing',
        'Housing & Utilities',
        'Lakhatás és rezsi',
        'expense',
        'home',
        '#3B82F6',
        true,
        2
      ),
      (
        'cat-dining',
        'Dining & Coffee',
        'Étterem és kávé',
        'expense',
        'restaurant',
        '#F59E0B',
        false,
        3
      ),
      (
        'cat-transport',
        'Transport',
        'Közlekedés',
        'expense',
        'directions_car',
        '#6366F1',
        true,
        4
      ),
      (
        'cat-health',
        'Health',
        'Egészség',
        'expense',
        'favorite',
        '#EF4444',
        true,
        5
      ),
      (
        'cat-fun',
        'Entertainment & Gifts',
        'Szórakozás és ajándék',
        'expense',
        'celebration',
        '#EC4899',
        false,
        6
      ),
      (
        'cat-salary',
        'Salary',
        'Fizetés',
        'income',
        'payments',
        '#14B8A6',
        false,
        7
      ),
    ];
    for (final c in defaultCats) {
      _categories[c.$1] = Category(
        id: c.$1,
        householdId: hhId,
        nameEn: c.$2,
        nameHu: c.$3,
        kind: c.$4,
        icon: c.$5,
        color: c.$6,
        isEssential: c.$7,
        sortOrder: c.$8,
        updatedAt: now,
      );
    }

    // Seed sample transactions demonstrating all 3 views & privacy rules:
    final split60_40 = calculatePercentageSplit(
      amountMinor: 1000000, // 10 000 Ft
      baseAmountMinor: 1000000,
      userA: samId,
      userB: annaId,
      pctA: 60,
    );
    _transactions['txn-together-card'] = Txn(
      id: 'txn-together-card',
      householdId: hhId,
      kind: TxnKind.expense,
      scope: Scope.together,
      visibility: VisibilityLevel.shared,
      occurredOn: now.subtract(const Duration(days: 2)),
      amountMinor: 1000000,
      baseAmountMinor: 1000000,
      paidBy: samId,
      paidFromCommon: false,
      accountId: 'acc-sam-bank',
      accountAmountMinor: 1000000,
      categoryId: 'cat-groceries',
      merchant: 'Lidl',
      note: 'Weekly groceries (60/40)',
      createdBy: samId,
      createdAt: now,
      updatedAt: now,
      shares: split60_40.sharesMinor,
      baseShares: split60_40.baseSharesMinor,
      tags: const ['Household'],
    );

    final split50_50 = calculatePercentageSplit(
      amountMinor: 845000, // 8 450 Ft
      baseAmountMinor: 845000,
      userA: samId,
      userB: annaId,
      pctA: 50,
    );
    _transactions['txn-common-rent'] = Txn(
      id: 'txn-common-rent',
      householdId: hhId,
      kind: TxnKind.expense,
      scope: Scope.together,
      visibility: VisibilityLevel.shared,
      occurredOn: now.subtract(const Duration(days: 5)),
      amountMinor: 845000,
      baseAmountMinor: 845000,
      paidBy: annaId,
      paidFromCommon: true,
      accountId: 'acc-common',
      accountAmountMinor: 845000,
      categoryId: 'cat-housing',
      merchant: 'MVM Next',
      note: 'Electricity bill from common account',
      createdBy: annaId,
      createdAt: now,
      updatedAt: now,
      shares: split50_50.sharesMinor,
      baseShares: split50_50.baseSharesMinor,
    );

    final indivSplit = calculateIndividualSplit(
      amountMinor: 500000, // 5 000 Ft
      baseAmountMinor: 500000,
      ownerId: samId,
    );
    _transactions['txn-sam-private'] = Txn(
      id: 'txn-sam-private',
      householdId: hhId,
      kind: TxnKind.expense,
      scope: Scope.individual,
      visibility: VisibilityLevel.private,
      occurredOn: now.subtract(const Duration(days: 1)),
      amountMinor: 500000,
      baseAmountMinor: 500000,
      paidBy: samId,
      paidFromCommon: false,
      accountId: 'acc-sam-bank',
      accountAmountMinor: 500000,
      categoryId: 'cat-fun',
      merchant: 'Bookline',
      note: 'Surprise gift (Private)',
      createdBy: samId,
      createdAt: now,
      updatedAt: now,
      shares: indivSplit.sharesMinor,
      baseShares: indivSplit.baseSharesMinor,
    );

    // Seed budgets
    _budgets['bud-together-total'] = Budget(
      id: 'bud-together-total',
      householdId: hhId,
      scope: Scope.together,
      amountMinor: 25000000, // 250 000 Ft
      rollover: true,
      updatedAt: now,
    );
    _budgets['bud-my-total'] = Budget(
      id: 'bud-my-total',
      householdId: hhId,
      scope: Scope.individual,
      ownerId: samId,
      amountMinor: 18000000, // 180 000 Ft
      rollover: false,
      updatedAt: now,
    );

    // Seed goals
    _goals['goal-vacation'] = Goal(
      id: 'goal-vacation',
      householdId: hhId,
      name: 'Greece 2027 Vacation',
      type: 'savings',
      scope: 'shared',
      targetAmountMinor: 80000000, // 800 000 Ft
      savedAmountMinor: 40000000,
      annualInterestRatePct: 5.0,
      deadline: DateTime(now.year + 1, 6, 1),
      contributionsByUser: {samId: 20000000, annaId: 20000000},
      updatedAt: now,
    );
    _goals['goal-emergency-shared'] = Goal(
      id: 'goal-emergency-shared',
      householdId: hhId,
      name: 'Shared Emergency Fund',
      type: 'emergency_fund',
      scope: 'shared',
      targetAmountMinor: 90000000, // 900 000 Ft
      savedAmountMinor: 45000000,
      annualInterestRatePct: 6.0,
      updatedAt: now,
    );

    // Seed recurring rule
    _recurringRules['rec-netflix'] = RecurringRule(
      id: 'rec-netflix',
      householdId: hhId,
      title: 'Netflix Standard',
      kind: TxnKind.expense,
      scope: Scope.together,
      visibility: VisibilityLevel.shared,
      amountMinor: 449000, // 4 490 Ft
      accountId: 'acc-common',
      categoryId: 'cat-fun',
      frequency: 'monthly',
      nextDueOn: DateTime(now.year, now.month + 1, 5),
      autoCreate: true,
      isSubscription: true,
      createdBy: samId,
      updatedAt: now,
    );

    // Seed shared activity
    _activities['act-1'] = ActivityEvent(
      id: 'act-1',
      householdId: hhId,
      actorId: annaId,
      eventType: 'expense_added',
      summaryEn: 'Anna added MVM Next 8 450 Ft (Together)',
      summaryHu: 'Anna hozzáadta: MVM Next 8 450 Ft (Közös)',
      amountMinor: 845000,
      createdAt: now.subtract(const Duration(hours: 5)),
    );
    _activities['act-2'] = ActivityEvent(
      id: 'act-2',
      householdId: hhId,
      actorId: samId,
      eventType: 'expense_added',
      summaryEn: 'Sam added Lidl 10 000 Ft (Together 60/40)',
      summaryHu: 'Sam hozzáadta: Lidl 10 000 Ft (Közös 60/40)',
      amountMinor: 1000000,
      createdAt: now.subtract(const Duration(hours: 2)),
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final currentUserIdProvider = StateProvider<String>((ref) => 'user-sam');
final partnerUserIdProvider = StateProvider<String>((ref) => 'user-anna');
final appLocaleProvider = StateProvider<String>((ref) => 'en');
final hideAmountsProvider = StateProvider<bool>((ref) => false);
final displayCurrencyProvider =
    StateProvider<CurrencyCode>((ref) => CurrencyCode.huf);
final fxServiceProvider = Provider<FxService>((ref) => FxService());

final dbTickProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(appDatabaseProvider);
  var i = 0;
  yield i;
  await for (final _ in db.changes) {
    yield ++i;
  }
});
