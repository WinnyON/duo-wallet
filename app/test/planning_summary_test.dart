import 'package:flutter_test/flutter_test.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/domain/budget_summary.dart';
import 'package:duo_wallet/core/domain/recurring_schedule.dart';

void main() {
  final now = DateTime(2026, 11, 4);
  Txn expense(String id, DateTime date, int amount, String category,
          {Scope scope = Scope.together, Map<String, int> shares = const {}}) =>
      Txn(
        id: id,
        householdId: 'h',
        kind: TxnKind.expense,
        scope: scope,
        visibility: VisibilityLevel.shared,
        occurredOn: date,
        amountMinor: amount,
        baseAmountMinor: amount,
        paidBy: 'me',
        paidFromCommon: false,
        accountId: 'account',
        accountAmountMinor: amount,
        categoryId: category,
        createdBy: 'me',
        createdAt: now,
        updatedAt: now,
        baseShares: shares,
      );
  test('category budget uses dated category scope and previous-month rollover',
      () {
    final budget = Budget(
        id: 'b',
        householdId: 'h',
        scope: Scope.together,
        categoryId: 'food',
        amountMinor: 10000,
        rollover: true,
        updatedAt: now);
    final txns = [
      expense('previous', DateTime(2026, 10, 15), 4000, 'food'),
      expense('current', DateTime(2026, 11, 1), 7000, 'food'),
      expense('other', DateTime(2026, 11, 2), 9000, 'travel'),
      expense('private', DateTime(2026, 11, 3), 5000, 'food',
          scope: Scope.individual),
      expense('future', DateTime(2026, 12, 1), 8000, 'food'),
    ];
    expect(
        budgetSummary(
            budget: budget, transactions: txns, month: now, meId: 'me'),
        (spentMinor: 7000, effectiveLimitMinor: 16000));
  });
  test('personal budget includes only my shared share and own private expense',
      () {
    final budget = Budget(
        id: 'b',
        householdId: 'h',
        scope: Scope.individual,
        ownerId: 'me',
        amountMinor: 10000,
        updatedAt: now);
    final txns = [
      expense('shared', now, 9000, 'food',
          shares: {'me': 3000, 'partner': 6000}),
      expense('own', now, 1000, 'food', scope: Scope.individual),
    ];
    expect(
        budgetSummary(
                budget: budget, transactions: txns, month: now, meId: 'me')
            .spentMinor,
        4000);
  });
  test('empty previous month does not invent rollover history', () {
    final budget = Budget(
        id: 'b',
        householdId: 'h',
        scope: Scope.together,
        amountMinor: 10000,
        rollover: true,
        updatedAt: now);
    expect(
        budgetSummary(budget: budget, transactions: [], month: now, meId: 'me'),
        (spentMinor: 0, effectiveLimitMinor: 10000));
  });
  test('monthly advancement retains original month-end after February', () {
    final february =
        nextRecurringDate(DateTime(2028, 1, 31), 'monthly', anchorDay: 31);
    expect(february, DateTime(2028, 2, 29));
    expect(nextRecurringDate(february, 'monthly', anchorDay: 31),
        DateTime(2028, 3, 31));
    expect(nextRecurringDate(DateTime(2027, 1, 31), 'monthly'),
        DateTime(2027, 2, 28));
  });
  test('weekly and yearly schedules advance by calendar across boundaries', () {
    expect(nextRecurringDate(DateTime(2026, 12, 28), 'weekly'),
        DateTime(2027, 1, 4));
    expect(nextRecurringDate(DateTime(2028, 2, 29), 'yearly'),
        DateTime(2029, 2, 28));
    expect(() => nextRecurringDate(now, 'unsupported'), throwsArgumentError);
  });
}
