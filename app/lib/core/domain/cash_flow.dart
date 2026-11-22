import '../db/tables/tables.dart';
import 'views.dart';

enum ReportingRange { allTime, year, month }

class CashFlowBucket {
  const CashFlowBucket(
      {required this.start,
      required this.end,
      required this.expenseMinor,
      required this.incomeMinor});
  final DateTime start, end;
  final int expenseMinor, incomeMinor;
  int get balanceMinor => incomeMinor - expenseMinor;
  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

List<CashFlowBucket> cashFlowBuckets(
    {required Iterable<Txn> transactions,
    required ReportingRange range,
    required int year,
    required int month,
    required ExpenseView view,
    required String meId,
    required DateTime now}) {
  final visible = transactions
      .where((t) =>
          t.deletedAt == null &&
          (t.visibility == VisibilityLevel.shared || t.createdBy == meId))
      .toList();
  final dates = visible.map((t) => t.occurredOn.year).toList()..sort();
  final firstYear = dates.isEmpty ? now.year : dates.first;
  final lastYear = dates.isEmpty ? now.year : dates.last;
  final count = switch (range) {
    ReportingRange.allTime => lastYear - firstYear + 1,
    ReportingRange.year => 12,
    ReportingRange.month => DateTime(year, month + 1, 0).day,
  };
  return List.generate(count, (index) {
    final start = switch (range) {
      ReportingRange.allTime => DateTime(firstYear + index),
      ReportingRange.year => DateTime(year, index + 1),
      ReportingRange.month => DateTime(year, month, index + 1),
    };
    final end = switch (range) {
      ReportingRange.allTime => DateTime(start.year + 1),
      ReportingRange.year => DateTime(start.year, start.month + 1),
      ReportingRange.month => DateTime(start.year, start.month, start.day + 1),
    };
    var expense = 0, income = 0;
    for (final t in visible) {
      if (!t.occurredOn.isBefore(start) && t.occurredOn.isBefore(end)) {
        expense += amountFor(t, view, meId);
        income += incomeFor(t, view, meId);
      }
    }
    return CashFlowBucket(
        start: start, end: end, expenseMinor: expense, incomeMinor: income);
  });
}
