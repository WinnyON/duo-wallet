import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/tables/tables.dart';
import '../../../core/domain/insights.dart';
import '../../../core/domain/views.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  ExpenseView _view = ExpenseView.together;

  Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final val = int.tryParse('FF$cleaned', radix: 16);
    return val != null ? Color(val) : Colors.indigo;
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

    final txns = db.transactions;
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
        if (_view == ExpenseView.together) {
          if (t.paidFromCommon || t.visibility == VisibilityLevel.shared) {
            totalIncomeMinor += t.baseAmountMinor;
          }
        } else {
          if (!t.paidFromCommon && t.createdBy == meId) {
            totalIncomeMinor += t.baseAmountMinor;
          } else if (t.paidFromCommon) {
            totalIncomeMinor += t.baseAmountMinor ~/ 2;
          }
        }
      }
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
      appBar: AppBar(title: Text(l10n.stats)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<ExpenseView>(
            segments: [
              ButtonSegment(
                value: ExpenseView.together,
                label: Text('👥 ${l10n.viewTogether}'),
              ),
              ButtonSegment(
                value: ExpenseView.myTotal,
                label: Text('🔒 ${l10n.viewMyTotal}'),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(height: 16),

          // Spend vs Income & Savings Rate Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Income vs Spend & Savings Rate',
                        'Bevétel vs. Kiadás és Megtakarítási ráta'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statColumn(
                        context,
                        l10n.expense,
                        Money(totalSpendMinor, CurrencyCode.huf).format(
                          locale: localeStr,
                          hideAmounts: hideAmounts,
                        ),
                        Colors.redAccent,
                      ),
                      _statColumn(
                        context,
                        l10n.income,
                        Money(totalIncomeMinor, CurrencyCode.huf).format(
                          locale: localeStr,
                          hideAmounts: hideAmounts,
                        ),
                        Colors.teal,
                      ),
                      _statColumn(
                        context,
                        l10n.t('Savings Rate', 'Megtakarítási ráta'),
                        totalIncomeMinor > 0
                            ? '${savingsRatePct.toStringAsFixed(1)}%'
                            : '—',
                        Colors.indigo,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Category Breakdown & PieChart
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Category Breakdown', 'Kategória megoszlás'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (sortedCats.isEmpty)
                    Text(l10n.t('No expenses recorded.', 'Nincs rögzített kiadás.'))
                  else ...[
                    SizedBox(
                      height: 180,
                      child: PieChart(
                        PieChartData(
                          centerSpaceRadius: 36,
                          sectionsSpace: 2,
                          sections: sortedCats.map((entry) {
                            final cat = db.findCategory(entry.key);
                            final color = cat != null
                                ? _parseColor(cat.color)
                                : Colors.blueGrey;
                            final pct = totalSpendMinor > 0
                                ? (entry.value / totalSpendMinor * 100).round()
                                : 0;
                            return PieChartSectionData(
                              value: entry.value.toDouble(),
                              color: color,
                              radius: 48,
                              title: '$pct%',
                              titleStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final entry in sortedCats)
                      Builder(
                        builder: (context) {
                          final cat = db.findCategory(entry.key);
                          final name = cat != null
                              ? cat.localizedName(localeStr)
                              : l10n.t('Uncategorized', 'Kategória nélkül');
                          final color = cat != null
                              ? _parseColor(cat.color)
                              : Colors.blueGrey;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 6,
                                  backgroundColor: color,
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(name)),
                                Text(
                                  Money(entry.value, CurrencyCode.huf).format(
                                    locale: localeStr,
                                    hideAmounts: hideAmounts,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
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
          ),
          const SizedBox(height: 12),

          // Together vs Individual Ratio (from my visible data only)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t(
                      'Together vs Individual Ratio (My Cost)',
                      'Közös vs. Egyéni arány (Saját költség)',
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '👥 ${l10n.viewTogether}: $togetherPct% (${Money(myShareTogetherMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)})  •  '
                    '🔒 ${l10n.viewIndividual}: $individualPct% (${Money(myIndividualMinor, CurrencyCode.huf).format(locale: localeStr, hideAmounts: hideAmounts)})',
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: myCombinedMinor > 0
                          ? myShareTogetherMinor / myCombinedMinor
                          : 0.5,
                      minHeight: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Top Merchants
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Top Merchants', 'Leggyakoribb kereskedők'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (topMerchants.isEmpty)
                    Text(l10n.t('No merchant data yet.', 'Még nincs kereskedő adat.'))
                  else
                    for (final m in topMerchants.take(5))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(m.key),
                        trailing: Text(
                          Money(m.value, CurrencyCode.huf).format(
                            locale: localeStr,
                            hideAmounts: hideAmounts,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Active Financial Insights
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('Financial Insights', 'Pénzügyi elemzések'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (insights.isEmpty)
                    Text(l10n.t('No active insights.', 'Nincs aktív elemzés.'))
                  else
                    for (final item in insights)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          switch (item.severity) {
                            InsightSeverity.warning =>
                              Icons.warning_amber_rounded,
                            InsightSeverity.success =>
                              Icons.check_circle_outline,
                            InsightSeverity.info => Icons.lightbulb_outline,
                          },
                          color: switch (item.severity) {
                            InsightSeverity.warning => Colors.deepOrange,
                            InsightSeverity.success => Colors.green,
                            InsightSeverity.info => Colors.indigo,
                          },
                        ),
                        title: Text(item.localizedTitle(localeStr)),
                      ),
                ],
              ),
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
