import '../db/tables/tables.dart';
import 'views.dart';

/// One-month rollover follows the existing budget policy: carry unused funds
/// only from a preceding month with recorded spending.
({int spentMinor, int effectiveLimitMinor}) budgetSummary({
  required Budget budget,
  required Iterable<Txn> transactions,
  required DateTime month,
  required String meId,
}) {
  final view = budget.scope == Scope.together
      ? ExpenseView.together
      : ExpenseView.myTotal;
  int spent(DateTime start) {
    final end = DateTime(start.year, start.month + 1);
    return transactions
        .where((t) =>
            !t.occurredOn.isBefore(start) &&
            t.occurredOn.isBefore(end) &&
            (budget.categoryId == null || t.categoryId == budget.categoryId))
        .fold<int>(0, (sum, t) => sum + amountFor(t, view, meId));
  }

  final start = DateTime(month.year, month.month);
  final previous = spent(DateTime(month.year, month.month - 1));
  final carry = budget.rollover && previous > 0 && previous < budget.amountMinor
      ? budget.amountMinor - previous
      : 0;
  return (
    spentMinor: spent(start),
    effectiveLimitMinor: budget.amountMinor + carry
  );
}
