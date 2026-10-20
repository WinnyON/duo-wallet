import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/splits.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/fx_service.dart';
import '../../../core/money/money.dart';
import '../../../core/sync/sync_engine.dart';

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
    final acc = db.findAccount(r.accountId);
    final paidFromCommon = acc?.isCommon ?? false;
    final effectiveScope = paidFromCommon ? Scope.together : r.scope;
    final money = Money(r.amountMinor, r.currency);
    final baseMinor = fx.convert(money, CurrencyCode.huf).amountMinor;
    final acctMinor = acc != null
        ? fx.convert(money, acc.currency).amountMinor
        : r.amountMinor;

    final split = effectiveScope == Scope.together
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
        note: 'Recurring (${r.frequency})',
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
    BuildContext context,
    AppDatabase db,
    String meId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final visibleAccounts = db.accounts
        .where((a) => a.isCommon || a.ownerId == meId)
        .toList();
    if (visibleAccounts.isEmpty) return;

    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    const kind = TxnKind.expense;
    var scope = Scope.together;
    var currency = CurrencyCode.huf;
    var frequency = 'monthly';
    var isSubscription = true;
    var autoCreate = true;
    var accountId = visibleAccounts.first.id;
    final String? categoryId = db.categories.firstOrNull?.id;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            l10n.t('Add Recurring Rule', 'Új ismétlődő szabály'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.t('Title (e.g. Netflix, Rent)', 'Megnevezés'),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<Scope>(
                  segments: [
                    ButtonSegment(
                      value: Scope.together,
                      label: Text('👥 ${l10n.viewTogether}'),
                    ),
                    ButtonSegment(
                      value: Scope.individual,
                      label: Text('🔒 ${l10n.viewIndividual}'),
                    ),
                  ],
                  selected: {scope},
                  onSelectionChanged: (s) =>
                      setDialogState(() => scope = s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.t('Amount', 'Összeg'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<CurrencyCode>(
                        initialValue: currency,
                        decoration: InputDecoration(
                          labelText: l10n.t('Currency', 'Pénznem'),
                        ),
                        items: CurrencyCode.values
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c.code),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialogState(() => currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: frequency,
                  decoration: InputDecoration(
                    labelText: l10n.t('Frequency', 'Gyakoriság'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'weekly',
                      child: Text(l10n.t('Weekly', 'Heti')),
                    ),
                    DropdownMenuItem(
                      value: 'monthly',
                      child: Text(l10n.t('Monthly', 'Havi')),
                    ),
                    DropdownMenuItem(
                      value: 'yearly',
                      child: Text(l10n.t('Yearly', 'Éves')),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => frequency = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: InputDecoration(
                    labelText: l10n.t('Account', 'Számla'),
                  ),
                  items: visibleAccounts
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => accountId = v);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.t('Subscription', 'Előfizetés')),
                  value: isSubscription,
                  onChanged: (v) => setDialogState(() => isSubscription = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.t('Auto-create on due date', 'Automatikus rögzítés'),
                  ),
                  value: autoCreate,
                  onChanged: (v) => setDialogState(() => autoCreate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.t('Cancel', 'Mégse')),
            ),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                final major =
                    double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ??
                        0;
                if (title.isEmpty || major <= 0) return;
                final acc = db.findAccount(accountId);
                final effectiveScope =
                    (acc?.isCommon ?? false) ? Scope.together : scope;
                final vis = effectiveScope == Scope.together
                    ? VisibilityLevel.shared
                    : VisibilityLevel.private;
                final now = DateTime.now();

                db.upsertRecurringRule(
                  RecurringRule(
                    id: _uuid.v4(),
                    householdId: db.household?.id ?? 'hh-default-001',
                    title: title,
                    kind: kind,
                    scope: effectiveScope,
                    visibility: vis,
                    amountMinor: Money.fromMajor(major, currency).amountMinor,
                    currency: currency,
                    accountId: accountId,
                    categoryId: categoryId,
                    frequency: frequency,
                    nextDueOn: DateTime(now.year, now.month, now.day),
                    autoCreate: autoCreate,
                    isSubscription: isSubscription,
                    createdBy: meId,
                    updatedAt: now,
                  ),
                );
                Navigator.of(ctx).pop();
              },
              child: Text(l10n.t('Save', 'Mentés')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final fx = ref.watch(fxServiceProvider);
    final meId = ref.watch(currentUserIdProvider);
    final partnerId = ref.watch(partnerUserIdProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;

    final rules = db.recurringRules
        .where(
          (r) =>
              r.visibility == VisibilityLevel.shared || r.createdBy == meId,
        )
        .toList()
      ..sort((a, b) => a.nextDueOn.compareTo(b.nextDueOn));

    var monthlyFixedMinor = 0;
    for (final r in rules) {
      if (r.kind != TxnKind.expense) continue;
      final baseMinor =
          fx.convert(Money(r.amountMinor, r.currency), CurrencyCode.huf)
              .amountMinor;
      final factor = switch (r.frequency) {
        'weekly' => 52 / 12,
        'yearly' => 1 / 12,
        _ => 1.0,
      };
      monthlyFixedMinor += (baseMinor * factor).round();
    }
    final yearlyFixedMinor = monthlyFixedMinor * 12;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recurring),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddRuleDialog(context, db, meId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('Monthly Fixed Costs', 'Havi fix költségek'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Money(monthlyFixedMinor, CurrencyCode.huf).format(
                          locale: localeStr,
                          hideAmounts: hideAmounts,
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('Yearly Projection', 'Éves összesített'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Money(yearlyFixedMinor, CurrencyCode.huf).format(
                          locale: localeStr,
                          hideAmounts: hideAmounts,
                        ),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.t('Upcoming Bills & Rules', 'Esedékes számlák és szabályok'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              FilledButton.tonalIcon(
                onPressed: rules.isEmpty
                    ? null
                    : () {
                        for (final r in rules) {
                          _generateFromRule(db, fx, r, meId, partnerId);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              l10n.t(
                                'Generated due transactions (idempotent UUIDv5).',
                                'Esedékes tranzakciók létrehozva (duplikációmentes).',
                              ),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.play_arrow_outlined),
                label: Text(l10n.t('Generate due now', 'Generálás most')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rules.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  l10n.t(
                    'No recurring rules yet.',
                    'Még nincs ismétlődő szabály.',
                  ),
                ),
              ),
            ),
          for (final r in rules)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: Icon(
                  r.isSubscription
                      ? Icons.subscriptions_outlined
                      : Icons.autorenew_outlined,
                ),
                title: Text(
                  '${r.title} (${r.visibility == VisibilityLevel.shared ? "👥" : "🔒"})',
                ),
                subtitle: Text(
                  '${r.frequency} • ${l10n.t("Next due:", "Következő:")} '
                  '${r.nextDueOn.toIso8601String().split("T").first}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Money(r.amountMinor, r.currency).format(
                        locale: localeStr,
                        hideAmounts: hideAmounts,
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: l10n.t('Generate due now', 'Generálás most'),
                      icon: const Icon(Icons.playlist_add_check),
                      onPressed: () =>
                          _generateFromRule(db, fx, r, meId, partnerId),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
