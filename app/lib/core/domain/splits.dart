class SplitResult {
  final Map<String, int> sharesMinor;
  final Map<String, int> baseSharesMinor;

  const SplitResult({
    required this.sharesMinor,
    required this.baseSharesMinor,
  });
}

/// Calculates split shares for [userA] and [userB] given [pctA] (0..100).
/// Any odd remainder is assigned to [userA] (the primary/payer) so the sum is exact.
SplitResult calculatePercentageSplit({
  required int amountMinor,
  required int baseAmountMinor,
  required String userA,
  required String userB,
  required int pctA,
}) {
  assert(pctA >= 0 && pctA <= 100, 'pctA must be between 0 and 100');
  final shareA = (amountMinor * pctA) ~/ 100;
  final shareB = amountMinor - shareA;

  final baseA = (baseAmountMinor * pctA) ~/ 100;
  final baseB = baseAmountMinor - baseA;

  return SplitResult(
    sharesMinor: {userA: shareA, userB: shareB},
    baseSharesMinor: {userA: baseA, userB: baseB},
  );
}

SplitResult calculateIndividualSplit({
  required int amountMinor,
  required int baseAmountMinor,
  required String ownerId,
}) {
  return SplitResult(
    sharesMinor: {ownerId: amountMinor},
    baseSharesMinor: {ownerId: baseAmountMinor},
  );
}
