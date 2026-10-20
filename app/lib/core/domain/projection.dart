import 'dart:math';
import '../db/tables/tables.dart';
import 'views.dart';

class ProjectionPoint {
  final int month;
  final int balanceMinor;
  final int contributedMinor;

  const ProjectionPoint(this.month, this.balanceMinor, this.contributedMinor);

  int get interestMinor => balanceMinor - contributedMinor;
}

class Projection {
  final List<ProjectionPoint> points;
  const Projection(this.points);

  int get finalBalanceMinor => points.isEmpty ? 0 : points.last.balanceMinor;
  int get totalContributedMinor =>
      points.isEmpty ? 0 : points.last.contributedMinor;
  int get totalInterestMinor => finalBalanceMinor - totalContributedMinor;
}

Projection project({
  required int startMinor,
  required int monthlyContributionMinor,
  required double annualRatePct,
  required Compounding compounding,
  required int months,
  double taxPct = 0,
}) {
  if (months <= 0) {
    return Projection([ProjectionPoint(0, startMinor, startMinor)]);
  }
  final periodsPerYear = compounding.periodsPerYear;
  final monthlyFactor = annualRatePct == 0
      ? 0.0
      : pow(1 + annualRatePct / 100 / periodsPerYear, periodsPerYear / 12) - 1;
  double balance = startMinor.toDouble();
  double contributed = startMinor.toDouble();
  final points = <ProjectionPoint>[];
  for (var m = 1; m <= months; m++) {
    final interest = balance * monthlyFactor * (1 - taxPct / 100);
    balance += interest + monthlyContributionMinor;
    contributed += monthlyContributionMinor;
    points.add(ProjectionPoint(m, balance.round(), contributed.round()));
  }
  return Projection(points);
}

/// Binary searches for the required monthly saving (minor units) to reach [targetMinor] in [months].
int solveRequiredMonthlyContribution({
  required int startMinor,
  required int targetMinor,
  required double annualRatePct,
  required Compounding compounding,
  required int months,
  double taxPct = 0,
}) {
  if (months <= 0) return max(0, targetMinor - startMinor);
  final zeroContribution = project(
    startMinor: startMinor,
    monthlyContributionMinor: 0,
    annualRatePct: annualRatePct,
    compounding: compounding,
    months: months,
    taxPct: taxPct,
  ).finalBalanceMinor;
  if (zeroContribution >= targetMinor) return 0;

  var low = 0;
  var high = targetMinor - startMinor;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    final projected = project(
      startMinor: startMinor,
      monthlyContributionMinor: mid,
      annualRatePct: annualRatePct,
      compounding: compounding,
      months: months,
      taxPct: taxPct,
    ).finalBalanceMinor;
    if (projected >= targetMinor) {
      high = mid;
    } else {
      low = mid + 1;
    }
  }
  return low;
}

/// Computes emergency fund target (minor units) for [targetMonths] based on average
/// monthly essential expenses over the last [lookbackMonths] (default 3).
int computeEmergencyFundTarget({
  required Iterable<Txn> transactions,
  required Set<String> essentialCategoryIds,
  required bool isSharedFund,
  required String meId,
  int targetMonths = 6,
  int lookbackMonths = 3,
}) {
  final view = isSharedFund ? ExpenseView.together : ExpenseView.myTotal;
  var totalEssentialMinor = 0;
  for (final t in transactions) {
    if (t.deletedAt != null || t.kind != TxnKind.expense) continue;
    if (t.categoryId == null || !essentialCategoryIds.contains(t.categoryId)) {
      continue;
    }
    totalEssentialMinor += amountFor(t, view, meId);
  }
  final avgMonthly = lookbackMonths > 0
      ? (totalEssentialMinor / lookbackMonths).round()
      : totalEssentialMinor;
  return avgMonthly * targetMonths;
}
