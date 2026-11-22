import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/insights.dart';
import '../../../core/domain/cash_flow.dart';
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
  ReportingRange _range = ReportingRange.allTime;
  int _year = DateTime.now().year, _month = DateTime.now().month;
  bool _bars = false;
  DateTime? _selectedPeriodStart;

  void _openEntries(CashFlowBucket bucket) {
    final end = DateTime(bucket.end.year, bucket.end.month, bucket.end.day - 1);
    context.go(Uri(path: '/transactions', queryParameters: {
      'from': DateFormat('yyyy-MM-dd').format(bucket.start),
      'to': DateFormat('yyyy-MM-dd').format(end),
      'view': _view.name,
      'request': DateTime.now().microsecondsSinceEpoch.toString(),
    }).toString());
  }

  String _bucketLabel(CashFlowBucket bucket, String locale) => switch (_range) {
        ReportingRange.allTime => '${bucket.start.year}',
        ReportingRange.year => DateFormat.yMMMM(locale).format(bucket.start),
        ReportingRange.month => DateFormat.yMMMd(locale).format(bucket.start),
      };

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

    final visible = db.transactions
        .where((t) =>
            t.deletedAt == null &&
            (t.visibility == VisibilityLevel.shared || t.createdBy == meId))
        .toList();
    final recordedYears = {
      now.year,
      _year,
      ...visible.map((t) => t.occurredOn.year)
    }.toList()
      ..sort();
    final years = List.generate(recordedYears.last - recordedYears.first + 1,
        (index) => recordedYears.last - index);
    final buckets = cashFlowBuckets(
        transactions: visible,
        range: _range,
        year: _year,
        month: _month,
        view: _view,
        meId: meId,
        now: now);
    final rangeStart = buckets.first.start, rangeEnd = buckets.last.end;
    final txns = visible
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
        totalIncomeMinor += incomeFor(t, _view, meId);
      }
    }

    final savingsRatePct = totalIncomeMinor > 0
        ? ((totalIncomeMinor - totalSpendMinor) / totalIncomeMinor) * 100
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

    final net = totalIncomeMinor - totalSpendMinor;
    final insights = <InsightItem>[
      if (totalIncomeMinor != 0 || totalSpendMinor != 0)
        InsightItem(
            id: 'period-balance',
            titleEn: net >= 0
                ? 'Income exceeds spending by ${Money(net).format(locale: localeStr, hideAmounts: hideAmounts)} in this period.'
                : 'Spending exceeds income by ${Money(-net).format(locale: localeStr, hideAmounts: hideAmounts)} in this period.',
            titleHu: net >= 0
                ? 'A bevétel ${Money(net).format(locale: localeStr, hideAmounts: hideAmounts)} összeggel meghaladja a kiadást ebben az időszakban.'
                : 'A kiadás ${Money(-net).format(locale: localeStr, hideAmounts: hideAmounts)} összeggel meghaladja a bevételt ebben az időszakban.',
            severity:
                net >= 0 ? InsightSeverity.success : InsightSeverity.warning),
      if (sortedCats.isNotEmpty)
        InsightItem(
            id: 'period-category',
            titleEn:
                '${db.findCategory(sortedCats.first.key)?.nameEn ?? 'Uncategorized'} is the largest expense category in this period.',
            titleHu:
                '${db.findCategory(sortedCats.first.key)?.nameHu ?? 'Kategória nélkül'} a legnagyobb kiadási kategória ebben az időszakban.'),
    ];
    final periodIndex =
        buckets.indexWhere((bucket) => bucket.start == _selectedPeriodStart);
    final pickedIndex = periodIndex < 0 ? null : periodIndex;
    final selected = pickedIndex == null ? null : buckets[pickedIndex];
    final trendTitle = switch (_range) {
      ReportingRange.allTime =>
        l10n.t('Yearly Cash-Flow Trend', 'Éves pénzmozgás trend'),
      ReportingRange.year =>
        l10n.t('Monthly Cash-Flow Trend', 'Havi pénzmozgás trend'),
      ReportingRange.month =>
        l10n.t('Daily Cash-Flow Trend', 'Napi pénzmozgás trend'),
    };

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
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final option in ReportingRange.values)
              ChoiceChip(
                  label: Text(switch (option) {
                    ReportingRange.allTime => l10n.t('All time', 'Összes idő'),
                    ReportingRange.year => l10n.t('Year', 'Év'),
                    ReportingRange.month => l10n.t('Month', 'Hónap'),
                  }),
                  selected: _range == option,
                  onSelected: (_) => setState(() {
                        _range = option;
                        _selectedPeriodStart = null;
                      })),
          ]),
          if (_range != ReportingRange.allTime) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<int>(
                      key: const ValueKey('statistics-year'),
                      initialValue: _year,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: l10n.t('Year', 'Év')),
                      items: years
                          .map((y) =>
                              DropdownMenuItem(value: y, child: Text('$y')))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _year = value;
                            _selectedPeriodStart = null;
                          });
                        }
                      })),
              if (_range == ReportingRange.month)
                SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<int>(
                        key: const ValueKey('statistics-month'),
                        initialValue: _month,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: l10n.t('Month', 'Hónap')),
                        items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                                value: i + 1,
                                child: Text(DateFormat.MMMM(localeStr)
                                    .format(DateTime(2000, i + 1))))),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _month = value;
                              _selectedPeriodStart = null;
                            });
                          }
                        })),
            ]),
          ],
          const SizedBox(height: 12),
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
            onSelectionChanged: (s) => setState(() {
              _view = s.first;
              _selectedPeriodStart = null;
            }),
          ),
          const SizedBox(height: 10),

          // 1. Spend Overview + Continuous Trading Line Chart + DuoWell Summary Metrics
          DuoSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DuoSectionHeader(
                    title: trendTitle,
                    trailing: ToggleButtons(
                        isSelected: [!_bars, _bars],
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.white,
                        fillColor: Theme.of(context).colorScheme.primary,
                        onPressed: (index) =>
                            setState(() => _bars = index == 1),
                        children: [
                          Tooltip(
                              message: l10n.t('Line chart', 'Vonaldiagram'),
                              child: const Icon(Icons.show_chart)),
                          Tooltip(
                              message: l10n.t('Bar chart', 'Oszlopdiagram'),
                              child: const Icon(Icons.bar_chart))
                        ])),
                const SizedBox(height: 8),
                DuoAmount(
                  money: Money(totalSpendMinor, CurrencyCode.huf),
                  locale: localeStr,
                  hideAmounts: hideAmounts,
                  animate: true,
                  fontSize: 36,
                ),
                const SizedBox(height: 14),
                _CashFlowChart(
                    key: ValueKey(
                        'cash-flow-${_range.name}-$_year-$_month-${_view.name}-$_bars'),
                    buckets: buckets,
                    range: _range,
                    bars: _bars,
                    locale: localeStr,
                    hideAmounts: hideAmounts,
                    expenseLabel: l10n.expense,
                    incomeLabel: l10n.income,
                    onSelect: (index) => setState(
                        () => _selectedPeriodStart = buckets[index].start)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(
                      'bucket-selector-${_range.name}-$_year-$_month-${_view.name}-${pickedIndex ?? 'none'}'),
                  initialValue: pickedIndex,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: l10n.t('Period details', 'Időszak részletei')),
                  hint: Text(
                      l10n.t('Select a period or tap the chart',
                          'Válassz időszakot vagy érintsd meg a diagramot'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  items: [
                    for (var i = 0; i < buckets.length; i++)
                      DropdownMenuItem(
                          value: i,
                          child: Text(_bucketLabel(buckets[i], localeStr)))
                  ],
                  onChanged: (index) {
                    if (index != null) {
                      setState(
                          () => _selectedPeriodStart = buckets[index].start);
                    }
                  },
                ),
                if (selected != null) ...[
                  const SizedBox(height: 12),
                  Text(_bucketLabel(selected, localeStr),
                      style: textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text(
                      '${l10n.expense}: ${Money(selected.expenseMinor).format(locale: localeStr, hideAmounts: hideAmounts)}'),
                  Text(
                      '${l10n.income}: ${Money(selected.incomeMinor).format(locale: localeStr, hideAmounts: hideAmounts)}'),
                  Text(
                      '${l10n.t('Balance', 'Egyenleg')}: ${Money(selected.balanceMinor).format(locale: localeStr, hideAmounts: hideAmounts)}'),
                  OutlinedButton.icon(
                      onPressed: () => _openEntries(selected),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label:
                          Text(l10n.t('View entries', 'Tételek megtekintése'))),
                ],
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
          DuoSection(
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
          DuoSection(
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
          DuoSection(
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
          DuoSection(
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

class _CashFlowChart extends StatelessWidget {
  const _CashFlowChart(
      {super.key,
      required this.buckets,
      required this.range,
      required this.bars,
      required this.locale,
      required this.hideAmounts,
      required this.expenseLabel,
      required this.incomeLabel,
      required this.onSelect});
  final List<CashFlowBucket> buckets;
  final ReportingRange range;
  final bool bars, hideAmounts;
  final String locale, expenseLabel, incomeLabel;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final duo = context.duo;
    final text = Theme.of(context).textTheme;
    final maxMinor = buckets.fold<int>(1,
        (value, b) => math.max(value, math.max(b.expenseMinor, b.incomeMinor)));
    final maxY = maxMinor * 1.18;
    final stride = (buckets.length / 6).ceil().clamp(1, 10000);
    final titles = FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: maxY / 3,
              getTitlesWidget: (value, meta) {
                if (value <= 0 || value >= maxY * .98) {
                  return const SizedBox.shrink();
                }
                return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                        Money(value.round()).formatCompact(
                            locale: locale, hideAmounts: hideAmounts),
                        style: text.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis));
              })),
      bottomTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if ((value - index).abs() > .01 ||
                    index < 0 ||
                    index >= buckets.length ||
                    index % stride != 0) {
                  return const SizedBox.shrink();
                }
                final date = buckets[index].start;
                final label = switch (range) {
                  ReportingRange.allTime => '${date.year}',
                  ReportingRange.year => DateFormat.MMM(locale).format(date),
                  ReportingRange.month => '${date.day}',
                };
                return InkWell(
                    onTap: () => onSelect(index),
                    child: SizedBox(
                        height: 48,
                        child: Center(
                            child: Text(label,
                                style: text.labelSmall
                                    ?.copyWith(color: duo.info)))));
              })),
    );
    final grid = FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 3,
        getDrawingHorizontalLine: (_) => FlLine(
            color: duo.hairline, strokeWidth: 1, dashArray: const [4, 4]));
    String amount(int value) =>
        Money(value).formatCompact(locale: locale, hideAmounts: hideAmounts);
    Widget legend(Color color, String label) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: text.labelSmall),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 20, runSpacing: 8, children: [
        legend(duo.negative, expenseLabel),
        legend(duo.positive, incomeLabel)
      ]),
      const SizedBox(height: 12),
      SizedBox(
          height: 224,
          child: LayoutBuilder(builder: (context, constraints) {
            if (bars) {
              final rodWidth =
                  (constraints.maxWidth / buckets.length / 4).clamp(2.0, 12.0);
              return BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: maxY,
                    titlesData: titles,
                    gridData: grid,
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < buckets.length; i++)
                        BarChartGroupData(x: i, barsSpace: 2, barRods: [
                          BarChartRodData(
                              toY: buckets[i].expenseMinor.toDouble(),
                              color: duo.negative,
                              width: rodWidth,
                              borderRadius: BorderRadius.circular(2)),
                          BarChartRodData(
                              toY: buckets[i].incomeMinor.toDouble(),
                              color: duo.positive,
                              width: rodWidth,
                              borderRadius: BorderRadius.circular(2)),
                        ])
                    ],
                    barTouchData: BarTouchData(
                        touchCallback: (event, response) {
                          if (event is FlTapUpEvent && response?.spot != null) {
                            onSelect(response!.spot!.touchedBarGroupIndex);
                          }
                        },
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => duo.heroSurface,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                              BarTooltipItem(
                                  '$expenseLabel: ${amount(buckets[groupIndex].expenseMinor)}\n$incomeLabel: ${amount(buckets[groupIndex].incomeMinor)}',
                                  const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                        )),
                  ),
                  swapAnimationDuration: Duration.zero);
            }
            LineChartBarData series(bool income) => LineChartBarData(
                  spots: [
                    for (var i = 0; i < buckets.length; i++)
                      FlSpot(
                          i.toDouble(),
                          (income
                                  ? buckets[i].incomeMinor
                                  : buckets[i].expenseMinor)
                              .toDouble())
                  ],
                  color: income ? duo.positive : duo.negative,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: true),
                  isCurved: false,
                  belowBarData: BarAreaData(
                      show: !income,
                      color: duo.negative.withValues(alpha: .08)),
                );
            return LineChart(
                LineChartData(
                  minX: buckets.length == 1 ? -.5 : 0,
                  maxX: buckets.length == 1
                      ? .5
                      : (buckets.length - 1).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  titlesData: titles,
                  gridData: grid,
                  borderData: FlBorderData(show: false),
                  lineBarsData: [series(false), series(true)],
                  lineTouchData: LineTouchData(
                      touchCallback: (event, response) {
                        if (event is FlTapUpEvent &&
                            response?.lineBarSpots?.isNotEmpty == true) {
                          onSelect(response!.lineBarSpots!.first.spotIndex);
                        }
                      },
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => duo.heroSurface,
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        getTooltipItems: (spots) => spots
                            .map((spot) => LineTooltipItem(
                                '${spot.barIndex == 0 ? expenseLabel : incomeLabel}: ${amount(spot.y.round())}',
                                const TextStyle(
                                    color: Colors.white, fontSize: 12)))
                            .toList(),
                      )),
                ),
                duration: Duration.zero);
          })),
    ]);
  }
}
