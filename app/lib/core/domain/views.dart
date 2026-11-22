import '../db/tables/tables.dart';

enum ExpenseView { together, individual, myTotal }

/// Returns the amount in base minor units (HUF minor) for [t] in view [v] for user [me].
int amountFor(Txn t, ExpenseView v, String me) {
  if (t.deletedAt != null || t.kind != TxnKind.expense) return 0;
  return switch (v) {
    ExpenseView.together => t.scope == Scope.together ? t.baseAmount : 0,
    ExpenseView.individual =>
      (t.scope == Scope.individual && t.createdBy == me) ? t.baseAmount : 0,
    ExpenseView.myTotal => t.scope == Scope.individual
        ? (t.createdBy == me ? t.baseAmount : 0)
        : (t.baseShares[me] ?? 0),
  };
}

bool isIncludedInView(Txn t, ExpenseView v, String me) =>
    amountFor(t, v, me) > 0;

/// Income uses recorded personal shares; transfers and deleted records are excluded.
int incomeFor(Txn t, ExpenseView view, String me) {
  if (t.deletedAt != null || t.kind != TxnKind.income) return 0;
  final personal = !t.paidFromCommon && t.scope == Scope.individual;
  return switch (view) {
    ExpenseView.together => personal ? 0 : t.baseAmountMinor,
    ExpenseView.individual =>
      personal && t.createdBy == me ? t.baseAmountMinor : 0,
    ExpenseView.myTotal => personal
        ? (t.createdBy == me ? t.baseAmountMinor : 0)
        : (t.baseShares[me] ?? 0),
  };
}
