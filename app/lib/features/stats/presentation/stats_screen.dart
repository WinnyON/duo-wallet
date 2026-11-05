import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/insights.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../theme.dart';
import '../../../router.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  ExpenseView _view = ExpenseView.together;

  Color _parseColor(String hex, Color fallback) {
    final cleaned = hex.replaceFirst('#', '');
    final val = int.tryParse('FF$cleaned', radix: 16);
    return val != null ? Color(val) : fallback;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dbTickProvider);
    final db = ref.watch(appDatabaseProvider);
    final meId = ref.watch(currentUserIdProvider);
    final hideAmounts = ref.watch(hideAmountsProvider);
    final l10n = AppLocalizations.of(context);
    final localeStr = l10n.locale.languageCode;
    final now = DateTime.now();
    final duo = context.duo;
    final textTheme = Theme.of(context).textTheme;

    final rangeStart = DateTime(now.year, now.month - 5);
    final rangeEnd = DateTime(now.year, now.month + 1);
    final txns = db.transactions
        .where((t) =>
            !t.occurredOn.isBefore(rangeStart) &&
            t.occurredOn.isBefore(rangeEnd))
        .toList();
    final categoryTotals = <String, int>{};
    final merchantTotals = <String, int>{};
    var totalSpendMinor = 0;
    var totalIncomeMinor = 0;
    var myShareTogetherMinor = 0;
    var myIndividualMinor = 0;

    int incomeFor(Txn t) => switch (_view) {
          ExpenseView.together => t.paidFromCommon || t.scope == Scope.together
              ? t.baseAmountMinor
              : 0,
          ExpenseView.individual => !t.paidFromCommon &&
                  t.scope == Scope.individual &&
                  t.createdBy == meId
              ? t.baseAmountMinor
              : 0,
          ExpenseView.myTotal => !t.paidFromCommon &&
                  t.scope == Scope.individual &&
                  t.createdBy == meId
              ? t.baseAmountMinor
              : (t.baseShares[meId] ?? 0),
        };

    for (final t in txns) {
      if (t.deletedAt != null) continue;
      if (t.kind == TxnKind.expense) {
        final amt = amountFor(t, _view, meId);
        if (amt > 0) {
          totalSpendMinor += amt;
          final catKey = t.categoryId ?? 'uncategorized';
          categoryTotals[catKey] = (categoryTotals[catKey] ?? 0) + amt;
          final merchant = (t.merchant ?? '').trim();
          if (merchant.isNotEmpty) {
            merchantTotals[merchant] = (merchantTotals[merchant] ?? 0) + amt;
          }
        }
        if (t.scope == Scope.together) {
          myShareTogetherMinor += t.baseShares[meId] ?? 0;
        } else if (t.scope == Scope.individual && t.createdBy == meId) {
          myIndividualMinor += t.baseAmountMinor;
        }
      } else if (t.kind == TxnKind.income) {
        totalIncomeMinor += incomeFor(t);
      }
    }

    // Compute 6-month trend points (Expenses & Income) for continuous trading chart
    final trendMonths = <({
      String label,
      int amountMinor,
      int incomeMinor,
      bool isCurrent,
    })>[];
    for (var offset = 5; offset >= 0; offset--) {
      final mDate = DateTime(now.year, now.month - offset, 1);
      final mEnd = DateTime(now.year, now.month - offset + 1, 1);
      final mTotal = txns
          .where(
            (t) =>
                t.deletedAt == null &&
                t.kind == TxnKind.expense &&
                !t.occurredOn.isBefore(mDate) &&
                t.occurredOn.isBefore(mEnd),
          )
          .fold<int>(0, (s, t) => s + amountFor(t, _view, meId));
      final mIncome = txns
          .where(
            (t) =>
                t.deletedAt == null &&
                t.kind == TxnKind.income &&
                !t.occurredOn.isBefore(mDate) &&
                t.occurredOn.isBefore(mEnd),
          )
          .fold<int>(0, (s, t) => s + incomeFor(t));
      trendMonths.add((
        label: DateFormat('MMM', localeStr).format(mDate),
        amountMinor: mTotal,
        incomeMinor: mIncome,
        isCurrent: offset == 0,
      ));
    }

    final savingsRatePct = totalIncomeMinor > 0
        ? (((totalIncomeMinor - totalSpendMinor) / totalIncomeMinor) * 100)
            .clamp(-100.0, 100.0)
        : 0.0;

    final sortedCats = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topMerchants = merchantTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final myCombinedMinor = myShareTogetherMinor + myIndividualMinor;
    final togetherPct = myCombinedMinor > 0
        ? ((myShareTogetherMinor / myCombinedMinor) * 100).round()
        : 0;
    final individualPct = myCombinedMinor > 0 ? 100 - togetherPct : 0;

    final insights = generateInsights(
      meId: meId,
      transactions: txns,
      categories: db.categories,
      budgets: db.budgets,
      recurringRules: db.recurringRules.where(
        (r) => r.visibility == VisibilityLevel.shared || r.createdBy == meId,
      ),
      goals: db.goals.where((g) => g.isShared || g.ownerId == meId),
      now: now,
    );

    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.menu),
              tooltip: l10n.t("Menu", "Menü"),
              onPressed: () => AppShell.openDrawer(context)),
          title: Text(l10n.stats)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
              '${DateFormat.yMMMd(localeStr).format(rangeStart)} – ${DateFormat.yMMMd(localeStr).format(rangeEnd.subtract(const Duration(days: 1)))} • HUF'),
          if (_view == ExpenseView.myTotal &&
              txns.any((t) =>
                  t.kind == TxnKind.income &&
                  (t.paidFromCommon || t.scope == Scope.together) &&
                  !t.baseShares.containsKey(meId)))
            Text(l10n.t(
                'Shared income without a recorded personal share is excluded from personal income.',
                'A rögzített saját részesedés nélküli közös bevétel nem szerepel a saját bevételben.')),
          SegmentedButton<ExpenseView>(
            segments: [
              ButtonSegment(
                value: ExpenseView.together,
                label: Text(l10n.viewTogether),
              ),
              ButtonSegment(
                value: ExpenseView.myTotal,
                label: Text(l10n.viewMyTotal),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: 10),

          // 1. Spend Overview + Continuous Trading Line Chart + DuoWell Summary Metrics
          DuoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.t(
                          'Monthly Cash-Flow Trend',
                          'Havi pénzmozgás trend',
                        ),
                        style: textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    DuoPill(
                      totalIncomeMinor > 0
                          ? '${savingsRatePct >= 0 ? "+" : ""}${savingsRatePct.toStringAsFixed(1)}%'
                          : '—',
                      solid: savingsRatePct >= 0,
                      color: savingsRatePct >= 0 ? duo.positive : duo.negative,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DuoAmount(
                  money: Money(totalSpendMinor, CurrencyCode.huf),
                  locale: localeStr,
                  hideAmounts: hideAmounts,
                  animate: true,
                  fontSize: 36,
                ),
                const SizedBox(height: 14),
                _StatsTradingLineChart(
                  months: trendMonths,
                  locale: localeStr,
                  hideAmounts: hideAmounts,
                  expenseLabel: l10n.expense,
                  incomeLabel: l10n.income,
                ),
                const SizedBox(height: 16),
                DuoWell(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: _statColumn(
                          context,
                          l10n.expense,
                          Money(totalSpendMinor, CurrencyCode.huf)
                              .formatCompact(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          duo.negative,
                        ),
                      ),
                      Expanded(
                        child: _statColumn(
                          context,
                          l10n.income,
                          Money(totalIncomeMinor, CurrencyCode.huf)
                              .formatCompact(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          duo.positive,
                        ),
                      ),
                      Expanded(
                        child: _statColumn(
                          context,
                          l10n.t('Savings Rate', 'Megtakarítási ráta'),
                          totalIncomeMinor > 0
                              ? '${savingsRatePct.toStringAsFixed(1)}%'
                              : '—',
                          savingsRatePct >= 0 ? duo.positive : duo.negative,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Category Breakdown & Donut Chart with Center Total
          DuoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('Category Breakdown', 'Kategória megoszlás'),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (sortedCats.isEmpty)
                  Text(l10n.t(
                      'No expenses recorded.', 'Nincs rögzített kiadás.'))
                else ...[
                  SizedBox(
                    height: 196,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            centerSpaceRadius: 58,
                            sectionsSpace: 3,
                            sections: sortedCats.map((entry) {
                              final cat = db.findCategory(entry.key);
                              final color = cat != null
                                  ? _parseColor(cat.color, duo.muted)
                                  : duo.muted;
                              return PieChartSectionData(
                                value: entry.value.toDouble(),
                                color: color,
                                radius: 34,
                                title: '',
                                titleStyle: textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            }).toList(),
                          ),
                          swapAnimationDuration:
                              MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                        ),
                        SizedBox(
                          width: 104,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                l10n.t('Total', 'Összesen'),
                                style: textTheme.labelSmall?.copyWith(
                                  color: duo.muted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              DuoAmount(
                                money: Money(totalSpendMinor, CurrencyCode.huf),
                                locale: localeStr,
                                hideAmounts: hideAmounts,
                                compact: true,
                                fontSize: 18,
                                alignment: Alignment.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  DuoWell(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Column(
                      children: [
                        for (var i = 0; i < sortedCats.length; i++) ...[
                          if (i > 0) const Divider(height: 12),
                          Builder(
                            builder: (context) {
                              final entry = sortedCats[i];
                              final cat = db.findCategory(entry.key);
                              final name = cat != null
                                  ? cat.localizedName(localeStr)
                                  : l10n.t('Uncategorized', 'Kategória nélkül');
                              final color = cat != null
                                  ? _parseColor(cat.color, duo.muted)
                                  : duo.muted;
                              final pct = totalSpendMinor > 0
                                  ? (entry.value / totalSpendMinor * 100)
                                      .round()
                                  : 0;
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(name,
                                              style: textTheme.bodyMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w500))),
                                    ]),
                                    Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          DuoBadge('$pct%'),
                                          Text(
                                              Money(entry.value,
                                                      CurrencyCode.huf)
                                                  .format(
                                                      locale: localeStr,
                                                      hideAmounts: hideAmounts),
                                              style: textTheme.titleSmall
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                        ]),
                                  ]);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 3. Shared vs Personal Ratio (from my visible data only)
          DuoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t(
                    'Shared vs Personal Ratio (My Cost)',
                    'Közös vs. Saját arány (Saját költség)',
                  ),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.viewTogether}: $togetherPct% (${Money(myShareTogetherMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)})  •  '
                  '${l10n.viewIndividual}: $individualPct% (${Money(myIndividualMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)})',
                  style: textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 10),
                DuoProgressBar(
                  value: myCombinedMinor > 0
                      ? myShareTogetherMinor / myCombinedMinor
                      : 0.5,
                ),
              ],
            ),
          ),

          // 4. Top Merchants
          DuoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('Top Merchants', 'Leggyakoribb kereskedők'),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (topMerchants.isEmpty)
                  Text(l10n.t(
                      'No merchant data yet.', 'Még nincs kereskedő adat.'))
                else
                  for (final m in topMerchants.take(5))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: MerchantAvatar(
                        name: m.key,
                        category: 'Shopping',
                      ),
                      title: Text(m.key,
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          Money(m.value, CurrencyCode.huf).format(
                              locale: localeStr, hideAmounts: hideAmounts),
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
              ],
            ),
          ),

          // 5. Active Financial Insights
          DuoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.t('Financial Insights', 'Pénzügyi elemzések'),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (insights.isEmpty)
                  Text(l10n.t('No active insights.', 'Nincs aktív elemzés.'))
                else
                  for (final item in insights)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: DuoIconBox(
                        switch (item.severity) {
                          InsightSeverity.warning =>
                            Icons.warning_amber_rounded,
                          InsightSeverity.success => Icons.check_circle_outline,
                          InsightSeverity.info => Icons.lightbulb_outline,
                        },
                        size: 24,
                        color: switch (item.severity) {
                          InsightSeverity.warning => duo.warning,
                          InsightSeverity.success => duo.positive,
                          InsightSeverity.info => duo.info,
                        },
                      ),
                      title: Text(item.localizedTitle(localeStr)),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _StatsTradingLineChart extends StatelessWidget {
  const _StatsTradingLineChart({
    required this.months,
    required this.locale,
    required this.hideAmounts,
    required this.expenseLabel,
    required this.incomeLabel,
  });

  final List<
      ({
        String label,
        int amountMinor,
        int incomeMinor,
        bool isCurrent,
      })> months;
  final String locale;
  final bool hideAmounts;
  final String expenseLabel;
  final String incomeLabel;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final textTheme = Theme.of(context).textTheme;
    final maxMinor = months.fold<int>(
      1,
      (m, e) => math.max(m, math.max(e.amountMinor, e.incomeMinor)),
    );
    final maxY = (maxMinor * 1.18).toDouble();

    final expenseSpots = <FlSpot>[
      for (var i = 0; i < months.length; i++)
        FlSpot(i.toDouble(), months[i].amountMinor.toDouble()),
    ];
    final incomeSpots = <FlSpot>[
      for (var i = 0; i < months.length; i++)
        FlSpot(i.toDouble(), months[i].incomeMinor.toDouble()),
    ];

    final expenseColor = duo.negative;
    final incomeColor = duo.positive; // Babu Teal

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _legendItem(textTheme, expenseColor, expenseLabel),
            const SizedBox(width: 16),
            _legendItem(textTheme, incomeColor, incomeLabel),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 184,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (months.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: maxY > 0 ? maxY / 3 : 1,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: duo.hairline,
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: duo.hairline.withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    interval: maxY > 0 ? maxY / 3 : 1,
                    getTitlesWidget: (value, meta) {
                      if (value <= 0 || value >= maxY * 0.98) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          Money(value.round()).formatCompact(
                            locale: locale,
                            hideAmounts: hideAmounts,
                          ),
                          style: textTheme.labelSmall?.copyWith(
                            color: duo.muted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.round();
                      if (idx < 0 || idx >= months.length) {
                        return const SizedBox.shrink();
                      }
                      final item = months[idx];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          item.label,
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: 12,
                            fontWeight: item.isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.isCurrent ? expenseColor : duo.muted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                enabled: !hideAmounts,
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF222222),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final isExpense = spot.barIndex == 0;
                      final label = isExpense ? expenseLabel : incomeLabel;
                      final formatted = Money(spot.y.round()).formatCompact(
                        locale: locale,
                        hideAmounts: hideAmounts,
                      );
                      return LineTooltipItem(
                        '$label: $formatted',
                        TextStyle(
                          color: isExpense
                              ? const Color(0xFFFF5A5F)
                              : const Color(0xFF00A699),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                // 1. Expense continuous curve (Radical Red)
                LineChartBarData(
                  spots: expenseSpots,
                  isCurved: false,
                  curveSmoothness: 0.32,
                  preventCurveOverShooting: true,
                  color: expenseColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: index == months.length - 1 ? 5 : 3.5,
                      color: expenseColor,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        expenseColor.withValues(alpha: 0.26),
                        expenseColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
                // 2. Income continuous curve (Babu Teal)
                LineChartBarData(
                  spots: incomeSpots,
                  isCurved: false,
                  curveSmoothness: 0.32,
                  preventCurveOverShooting: true,
                  color: incomeColor,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: index == months.length - 1 ? 4.5 : 3,
                      color: incomeColor,
                      strokeWidth: 1.8,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        incomeColor.withValues(alpha: 0.16),
                        incomeColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
          ),
        ),
      ],
    );
  }

  Widget _legendItem(TextTheme textTheme, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
