import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../transfers/presentation/transfer_sheet.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  Future<void> _showAccountDialog(
    BuildContext context,
    AppDatabase db,
    String meId, {
    Account? existing,
  }) async {
    final l10n = AppLocalizations.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final openingCtrl = TextEditingController(
      text: existing != null
          ? Money(existing.openingBalanceMinor, existing.currency)
                .majorAmount
                .toStringAsFixed(existing.currency.displayDecimals)
          : '0',
    );
    final rateCtrl = TextEditingController(
      text: existing?.interestRatePct?.toString() ?? '',
    );
    final taxCtrl = TextEditingController(
      text: (existing?.interestTaxPct ?? 0).toString(),
    );

    var type = existing?.type ?? AccountType.bank;
    var ownership = existing?.ownership ?? AccountOwnership.personal;
    var currency = existing?.currency ?? CurrencyCode.huf;
    var compounding = existing?.compounding ?? Compounding.monthly;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final hasInterest =
              type == AccountType.savings || type == AccountType.deposit;
          return AlertDialog(
            title: Text(
              existing == null
                  ? l10n.t('New Account', 'Új számla')
                  : l10n.t('Edit Account', 'Számla szerkesztése'),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.t('Account Name', 'Számla neve'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountOwnership>(
                    initialValue: ownership,
                    decoration: InputDecoration(
                      labelText: l10n.t('Ownership / Visibility', 'Tulajdon / Láthatóság'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: AccountOwnership.personal,
                        child: Text('🔒 ${l10n.personalAccount}'),
                      ),
                      DropdownMenuItem(
                        value: AccountOwnership.common,
                        child: Text('👥 ${l10n.commonAccount}'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => ownership = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<AccountType>(
                    initialValue: type,
                    decoration: InputDecoration(
                      labelText: l10n.t('Type', 'Típus'),
                    ),
                    items: AccountType.values
                        .map(
                          (t) => DropdownMenuItem(
                            value: t,
                            child: Text(t.value.toUpperCase()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<CurrencyCode>(
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: openingCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n.t('Opening Balance', 'Nyitó egyenleg'),
                    ),
                  ),
                  if (hasInterest) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.t('Annual Interest Rate %', 'Éves kamat %'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<Compounding>(
                      initialValue: compounding,
                      decoration: InputDecoration(
                        labelText: l10n.t('Compounding', 'Tőkésítés'),
                      ),
                      items: Compounding.values
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => compounding = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: taxCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.t('Interest Tax %', 'Kamatadó %'),
                      ),
                    ),
                  ],
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
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final openMajor =
                      double.tryParse(openingCtrl.text.replaceAll(',', '.')) ??
                      0;
                  final acc = Account(
                    id: existing?.id ?? const Uuid().v4(),
                    householdId: db.household?.id ?? 'hh-default-001',
                    name: name,
                    type: type,
                    ownership: ownership,
                    ownerId: ownership == AccountOwnership.personal
                        ? (existing?.ownerId ?? meId)
                        : null,
                    currency: currency,
                    openingBalanceMinor:
                        Money.fromMajor(openMajor, currency).amountMinor,
                    openingDate: existing?.openingDate ?? DateTime.now(),
                    interestRatePct: double.tryParse(
                      rateCtrl.text.replaceAll(',', '.'),
                    ),
                    compounding: hasInterest ? compounding : null,
                    interestTaxPct:
                        double.tryParse(taxCtrl.text.replaceAll(',', '.')) ?? 0,
                    updatedAt: DateTime.now(),
                  );
                  db.upsertAccount(acc);
                  Navigator.of(ctx).pop();
                },
                child: Text(l10n.t('Save', 'Mentés')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showValuationDialog(
    BuildContext context,
    AppDatabase db,
    Account account,
  ) async {
    final l10n = AppLocalizations.of(context);
    final currentMinor = db.computeAccountBalanceMinor(account.id);
    final valCtrl = TextEditingController(
      text: Money(currentMinor, account.currency)
          .majorAmount
          .toStringAsFixed(account.currency.displayDecimals),
    );
    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.t(
            'Update Valuation: ${account.name}',
            'Értékbecslés frissítése: ${account.name}',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    '${l10n.t("Current Value", "Aktuális érték")} (${account.currency.code})',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l10n.t('Note', 'Megjegyzés'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.t('Cancel', 'Mégse')),
          ),
          FilledButton(
            onPressed: () {
              final major =
                  double.tryParse(valCtrl.text.replaceAll(',', '.')) ?? 0;
              final snap = AccountValuation(
                id: const Uuid().v4(),
                accountId: account.id,
                valuedOn: DateTime.now(),
                valueMinor:
                    Money.fromMajor(major, account.currency).amountMinor,
                note: noteCtrl.text.trim().isEmpty
                    ? null
                    : noteCtrl.text.trim(),
                createdAt: DateTime.now(),
              );
              db.upsertValuation(snap);
              Navigator.of(ctx).pop();
            },
            child: Text(l10n.t('Save Snapshot', 'Mentés')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final commonAccounts = db.accounts
        .where((a) => !a.archived && a.isCommon)
        .toList();
    final myPersonalAccounts = db.accounts
        .where((a) => !a.archived && !a.isCommon && a.ownerId == meId)
        .toList();

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    // Common-account monthly cash-flow calculations
    final contributionsByUser = <String, int>{
      for (final p in db.profiles) p.id: 0,
    };
    var commonExpensesMinor = 0;
    var commonIncomeMinor = 0;

    for (final t in db.transactions) {
      if (t.occurredOn.isBefore(monthStart)) continue;
      if (t.kind == TxnKind.transfer && t.isContribution) {
        contributionsByUser[t.paidBy] =
            (contributionsByUser[t.paidBy] ?? 0) + t.baseAmountMinor;
      } else if (t.kind == TxnKind.expense && t.paidFromCommon) {
        commonExpensesMinor += t.baseAmountMinor;
      } else if (t.kind == TxnKind.income && t.paidFromCommon) {
        commonIncomeMinor += t.baseAmountMinor;
      }
    }

    final commonOpeningMinor = commonAccounts.fold<int>(
      0,
      (s, a) => s + a.openingBalanceMinor,
    );
    final commonClosingMinor = commonAccounts.fold<int>(
      0,
      (s, a) => s + db.computeAccountBalanceMinor(a.id, currentUserId: meId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.accounts),
        actions: [
          IconButton(
            tooltip: l10n.transfer,
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => TransferSheet.show(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        children: [
          // Section 1: Common Accounts 👥
          Text(
            '👥 ${l10n.commonAccount} (${l10n.sharedBadge})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final a in commonAccounts)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.groups)),
                title: Text(a.name),
                subtitle: Text('${a.type.value.toUpperCase()} • ${a.currency.code}'),
                trailing: Text(
                  Money(
                    db.computeAccountBalanceMinor(a.id, currentUserId: meId),
                    a.currency,
                  ).format(locale: locale, hideAmounts: hideAmounts),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () => _showAccountDialog(
                  context,
                  db,
                  meId,
                  existing: a,
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Common-Account Monthly Cash-Flow Card
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.t(
                            'Common Account Monthly Cash-Flow',
                            'Közös számla havi cash-flow',
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => TransferSheet.show(
                          context,
                          initialToAccountId: commonAccounts.firstOrNull?.id,
                          initialIsContribution: true,
                        ),
                        icon: const Icon(Icons.add_card, size: 18),
                        label: Text(l10n.t('Contribute', 'Befizetés')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t(
                      'Extra contributions show as ahead/behind and do NOT affect Settle-Up.',
                      'A többlet befizetés előnyként/elmaradásként látszik, az elszámolást NEM módosítja.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 20),
                  for (final p in db.profiles) ...[
                    Builder(
                      builder: (context) {
                        final actual = contributionsByUser[p.id] ?? 0;
                        final agreed = p.monthlyCommonContributionMinor ?? 0;
                        final diff = actual - agreed;
                        final statusLabel = diff >= 0
                            ? l10n.t(
                                'Ahead by ${Money(diff).format(locale: locale, hideAmounts: hideAmounts)}',
                                'Előnyben: ${Money(diff).format(locale: locale, hideAmounts: hideAmounts)}',
                              )
                            : l10n.t(
                                'Behind by ${Money(diff.abs()).format(locale: locale, hideAmounts: hideAmounts)}',
                                'Elmaradás: ${Money(diff.abs()).format(locale: locale, hideAmounts: hideAmounts)}',
                              );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${p.displayName}: ${Money(actual).format(locale: locale, hideAmounts: hideAmounts)} / ${Money(agreed).format(locale: locale, hideAmounts: hideAmounts)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  statusLabel,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.t('Common Expenses', 'Közös kiadások')),
                      Text(
                        '-${Money(commonExpensesMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.t('Common Income', 'Közös bevételek')),
                      Text(
                        '+${Money(commonIncomeMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.t(
                          'Opening → Live Closing',
                          'Nyitó → Aktuális záró egyenleg',
                        ),
                      ),
                      Text(
                        '${Money(commonOpeningMinor).format(locale: locale, hideAmounts: hideAmounts)} → ${Money(commonClosingMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 2: My Personal Accounts 🔒
          Text(
            '🔒 ${l10n.personalAccount} (${l10n.privateBadge})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            l10n.t(
              'Strictly private to you. Your partner cannot see these accounts or their balances.',
              'Szigorúan privát. A partnered nem látja ezeket a számlákat és az egyenlegüket.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final a in myPersonalAccounts)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(switch (a.type) {
                    AccountType.cash => Icons.payments_outlined,
                    AccountType.bank => Icons.credit_card,
                    AccountType.savings => Icons.savings_outlined,
                    AccountType.investment => Icons.trending_up,
                    AccountType.deposit => Icons.lock_clock_outlined,
                  }),
                ),
                title: Text(a.name),
                subtitle: Text(
                  [
                    a.type.value.toUpperCase(),
                    a.currency.code,
                    if (a.interestRatePct != null) '${a.interestRatePct}% APY',
                  ].join(' • '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (a.type == AccountType.investment)
                      IconButton(
                        tooltip: l10n.t(
                          'Update Valuation',
                          'Értékbecslés frissítése',
                        ),
                        icon: const Icon(Icons.candlestick_chart_outlined),
                        onPressed: () => _showValuationDialog(context, db, a),
                      ),
                    Text(
                      Money(
                        db.computeAccountBalanceMinor(
                          a.id,
                          currentUserId: meId,
                        ),
                        a.currency,
                      ).format(locale: locale, hideAmounts: hideAmounts),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                onTap: () => _showAccountDialog(
                  context,
                  db,
                  meId,
                  existing: a,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAccountDialog(context, db, meId),
        icon: const Icon(Icons.add),
        label: Text(l10n.t('Add Account', 'Új számla')),
      ),
    );
  }
}
