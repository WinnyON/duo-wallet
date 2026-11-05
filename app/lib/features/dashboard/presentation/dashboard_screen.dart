import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/auth/backend_session.dart';
import '../../../core/auth/cloud_status.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/balance.dart';
import '../../../core/domain/budget_summary.dart';
import '../../../core/domain/insights.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/money.dart';
import '../../../router.dart';
import '../../../theme.dart';
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
    final duo = context.duo;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final prevMonthStart = DateTime(now.year, now.month - 1, 1);

    final monthTxns = db.transactions
        .where((t) =>
            t.deletedAt == null &&
            !t.occurredOn.isBefore(monthStart) &&
            t.occurredOn.isBefore(DateTime(now.year, now.month + 1)))
        .toList();

    final prevMonthTxns = db.transactions
        .where(
          (t) =>
              t.deletedAt == null &&
              !t.occurredOn.isBefore(prevMonthStart) &&
              t.occurredOn.isBefore(monthStart),
        )
        .toList();

    final monthTogetherMinor = monthTxns.fold<int>(
      0,
      (s, t) => s + amountFor(t, ExpenseView.together, meId),
    );
    final prevTogetherMinor = prevMonthTxns.fold<int>(
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

    // Compute 6-month history for the hero mini bar chart
    final sixMonths = <({String label, int amountMinor, bool isCurrent})>[];
    for (var offset = 5; offset >= 0; offset--) {
      final mDate = DateTime(now.year, now.month - offset, 1);
      final mEnd = DateTime(now.year, now.month - offset + 1, 1);
      final mTotal = db.transactions
          .where(
            (t) =>
                t.deletedAt == null &&
                !t.occurredOn.isBefore(mDate) &&
                t.occurredOn.isBefore(mEnd),
          )
          .fold<int>(0, (s, t) => s + amountFor(t, ExpenseView.together, meId));

      final shortMonth = DateFormat('MMM', locale).format(mDate);
      sixMonths.add((
        label: shortMonth,
        amountMinor: mTotal,
        isCurrent: offset == 0,
      ));
    }

    final baselinePrev = prevTogetherMinor;
    final deltaPct = baselinePrev > 0
        ? ((monthTogetherMinor - baselinePrev) / baselinePrev * 100)
        : 0.0;
    final deltaSign = deltaPct >= 0 ? '+' : '';
    final deltaLabel = baselinePrev > 0
        ? '$deltaSign${deltaPct.toStringAsFixed(1)}%'
        : l10n.t('No comparison', 'Nincs összehasonlítás');

    final settleUp = computeSettleUpBalance(
      meId: meId,
      partnerId: partnerId,
      transactions: db.transactions,
      settlements: db.settlements,
    );

    final meProfile = db.findProfile(meId);
    final meName = meProfile?.displayName ?? 'Sam';
    final partnerName = db.findProfile(partnerId)?.displayName ?? 'Anna';

    // Visible accounts: only Common + My Personal accounts
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

    final visibleGoals =
        db.goals.where((g) => g.isShared || g.ownerId == meId).toList();

    final insights = generateInsights(
      meId: meId,
      transactions: db.transactions,
      categories: db.categories,
      budgets: visibleBudgets,
      recurringRules: db.recurringRules,
      goals: visibleGoals,
      now: now,
    );

    final formattedDate = DateFormat('EEE, d MMM y', locale).format(now);

    return Scaffold(
      floatingActionButton: Pressable(
        child: FloatingActionButton.extended(
          onPressed: () => QuickAddTransactionSheet.show(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.quickAdd),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          children: [
            // Greeting Header
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  DuoCircleButton(
                    tooltip: l10n.t('Menu', 'Menü'),
                    icon: Icons.menu_rounded,
                    onTap: () => AppShell.openDrawer(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$formattedDate • ${l10n.appName}',
                          style: textTheme.labelMedium?.copyWith(
                            color: duo.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.t('Hi, $meName', 'Szia, $meName'),
                          style: textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DuoCircleButton(
                    tooltip: l10n.t(
                      'Hide / Show Amounts',
                      'Összegek elrejtése / mutatása',
                    ),
                    icon: hideAmounts
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    onTap: () {
                      ref.read(hideAmountsProvider.notifier).state =
                          !hideAmounts;
                    },
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => context.push('/auth'),
                    child: Tooltip(
                      message: l10n.t(
                        'Switch User / Profile',
                        'Profil / Felhasználó váltás',
                      ),
                      child: UserAvatar(
                        avatarType: meProfile?.avatarType,
                        avatarUrl: meProfile?.avatarUrl,
                        name: meName,
                        size: 38,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (ref.watch(productionModeProvider))
              const CloudStatusCard(compact: true)
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                    l10n.t(
                        'Demo · temporary data. Closing the app resets changes.',
                        'Demó · ideiglenes adatok. Bezáráskor a módosítások elvesznek.'),
                    style: textTheme.bodySmall),
              ),
            // 1. Hero Spend Card (Together this month + 6-month mini bar chart + My Total / Individual well)
            DuoCard(
              onTap: () => context.go('/transactions'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.viewTogether} • ${l10n.t('This month', 'Ebben a hónapban')}',
                    style: textTheme.labelLarge?.copyWith(
                        color: duo.muted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      baselinePrev > 0
                          ? l10n.t('$deltaLabel vs last month',
                              '$deltaLabel az előző hónaphoz képest')
                          : l10n.t('No previous month to compare',
                              'Nincs összehasonlítható előző hónap'),
                      style: textTheme.bodySmall),
                  const SizedBox(height: 10),
                  DuoAmount(
                    money: Money(monthTogetherMinor),
                    locale: locale,
                    hideAmounts: hideAmounts,
                    animate: true,
                    fontSize: 42,
                  ),
                  const SizedBox(height: 18),
                  _HeroMiniBarChart(
                    months: sixMonths,
                    locale: locale,
                    hideAmounts: hideAmounts,
                  ),
                  const SizedBox(height: 16),
                  DuoWell(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 15,
                                    color: duo.icon,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      l10n.viewMyTotal,
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              DuoAmount(
                                money: Money(monthMyTotalMinor),
                                locale: locale,
                                hideAmounts: hideAmounts,
                                fontSize: 20,
                              ),
                            ],
                          ),
                        ),
                        VerticalDivider(
                          width: 24,
                          thickness: 1,
                          color: duo.hairline,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lock_outline_rounded,
                                    size: 14,
                                    color: duo.muted,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      l10n.viewIndividual,
                                      style: textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              DuoAmount(
                                money: Money(monthIndividualMinor),
                                locale: locale,
                                hideAmounts: hideAmounts,
                                fontSize: 20,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Settle-Up Strip (Deep Forest Pine hero surface when someone owes)
            DuoCard(
              isHero: settleUp.someoneOwes,
              onTap: () => context.go('/settle-up'),
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: settleUp.someoneOwes
                          ? duo.onHeroSurface.withValues(alpha: 0.14)
                          : duo.well,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      !settleUp.someoneOwes
                          ? Icons.check_circle_outline_rounded
                          : Icons.sync_alt_rounded,
                      size: 22,
                      color:
                          settleUp.someoneOwes ? duo.onHeroSurface : duo.icon,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          !settleUp.someoneOwes
                              ? l10n.t('All settled up!', 'Minden elszámolva!')
                              : settleUp.partnerOwesMe
                                  ? l10n.t(
                                      '$partnerName owes $meName',
                                      '$partnerName tartozik $meName részére:',
                                    )
                                  : l10n.t(
                                      '$meName owes $partnerName',
                                      '$meName tartozik $partnerName részére:',
                                    ),
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: settleUp.someoneOwes
                                ? duo.onHeroSurface
                                : scheme.onSurface,
                          ),
                        ),
                        if (settleUp.someoneOwes)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                                Money(settleUp.absoluteOwedMinor).format(
                                    locale: locale, hideAmounts: hideAmounts),
                                style: textTheme.titleLarge
                                    ?.copyWith(color: duo.onHeroSurface)),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.t(
                            'Common-account expenses & contributions create no debt',
                            'A közös számlás kiadások és befizetések nem hoznak létre tartozást',
                          ),
                          style: textTheme.bodySmall?.copyWith(
                            color: settleUp.someoneOwes
                                ? duo.onHeroSurface.withValues(alpha: 0.76)
                                : duo.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.chevron_right,
                      color:
                          settleUp.someoneOwes ? duo.onHeroSurface : duo.icon),
                ],
              ),
            ),

            // 4. Accounts Summary (My personal + Common)
            DuoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuoSectionHeader(
                    title: l10n.accounts,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Pressable(
                          onTap: () => TransferSheet.show(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: duo.positive.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.swap_horiz_rounded,
                                    size: 15, color: duo.positive),
                                const SizedBox(width: 4),
                                Text(
                                  l10n.transfer,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: duo.positive,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Pressable(
                          onTap: () => context.go('/accounts'),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: duo.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0;
                      i < math.min(3, visibleAccounts.length);
                      i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Builder(
                      builder: (context) {
                        final acc = visibleAccounts[i];
                        final balMinor = db.computeAccountBalanceMinor(
                          acc.id,
                          currentUserId: meId,
                        );
                        return ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          onTap: () => context.push('/accounts/${acc.id}'),
                          leading: Icon(
                            acc.isCommon
                                ? Icons.account_balance_outlined
                                : switch (acc.type) {
                                    AccountType.cash => Icons.payments_outlined,
                                    AccountType.bank =>
                                      Icons.credit_card_outlined,
                                    AccountType.savings =>
                                      Icons.savings_outlined,
                                    AccountType.investment => Icons.trending_up,
                                    AccountType.deposit =>
                                      Icons.lock_clock_outlined,
                                  },
                            size: 22,
                            color: acc.isCommon ? duo.positive : duo.icon,
                          ),
                          title: Text(
                            acc.name,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    acc.isCommon
                                        ? l10n.commonAccount
                                        : l10n.personalAccount,
                                    style: textTheme.bodySmall),
                                const SizedBox(height: 4),
                                DuoAmount(
                                    money: Money(balMinor, acc.currency),
                                    locale: locale,
                                    hideAmounts: hideAmounts,
                                    fontSize: 18),
                              ]),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            DuoCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  DuoSectionHeader(
                      title: l10n.t(
                          'Recent transactions', 'Legutóbbi tranzakciók'),
                      trailingLabel: l10n.t('View all', 'Összes'),
                      onTap: () => context.go('/transactions')),
                  for (final transaction in db.transactions
                      .where((t) =>
                          t.visibility == VisibilityLevel.shared ||
                          t.createdBy == meId)
                      .take(4))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () =>
                            showTransactionDetails(context, transaction),
                        title: Text(transaction.merchant ??
                            db
                                .findCategory(transaction.categoryId ?? '')
                                ?.localizedName(locale) ??
                            l10n.t('Transaction', 'Tranzakció')),
                        subtitle: Text(
                            '${DateFormat.yMMMd(locale).format(transaction.occurredOn)} • ${Money(transaction.amountMinor, transaction.currency).format(locale: locale, hideAmounts: hideAmounts)}')),
                ])),

            // 5. Active Budgets Progress
            if (visibleBudgets.isNotEmpty)
              DuoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DuoSectionHeader(
                      title: l10n.budgets,
                      trailingLabel: l10n.t('Manage', 'Kezelés'),
                      onTap: () => context.push('/budgets'),
                    ),
                    const SizedBox(height: 6),
                    for (final b in visibleBudgets.take(3)) ...[
                      Builder(
                        builder: (context) {
                          final summary = budgetSummary(
                              budget: b,
                              transactions: db.transactions,
                              month: now,
                              meId: meId);
                          final spent = summary.spentMinor;
                          final ratio = summary.effectiveLimitMinor > 0
                              ? (spent / summary.effectiveLimitMinor)
                                  .clamp(0.0, 1.0)
                              : 0.0;
                          final barColor = ratio >= 1.0
                              ? duo.negative
                              : ratio >= 0.8
                                  ? duo.warning
                                  : duo.positive;
                          final label = b.categoryId != null
                              ? (db
                                      .findCategory(b.categoryId!)
                                      ?.localizedName(locale) ??
                                  l10n.t("Category budget", "Kategóriakeret"))
                              : b.scope == Scope.together
                                  ? l10n.viewTogether
                                  : l10n.viewMyTotal;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${Money(spent).format(locale: locale, hideAmounts: hideAmounts)} / ${Money(summary.effectiveLimitMinor).format(locale: locale, hideAmounts: hideAmounts)}',
                                      style: textTheme.bodySmall?.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                DuoProgressBar(
                                  value: ratio,
                                  color: barColor,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),

            // 6. Goals Summary (with mini DuoGauge)
            if (visibleGoals.isNotEmpty)
              DuoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DuoSectionHeader(
                      title: l10n.goals,
                      trailingLabel: l10n.t('View All', 'Összes'),
                      onTap: () => context.push('/goals'),
                    ),
                    const SizedBox(height: 8),
                    for (final g in visibleGoals.take(3))
                      Builder(
                        builder: (context) {
                          final ratio = g.targetAmountMinor > 0
                              ? (g.savedAmountMinor / g.targetAmountMinor)
                                  .clamp(0.0, 1.0)
                              : 0.0;
                          final pct = (ratio * 100).round();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: DuoWell(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  DuoGauge(
                                    progress: ratio,
                                    size: 52,
                                    strokeWidth: 5.5,
                                    trackColor: scheme.surface,
                                    child: Text(
                                      '$pct%',
                                      style: textTheme.labelSmall?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          g.name,
                                          style: textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${Money(g.savedAmountMinor, g.currency).format(locale: locale, hideAmounts: hideAmounts)} / ${Money(g.targetAmountMinor, g.currency).format(locale: locale, hideAmounts: hideAmounts)}',
                                          style: textTheme.bodySmall?.copyWith(
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),

            // 7. Insights Card
            if (insights.isNotEmpty)
              DuoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DuoSectionHeader(
                      title: l10n.t('Insights', 'Elemzések és tippek'),
                    ),
                    const SizedBox(height: 8),
                    for (final ins in insights)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: DuoIconBox(
                          switch (ins.severity) {
                            InsightSeverity.warning =>
                              Icons.warning_amber_rounded,
                            InsightSeverity.success =>
                              Icons.check_circle_outline,
                            InsightSeverity.info => Icons.lightbulb_outline,
                          },
                          size: 24,
                          color: switch (ins.severity) {
                            InsightSeverity.warning => duo.warning,
                            InsightSeverity.success => duo.positive,
                            InsightSeverity.info => duo.info,
                          },
                        ),
                        title: Text(ins.localizedTitle(locale)),
                      ),
                  ],
                ),
              ),

            // 8. Recent Shared Activity Feed
            DuoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DuoSectionHeader(
                    title: l10n.activity,
                    trailingLabel: l10n.t('More', 'Továbbiak'),
                    onTap: () => context.push('/activity'),
                  ),
                  const SizedBox(height: 6),
                  for (final act in db.activities.take(4))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const MerchantAvatar(
                        name: 'Act',
                        icon: Icons.schedule_rounded,
                      ),
                      title: Text(activityDisplaySummary(act,
                          locale: locale, hideAmounts: hideAmounts)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMiniBarChart extends StatelessWidget {
  const _HeroMiniBarChart({
    required this.months,
    required this.locale,
    required this.hideAmounts,
  });

  final List<({String label, int amountMinor, bool isCurrent})> months;
  final String locale;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final maxMinor = months.fold<int>(
      1,
      (m, e) => math.max(m, e.amountMinor),
    );

    return SizedBox(
      height: 112,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < months.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  final item = months[i];
                  final ratio = (item.amountMinor / maxMinor).clamp(0.0, 1.0);
                  final barHeight = 56.0 * ratio;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        curve: Motion.easeOut,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: item.isCurrent
                              ? scheme.primary
                              : duo.positive.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          fontSize: 12,
                          fontWeight: item.isCurrent
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: item.isCurrent ? scheme.primary : duo.muted,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
