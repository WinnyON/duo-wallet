import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/balance.dart';
import '../../../core/domain/insights.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../transactions/presentation/transactions_screen.dart';
import '../../transfers/presentation/transfer_sheet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dbTickProvider);
    final l10n = AppLocalizations.of(context);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final partnerId = ref.watch(partnerUserIdProvider);
    final locale = ref.watch(appLocaleProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final monthTxns = db.transactions
        .where((t) => !t.occurredOn.isBefore(monthStart))
        .toList();

    final monthTogetherMinor = monthTxns.fold<int>(
      0,
      (s, t) => s + amountFor(t, ExpenseView.together, meId),
    );
    final monthMyTotalMinor = monthTxns.fold<int>(
      0,
      (s, t) => s + amountFor(t, ExpenseView.myTotal, meId),
    );
    final monthIndividualMinor = monthTxns.fold<int>(
      0,
      (s, t) => s + amountFor(t, ExpenseView.individual, meId),
    );

    final settleUp = computeSettleUpBalance(
      meId: meId,
      partnerId: partnerId,
      transactions: db.transactions,
      settlements: db.settlements,
    );

    final meName = db.findProfile(meId)?.displayName ?? 'Sam';
    final partnerName = db.findProfile(partnerId)?.displayName ?? 'Anna';

    // Visible accounts: only Common + My Personal accounts (partner's personal accounts strictly hidden)
    final visibleAccounts = db.accounts
        .where((a) => !a.archived && (a.isCommon || a.ownerId == meId))
        .toList();

    final visibleBudgets = db.budgets
        .where(
          (b) =>
              b.scope == Scope.together ||
              (b.scope == Scope.individual && b.ownerId == meId),
        )
        .toList();

    final visibleGoals = db.goals
        .where((g) => g.isShared || g.ownerId == meId)
        .toList();

    final insights = generateInsights(
      meId: meId,
      transactions: db.transactions,
      categories: db.categories,
      budgets: visibleBudgets,
      recurringRules: db.recurringRules,
      goals: visibleGoals,
      now: now,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${l10n.appName} • $meName'),
        actions: [
          IconButton(
            tooltip: l10n.t('Hide / Show Amounts', 'Összegek elrejtése / mutatása'),
            icon: Icon(
              hideAmounts ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
            onPressed: () {
              ref.read(hideAmountsProvider.notifier).state = !hideAmounts;
            },
          ),
          IconButton(
            tooltip: l10n.t('Switch User / Profile', 'Profil / Felhasználó váltás'),
            icon: const Icon(Icons.switch_account_outlined),
            onPressed: () => context.go('/auth'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
        children: [
          // 1. Month Spend Overview (My Total, Together, Individual)
          Row(
            children: [
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go('/transactions'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '👥 ${l10n.viewTogether}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            Money(monthTogetherMinor).format(
                              locale: locale,
                              hideAmounts: hideAmounts,
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.t('This month', 'Ebben a hónapban'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go('/transactions'),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🔒 ${l10n.viewMyTotal}',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            Money(monthMyTotalMinor).format(
                              locale: locale,
                              hideAmounts: hideAmounts,
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${l10n.viewIndividual}: ${Money(monthIndividualMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 2. Settle-Up Balance Card
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.handshake_outlined),
              title: Text(
                !settleUp.someoneOwes
                    ? l10n.t('All settled up!', 'Minden elszámolva!')
                    : settleUp.partnerOwesMe
                    ? l10n.t(
                        '$partnerName owes $meName ${Money(settleUp.absoluteOwedMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                        '$partnerName tartozik $meName részére: ${Money(settleUp.absoluteOwedMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                      )
                    : l10n.t(
                        '$meName owes $partnerName ${Money(settleUp.absoluteOwedMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                        '$meName tartozik $partnerName részére: ${Money(settleUp.absoluteOwedMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                      ),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                l10n.t(
                  'Common-account expenses & contributions create no debt',
                  'A közös számlás kiadások és befizetések nem hoznak létre tartozást',
                ),
              ),
              trailing: FilledButton.tonal(
                onPressed: () => context.go('/settle-up'),
                child: Text(l10n.settleUp),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. Accounts Summary (My personal + Common)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.accounts,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => TransferSheet.show(context),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(l10n.transfer),
                          ),
                          TextButton(
                            onPressed: () => context.go('/accounts'),
                            child: Text(l10n.t('Details', 'Részletek')),
                          ),
                        ],
                      ),
                    ],
                  ),
                  for (final acc in visibleAccounts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Text(acc.isCommon ? '👥' : '🔒'),
                      title: Text(acc.name),
                      subtitle: Text(
                        acc.isCommon
                            ? l10n.commonAccount
                            : '${l10n.personalAccount} (${l10n.privateBadge})',
                      ),
                      trailing: Text(
                        Money(
                          db.computeAccountBalanceMinor(
                            acc.id,
                            currentUserId: meId,
                          ),
                          acc.currency,
                        ).format(locale: locale, hideAmounts: hideAmounts),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 4. Active Budgets Progress
          if (visibleBudgets.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.budgets,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => context.go('/budgets'),
                          child: Text(l10n.t('Manage', 'Kezelés')),
                        ),
                      ],
                    ),
                    for (final b in visibleBudgets) ...[
                      Builder(
                        builder: (context) {
                          final spent = b.scope == Scope.together
                              ? monthTogetherMinor
                              : monthMyTotalMinor;
                          final ratio = b.amountMinor > 0
                              ? (spent / b.amountMinor).clamp(0.0, 1.0)
                              : 0.0;
                          final label = b.scope == Scope.together
                              ? '👥 ${l10n.viewTogether}'
                              : '🔒 ${l10n.viewMyTotal}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(label),
                                    Text(
                                      '${Money(spent).format(locale: locale, hideAmounts: hideAmounts)} / ${Money(b.amountMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(value: ratio),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // 5. Insights Cards
          if (insights.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('Insights', 'Elemzések és tippek'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final ins in insights)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (ins.severity) {
                            InsightSeverity.warning => Icons.warning_amber_rounded,
                            InsightSeverity.success => Icons.check_circle_outline,
                            InsightSeverity.info => Icons.lightbulb_outline,
                          },
                          color: switch (ins.severity) {
                            InsightSeverity.warning => Colors.orange,
                            InsightSeverity.success => Colors.teal,
                            InsightSeverity.info => null,
                          },
                        ),
                        title: Text(ins.localizedTitle(locale)),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // 6. Goals Summary
          if (visibleGoals.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.goals,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        TextButton(
                          onPressed: () => context.go('/goals'),
                          child: Text(l10n.t('View All', 'Összes')),
                        ),
                      ],
                    ),
                    for (final g in visibleGoals)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Text(g.isShared ? '👥' : '🔒'),
                        title: Text(g.name),
                        subtitle: LinearProgressIndicator(
                          value: g.targetAmountMinor > 0
                              ? (g.savedAmountMinor / g.targetAmountMinor)
                                    .clamp(0.0, 1.0)
                              : 0.0,
                        ),
                        trailing: Text(
                          '${Money(g.savedAmountMinor, g.currency).format(locale: locale, hideAmounts: hideAmounts)} / ${Money(g.targetAmountMinor, g.currency).format(locale: locale, hideAmounts: hideAmounts)}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // 7. Recent Shared Activity Feed
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '👥 ${l10n.activity}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      TextButton(
                        onPressed: () => context.go('/activity'),
                        child: Text(l10n.t('More', 'Továbbiak')),
                      ),
                    ],
                  ),
                  for (final act in db.activities.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bolt_outlined, size: 20),
                      title: Text(act.localizedSummary(locale)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => QuickAddTransactionSheet.show(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.quickAdd),
      ),
    );
  }
}
