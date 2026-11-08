import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/splits.dart';
import '../../../core/domain/recurring_schedule.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../theme.dart';

class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  static const _uuid = Uuid();

  void _generateFromRule(
    AppDatabase db,
    FxService fx,
    RecurringRule r,
    String meId,
    String partnerId,
  ) {
    final txnId = SyncEngine.deterministicRecurringTxnId(r.id, r.nextDueOn);
    if (db.transactions.any((t) => t.id == txnId)) return;
    final acc = db.findAccount(r.accountId);
    final paidFromCommon = acc?.isCommon ?? false;
    final effectiveScope = paidFromCommon
        ? Scope.together
        : partnerId.isEmpty
            ? Scope.individual
            : r.scope;
    final money = Money(r.amountMinor, r.currency);
    final baseMinor = fx.convert(money, CurrencyCode.huf).amountMinor;
    final acctMinor = acc != null
        ? fx.convert(money, acc.currency).amountMinor
        : r.amountMinor;

    final split = effectiveScope == Scope.together && partnerId.isNotEmpty
        ? calculatePercentageSplit(
            amountMinor: r.amountMinor,
            baseAmountMinor: baseMinor,
            userA: r.createdBy,
            userB: r.createdBy == meId ? partnerId : meId,
            pctA: r.splitPctCreator,
          )
        : calculateIndividualSplit(
            amountMinor: r.amountMinor,
            baseAmountMinor: baseMinor,
            ownerId: r.createdBy,
          );

    final now = DateTime.now();
    db.saveTransaction(
      Txn(
        id: txnId,
        householdId: r.householdId,
        kind: r.kind,
        scope: effectiveScope,
        visibility: effectiveScope == Scope.together || paidFromCommon
            ? VisibilityLevel.shared
            : VisibilityLevel.private,
        occurredOn: r.nextDueOn,
        amountMinor: r.amountMinor,
        currency: r.currency,
        fxRateToBase: fx.getRate(r.currency, CurrencyCode.huf).rate,
        baseAmountMinor: baseMinor,
        paidBy: r.createdBy,
        paidFromCommon: paidFromCommon,
        accountId: r.accountId,
        accountAmountMinor: acctMinor,
        toAccountId: r.toAccountId,
        categoryId: r.categoryId,
        merchant: r.title,
        note: null,
        recurringRuleId: r.id,
        createdBy: r.createdBy,
        createdAt: now,
        updatedAt: now,
        shares: split.sharesMinor,
        baseShares: split.baseSharesMinor,
      ),
    );
  }

  Future<void> _showAddRuleDialog(
      BuildContext context, AppDatabase db, String meId,
      {RecurringRule? existing}) async {
    final l = AppLocalizations.of(context);
    final accounts = db.accounts
        .where((a) => !a.archived && (a.isCommon || a.ownerId == meId))
        .toList();
    if (accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              l.t('Create an account first.', 'Előbb hozz létre számlát.'))));
      return;
    }
    final title = TextEditingController(text: existing?.title ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : (existing.amountMinor / 100).toString());
    var accountId = existing?.accountId ?? accounts.first.id;
    if (!accounts.any((a) => a.id == accountId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l.t('This rule uses an unavailable account.',
              'A szabály számlája nem érhető el.'))));
      return;
    }
    var category = existing?.categoryId;
    final categories = db.categories.where((c) => c.kind == 'expense').toList();
    final hasPartner = ref.read(partnerUserIdProvider).isNotEmpty;
    var scope =
        hasPartner ? existing?.scope ?? Scope.together : Scope.individual;
    var currency = existing?.currency ?? accounts.first.currency;
    var frequency = existing?.frequency ?? 'monthly';
    var due = existing?.nextDueOn ?? DateTime.now();
    var pct = existing?.splitPctCreator ?? 50;
    var active = existing?.autoCreate ?? true;
    final form = GlobalKey<FormState>();
    final initialTitle = title.text;
    final initialAmount = amount.text;
    final initialAccount = accountId;
    final initialCategory = category;
    final initialScope = scope;
    final initialCurrency = currency;
    final initialFrequency = frequency;
    final initialDue = due;
    final initialPct = pct;
    final initialActive = active;
    bool dirty() =>
        title.text != initialTitle ||
        amount.text != initialAmount ||
        accountId != initialAccount ||
        category != initialCategory ||
        scope != initialScope ||
        currency != initialCurrency ||
        frequency != initialFrequency ||
        due != initialDue ||
        pct != initialPct ||
        active != initialActive;
    final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          Future<void> close() async {
            if (await confirmDiscardChanges(ctx, dirty: dirty())) {
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }

          return StatefulBuilder(
              builder: (ctx, update) => PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, result) {
                    if (!didPop) close();
                  },
                  child: AlertDialog(
                    title: Text(existing == null
                        ? l.t('New recurring rule', 'Új ismétlődő szabály')
                        : l.t('Edit recurring rule',
                            'Ismétlődő szabály szerkesztése')),
                    content: SingleChildScrollView(
                        child: Form(
                            key: form,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(l.t(
                                      'Records are created only when you choose Record due bills. No automatic background scheduling.',
                                      'A tételek csak az Esedékes számlák rögzítése gombbal készülnek el. Nincs automatikus háttérütemezés.')),
                                  TextFormField(
                                      controller: title,
                                      decoration: InputDecoration(
                                          labelText:
                                              l.t('Title', 'Megnevezés')),
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? l.t('Enter a title',
                                                  'Adj meg megnevezést')
                                              : null),
                                  TextFormField(
                                      controller: amount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                          labelText: l.t('Amount', 'Összeg')),
                                      validator: (v) =>
                                          parsePositiveAmount(v ?? '') == null
                                              ? l.t('Enter a positive amount',
                                                  'Adj meg pozitív összeget')
                                              : null),
                                  DropdownButtonFormField<CurrencyCode>(
                                      initialValue: currency,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              l.t('Currency', 'Pénznem')),
                                      items: CurrencyCode.values
                                          .map((v) => DropdownMenuItem(
                                              value: v, child: Text(v.code)))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          update(() => currency = v);
                                        }
                                      }),
                                  DropdownButtonFormField<String>(
                                      initialValue: accountId,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: l.t('Account', 'Számla')),
                                      items: accounts
                                          .map((a) => DropdownMenuItem(
                                              value: a.id, child: Text(a.name)))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          update(() => accountId = v);
                                        }
                                      }),
                                  DropdownButtonFormField<String>(
                                      initialValue: category,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              l.t('Category', 'Kategória')),
                                      items: categories
                                          .map((c) => DropdownMenuItem(
                                              value: c.id,
                                              child: Text(c.localizedName(
                                                  l.locale.languageCode))))
                                          .toList(),
                                      onChanged: (v) =>
                                          update(() => category = v),
                                      validator: (v) => v == null
                                          ? l.t('Choose a category',
                                              'Válassz kategóriát')
                                          : null),
                                  DropdownButtonFormField<String>(
                                      initialValue: frequency,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText:
                                              l.t('Frequency', 'Gyakoriság')),
                                      items: [
                                        'daily',
                                        'weekly',
                                        'monthly',
                                        'yearly'
                                      ]
                                          .map((f) => DropdownMenuItem(
                                              value: f,
                                              child: Text(_frequency(l, f))))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null) {
                                          update(() => frequency = v);
                                        }
                                      }),
                                  SegmentedButton<Scope>(
                                      segments: [
                                        ButtonSegment(
                                            value: Scope.together,
                                            enabled: hasPartner,
                                            label:
                                                Text(l.t('Shared', 'Közös'))),
                                        ButtonSegment(
                                            value: Scope.individual,
                                            label:
                                                Text(l.t('Personal', 'Saját')))
                                      ],
                                      selected: {
                                        scope
                                      },
                                      onSelectionChanged: (s) =>
                                          update(() => scope = s.first)),
                                  if (!hasPartner)
                                    Text(l.t(
                                        'Invite a partner to split expenses.',
                                        'Hívj meg egy társat a kiadások megosztásához.')),
                                  if (scope == Scope.together &&
                                      hasPartner) ...[
                                    Text(l.t('Creator share: $pct%',
                                        'Létrehozó része: $pct%')),
                                    Slider(
                                        value: pct.toDouble(),
                                        min: 0,
                                        max: 100,
                                        divisions: 20,
                                        label: '$pct%',
                                        onChanged: (v) =>
                                            update(() => pct = v.round())),
                                  ],
                                  TextButton.icon(
                                      icon: const Icon(Icons.calendar_today),
                                      label: Text(
                                          '${l.t("Next due", "Következő esedékesség")}: ${DateFormat.yMMMd(l.locale.languageCode).format(due)}'),
                                      onPressed: () async {
                                        final date = await showDatePicker(
                                            context: ctx,
                                            initialDate: due,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2200));
                                        if (date != null) {
                                          update(() => due = date);
                                        }
                                      }),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(l.t('Active', 'Aktív')),
                                      value: active,
                                      onChanged: (v) =>
                                          update(() => active = v)),
                                ]))),
                    actions: [
                      TextButton(
                          onPressed: close,
                          child: Text(l.t('Cancel', 'Mégse'))),
                      FilledButton(
                          onPressed: () {
                            if (!form.currentState!.validate()) return;
                            final common = accounts
                                .firstWhere((a) => a.id == accountId)
                                .isCommon;
                            final effectiveScope = common
                                ? Scope.together
                                : hasPartner
                                    ? scope
                                    : Scope.individual;
                            final json = existing?.toJson() ??
                                RecurringRule(
                                        id: _uuid.v4(),
                                        householdId: db.household?.id ??
                                            'hh-default-001',
                                        title: title.text.trim(),
                                        amountMinor: 0,
                                        accountId: accountId,
                                        nextDueOn: due,
                                        createdBy: meId,
                                        updatedAt: DateTime.now())
                                    .toJson();
                            json.addAll({
                              'title': title.text.trim(),
                              'amount_minor': Money.fromMajor(
                                      parsePositiveAmount(amount.text)!,
                                      currency)
                                  .amountMinor,
                              'currency': currency.code,
                              'account_id': accountId,
                              'category_id': category,
                              'frequency': frequency,
                              'next_due_on': due.toIso8601String(),
                              'scope': effectiveScope.value,
                              'visibility': effectiveScope == Scope.together
                                  ? 'shared'
                                  : 'private',
                              'split_pct_creator': hasPartner ? pct : 100,
                              'auto_create': active,
                              'updated_at': DateTime.now().toIso8601String()
                            });
                            db.upsertRecurringRule(
                                RecurringRule.fromJson(json));
                            Navigator.pop(ctx);
                          },
                          child: Text(l.t('Save', 'Mentés')))
                    ],
                  )));
        });
    await Navigator.of(context).push(route);
    await route.completed;
    title.dispose();
    amount.dispose();
  }

  String _frequency(AppLocalizations l, String f) => switch (f) {
        'weekly' => l.t('Weekly', 'Heti'),
        'yearly' => l.t('Yearly', 'Éves'),
        'daily' => l.t('Daily', 'Napi'),
        _ => l.t('Monthly', 'Havi')
      };

  int _recordDue(AppDatabase db, FxService fx, RecurringRule rule, String me,
      String partner) {
    if (!rule.autoCreate || rule.deletedAt != null) return 0;
    final account = db.findAccount(rule.accountId);
    if (account == null ||
        account.archived ||
        (!account.isCommon && account.ownerId != me)) {
      return 0;
    }
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    var current = rule;
    var count = 0;
    // The earliest generated occurrence retains the intended day after February.
    final previous = db.transactions
        .where((t) => t.recurringRuleId == rule.id)
        .toList()
      ..sort((a, b) => a.occurredOn.compareTo(b.occurredOn));
    var anchorDay =
        previous.isEmpty ? rule.nextDueOn.day : previous.first.occurredOn.day;
    if (previous.isNotEmpty &&
        nextRecurringDate(previous.last.occurredOn, rule.frequency,
                anchorDay: anchorDay) !=
            rule.nextDueOn) {
      anchorDay = rule.nextDueOn.day;
    }
    while (current.nextDueOn.isBefore(tomorrow)) {
      final id =
          SyncEngine.deterministicRecurringTxnId(current.id, current.nextDueOn);
      if (!db.transactions.any((t) => t.id == id)) {
        _generateFromRule(db, fx, current, me, partner);
        count++;
      }
      current = RecurringRule.fromJson({
        ...current.toJson(),
        'next_due_on': nextRecurringDate(current.nextDueOn, current.frequency,
                anchorDay: anchorDay)
            .toIso8601String(),
        'updated_at': now.toIso8601String()
      });
    }
    db.upsertRecurringRule(current);
    return count;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final fx = ref.watch(fxServiceProvider);
    final me = ref.watch(currentUserIdProvider);
    final partner = ref.watch(partnerUserIdProvider);
    final hidden = ref.watch(hideAmountsProvider);
    final l = AppLocalizations.of(context);
    final rules = db.recurringRules
        .where((r) =>
            r.deletedAt == null &&
            (r.visibility == VisibilityLevel.shared || r.createdBy == me))
        .toList()
      ..sort((a, b) => a.nextDueOn.compareTo(b.nextDueOn));
    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => AppShell.openDrawer(context),
                tooltip: l.t('Menu', 'Menü')),
            title: Text(l.recurring),
            actions: [
              IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l.t('Add rule', 'Szabály hozzáadása'),
                  onPressed: () => _showAddRuleDialog(context, db, me))
            ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(l.t(
              'Records due bills locally when requested. Future and paused rules stay unchanged.',
              'Kérésre helyben rögzíti az esedékes számlákat. A jövőbeli és szünetelő szabályok nem változnak.')),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
              icon: const Icon(Icons.play_arrow),
              label:
                  Text(l.t('Record due bills', 'Esedékes számlák rögzítése')),
              onPressed: rules.isEmpty
                  ? null
                  : () {
                      var count = 0;
                      for (final r in rules) {
                        count += _recordDue(db, fx, r, me, partner);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(l.t('$count bills recorded.',
                              '$count számla rögzítve.'))));
                    }),
          if (rules.isEmpty)
            DuoSection(
                child: TextButton(
                    onPressed: () => _showAddRuleDialog(context, db, me),
                    child: Text(l.t('Add your first recurring bill',
                        'Első ismétlődő számla hozzáadása')))),
          for (final rule in rules)
            DuoSection(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(rule.title,
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(Money(rule.amountMinor, rule.currency).format(
                      locale: l.locale.languageCode, hideAmounts: hidden)),
                  Text(
                      '${_frequency(l, rule.frequency)} • ${DateFormat.yMMMd(l.locale.languageCode).format(rule.nextDueOn)} • ${rule.autoCreate ? l.t("Active", "Aktív") : l.t("Paused", "Szünetel")}'),
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                        onPressed: () =>
                            _showAddRuleDialog(context, db, me, existing: rule),
                        child: Text(l.t('Edit', 'Szerkesztés'))),
                    TextButton(
                        onPressed: () =>
                            db.upsertRecurringRule(RecurringRule.fromJson({
                              ...rule.toJson(),
                              'auto_create': !rule.autoCreate,
                              'updated_at': DateTime.now().toIso8601String()
                            })),
                        child: Text(rule.autoCreate
                            ? l.t('Pause', 'Szüneteltetés')
                            : l.t('Resume', 'Folytatás'))),
                    TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: Text(l.t('Remove rule?',
                                          'Szabály eltávolítása?')),
                                      content: Text(rule.title),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child:
                                                Text(l.t('Cancel', 'Mégse'))),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: Text(
                                                l.t('Remove', 'Eltávolítás')))
                                      ]));
                          if (confirmed == true) {
                            db.upsertRecurringRule(RecurringRule.fromJson({
                              ...rule.toJson(),
                              'deleted_at': DateTime.now().toIso8601String(),
                              'updated_at': DateTime.now().toIso8601String()
                            }));
                          }
                        },
                        child: Text(l.t('Remove', 'Eltávolítás'))),
                  ]),
                ])),
        ]));
  }
}
