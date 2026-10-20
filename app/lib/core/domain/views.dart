import '../db/tables/tables.dart';

enum ExpenseView { together, individual, myTotal }

/// Returns the amount in base minor units (HUF minor) for [t] in view [v] for user [me].
int amountFor(Txn t, ExpenseView v, String me) {
  if (t.deletedAt != null || t.kind != TxnKind.expense) return 0;
  return switch (v) {
    ExpenseView.together => t.scope == Scope.together ? t.baseAmount : 0,
    ExpenseView.individual =>
      (t.scope == Scope.individual && t.createdBy == me) ? t.baseAmount : 0,
    ExpenseView.myTotal =>
      t.scope == Scope.individual
          ? (t.createdBy == me ? t.baseAmount : 0)
          : (t.baseShares[me] ?? 0),
  };
}

bool isIncludedInView(Txn t, ExpenseView v, String me) =>
    amountFor(t, v, me) > 0;
