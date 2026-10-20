import '../db/tables/tables.dart';
import '../money/money.dart';
import 'projection.dart';
import 'views.dart';

enum InsightSeverity { info, warning, success }

class InsightItem {
  final String id;
  final String titleEn;
  final String titleHu;
  final InsightSeverity severity;

  const InsightItem({
    required this.id,
    required this.titleEn,
    required this.titleHu,
    this.severity = InsightSeverity.info,
  });

  String localizedTitle(String locale) =>
      locale.startsWith('hu') ? titleHu : titleEn;
}

List<InsightItem> generateInsights({
  required String meId,
  required Iterable<Txn> transactions,
  required Iterable<Category> categories,
  required Iterable<Budget> budgets,
  required Iterable<RecurringRule> recurringRules,
  required Iterable<Goal> goals,
  required DateTime now,
}) {
  final insights = <InsightItem>[];
  final categoryMap = {for (final c in categories) c.id: c};

  // 1. Category spike vs 3-month average (My Total)
  final currentMonthStart = DateTime(now.year, now.month, 1);
  final threeMonthsAgo = DateTime(now.year, now.month - 3, 1);

  final currentByCat = <String, int>{};
  final pastByCat = <String, int>{};

  for (final t in transactions) {
    if (t.deletedAt != null || t.kind != TxnKind.expense || t.categoryId == null) {
      continue;
    }
    final amt = amountFor(t, ExpenseView.myTotal, meId);
    if (amt <= 0) continue;
    if (!t.occurredOn.isBefore(currentMonthStart)) {
      currentByCat[t.categoryId!] = (currentByCat[t.categoryId!] ?? 0) + amt;
    } else if (!t.occurredOn.isBefore(threeMonthsAgo) &&
        t.occurredOn.isBefore(currentMonthStart)) {
      pastByCat[t.categoryId!] = (pastByCat[t.categoryId!] ?? 0) + amt;
    }
  }

  for (final entry in currentByCat.entries) {
    final avg3m = (pastByCat[entry.key] ?? 0) / 3.0;
    if (avg3m > 0 && entry.value > avg3m * 1.25) {
      final pct = (((entry.value - avg3m) / avg3m) * 100).round();
      final cat = categoryMap[entry.key];
      final nameEn = cat?.nameEn ?? 'Category';
      final nameHu = cat?.nameHu ?? 'Kategória';
      insights.add(
        InsightItem(
          id: 'cat_spike_${entry.key}',
          titleEn: '$nameEn is $pct% above your 3-month average',
          titleHu: '$nameHu $pct%-kal a 3 havi átlagod felett van',
          severity: InsightSeverity.warning,
        ),
      );
    }
  }

  // 2. Monthly budget projection
  final myTotalBudget = budgets
      .where((b) =>
          b.deletedAt == null &&
          b.scope == Scope.individual &&
          b.ownerId == meId &&
          b.categoryId == null)
      .firstOrNull;
  if (myTotalBudget != null && myTotalBudget.amountMinor > 0) {
    final spentThisMonth = currentByCat.values.fold<int>(0, (a, b) => a + b);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final dayOfMonth = now.day.clamp(1, daysInMonth);
    final projectedMonthSpend =
        ((spentThisMonth / dayOfMonth) * daysInMonth).round();
    final diff = myTotalBudget.amountMinor - projectedMonthSpend;
    final formattedEn = Money(diff.abs()).format(locale: 'en');
    final formattedHu = Money(diff.abs()).format(locale: 'hu');
    if (diff >= 0) {
      insights.add(
        InsightItem(
          id: 'budget_pace_under',
          titleEn: 'On track to finish $formattedEn under budget',
          titleHu: 'Jó úton haladsz, hogy $formattedHu-tal a keret alatt maradj',
          severity: InsightSeverity.success,
        ),
      );
    } else {
      insights.add(
        InsightItem(
          id: 'budget_pace_over',
          titleEn: 'Projected to exceed budget by $formattedEn',
          titleHu: 'Várhatóan $formattedHu-tal túlléped a havi keretet',
          severity: InsightSeverity.warning,
        ),
      );
    }
  }

  // 3. Subscriptions total
  var monthlySubsMinor = 0;
  for (final r in recurringRules) {
    if (r.deletedAt != null || !r.isSubscription || r.kind != TxnKind.expense) {
      continue;
    }
    final factor = switch (r.frequency) {
      'weekly' => 52 / 12,
      'yearly' => 1 / 12,
      _ => 1.0,
    };
    monthlySubsMinor += (r.amountMinor * factor).round();
  }
  if (monthlySubsMinor > 0) {
    final subsEn = Money(monthlySubsMinor).format(locale: 'en');
    final subsHu = Money(monthlySubsMinor).format(locale: 'hu');
    insights.add(
      InsightItem(
        id: 'subs_total',
        titleEn: 'Subscriptions cost $subsEn/month',
        titleHu: 'Az előfizetések havi költsége $subsHu',
      ),
    );
  }

  // 4. Goal required monthly saving
  for (final g in goals) {
    if (g.deletedAt != null || g.deadline == null) continue;
    final monthsLeft =
        ((g.deadline!.year - now.year) * 12 + (g.deadline!.month - now.month))
            .clamp(1, 600);
    if (g.savedAmountMinor < g.targetAmountMinor) {
      final req = solveRequiredMonthlyContribution(
        startMinor: g.savedAmountMinor,
        targetMinor: g.targetAmountMinor,
        annualRatePct: g.annualInterestRatePct,
        compounding: Compounding.monthly,
        months: monthsLeft,
      );
      final reqEn = Money(req, g.currency).format(locale: 'en');
      final reqHu = Money(req, g.currency).format(locale: 'hu');
      insights.add(
        InsightItem(
          id: 'goal_req_${g.id}',
          titleEn: '${g.name}: save $reqEn/month to make the deadline',
          titleHu: '${g.name}: tegyél félre havi $reqHu-ot a határidőig',
        ),
      );
    }
  }

  return insights;
}
