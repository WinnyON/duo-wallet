import '../db/tables/tables.dart';

class SettleUpSummary {
  /// Positive means [partnerId] owes [meId]; negative means [meId] owes [partnerId].
  final int netSignedBaseMinor;
  final int pendingBaseMinor;
  final List<Settlement> pendingSettlements;

  const SettleUpSummary({
    required this.netSignedBaseMinor,
    required this.pendingBaseMinor,
    required this.pendingSettlements,
  });

  bool get someoneOwes => netSignedBaseMinor != 0;
  bool get partnerOwesMe => netSignedBaseMinor > 0;
  int get absoluteOwedMinor => netSignedBaseMinor.abs();
}

/// Computes settle-up balance between [meId] and [partnerId].
/// Rules:
/// 1. Only Together expenses paid from a PERSONAL account (`!paidFromCommon`) create debt.
/// 2. Common-account expenses and personal->common contributions create NO debt.
/// 3. Only CONFIRMED settlements adjust the balance; pending ones are reported separately.
SettleUpSummary computeSettleUpBalance({
  required String meId,
  required String partnerId,
  required Iterable<Txn> transactions,
  required Iterable<Settlement> settlements,
}) {
  var net = 0; // positive = partner owes me, negative = I owe partner

  for (final t in transactions) {
    if (t.deletedAt != null) continue;
    if (t.kind != TxnKind.expense) continue;
    if (t.scope != Scope.together) continue;
    if (t.paidFromCommon) continue;
    if (t.isContribution) continue;

    if (t.paidBy == meId) {
      net += t.baseShares[partnerId] ?? 0;
    } else if (t.paidBy == partnerId) {
      net -= t.baseShares[meId] ?? 0;
    }
  }

  var pendingTotal = 0;
  final pendingList = <Settlement>[];

  for (final s in settlements) {
    if (s.deletedAt != null || s.rejectedBy != null) continue;
    if (s.isConfirmed) {
      // If partner paid me, they owe me less:
      if (s.fromUser == partnerId && s.toUser == meId) {
        net -= s.baseAmountMinor;
      } else if (s.fromUser == meId && s.toUser == partnerId) {
        // If I paid partner, I owe them less (so net moves positive):
        net += s.baseAmountMinor;
      }
    } else {
      pendingTotal += s.baseAmountMinor;
      pendingList.add(s);
    }
  }

  return SettleUpSummary(
    netSignedBaseMinor: net,
    pendingBaseMinor: pendingTotal,
    pendingSettlements: pendingList,
  );
}
