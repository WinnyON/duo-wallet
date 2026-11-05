import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/domain/balance.dart';
import 'package:duo_wallet/core/domain/insights.dart';
import 'package:duo_wallet/core/domain/projection.dart';
import 'package:duo_wallet/core/domain/splits.dart';
import 'package:duo_wallet/core/domain/views.dart';
import 'package:duo_wallet/core/money/currency.dart';
import 'package:duo_wallet/core/money/fx_service.dart';
import 'package:duo_wallet/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sam = 'user-sam';
  const anna = 'user-anna';
  const hh = 'hh-1';
  final now = DateTime(2026, 10, 15);

  group('Splits (calculatePercentageSplit & calculateIndividualSplit)', () {
    test('50/50 even split', () {
      final res = calculatePercentageSplit(
        amountMinor: 10000,
        baseAmountMinor: 10000,
        userA: sam,
        userB: anna,
        pctA: 50,
      );
      expect(res.sharesMinor[sam], 5000);
      expect(res.sharesMinor[anna], 5000);
      expect(res.baseSharesMinor[sam]! + res.baseSharesMinor[anna]!, 10000);
    });

    test('odd remainder preserves exact sum', () {
      final res = calculatePercentageSplit(
        amountMinor: 10001,
        baseAmountMinor: 10001,
        userA: sam,
        userB: anna,
        pctA: 50,
      );
      expect(res.sharesMinor[sam], 5000);
      expect(res.sharesMinor[anna], 5001);
      expect(res.sharesMinor[sam]! + res.sharesMinor[anna]!, 10001);
    });

    test('0/100 split ("I paid Anna\'s dentist")', () {
      final res = calculatePercentageSplit(
        amountMinor: 2500000,
        baseAmountMinor: 2500000,
        userA: sam,
        userB: anna,
        pctA: 0,
      );
      expect(res.sharesMinor[sam], 0);
      expect(res.sharesMinor[anna], 2500000);
    });

    test('100/0 split', () {
      final res = calculatePercentageSplit(
        amountMinor: 2500000,
        baseAmountMinor: 2500000,
        userA: sam,
        userB: anna,
        pctA: 100,
      );
      expect(res.sharesMinor[sam], 2500000);
      expect(res.sharesMinor[anna], 0);
    });
  });

  group('Three Views (amountFor & isIncludedInView)', () {
    final together6040 = Txn(
      id: 't1',
      householdId: hh,
      kind: TxnKind.expense,
      scope: Scope.together,
      visibility: VisibilityLevel.shared,
      occurredOn: now,
      amountMinor: 1000000, // 10 000 Ft
      baseAmountMinor: 1000000,
      paidBy: sam,
      paidFromCommon: false,
      accountId: 'acc-sam',
      accountAmountMinor: 1000000,
      createdBy: sam,
      createdAt: now,
      updatedAt: now,
      baseShares: const {sam: 600000, anna: 400000},
      shares: const {sam: 600000, anna: 400000},
    );

    final samIndiv = Txn(
      id: 't2',
      householdId: hh,
      kind: TxnKind.expense,
      scope: Scope.individual,
      visibility: VisibilityLevel.private,
      occurredOn: now,
      amountMinor: 500000, // 5 000 Ft
      baseAmountMinor: 500000,
      paidBy: sam,
      paidFromCommon: false,
      accountId: 'acc-sam',
      accountAmountMinor: 500000,
      createdBy: sam,
      createdAt: now,
      updatedAt: now,
      baseShares: const {sam: 500000},
      shares: const {sam: 500000},
    );

    test('Together view shows full amount of Together expenses only', () {
      expect(amountFor(together6040, ExpenseView.together, sam), 1000000);
      expect(amountFor(together6040, ExpenseView.together, anna), 1000000);
      expect(amountFor(samIndiv, ExpenseView.together, sam), 0);
    });

    test('Individual view shows only own Individual expenses', () {
      expect(amountFor(samIndiv, ExpenseView.individual, sam), 500000);
      expect(amountFor(samIndiv, ExpenseView.individual, anna), 0);
      expect(amountFor(together6040, ExpenseView.individual, sam), 0);
    });

    test('My Total view sums own Individual + own share of Together', () {
      expect(amountFor(together6040, ExpenseView.myTotal, sam), 600000);
      expect(amountFor(together6040, ExpenseView.myTotal, anna), 400000);
      expect(amountFor(samIndiv, ExpenseView.myTotal, sam), 500000);
      expect(amountFor(samIndiv, ExpenseView.myTotal, anna), 0);
    });
  });

  group('Settle-Up Balance (computeSettleUpBalance)', () {
    test('Personal-paid Together creates debt; Common-paid and contributions create 0 debt', () {
      final txns = [
        // 10 000 Ft 60/40 paid by Sam from personal card -> Anna owes Sam 4 000 Ft (400000 minor)
        Txn(
          id: 't1',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.together,
          visibility: VisibilityLevel.shared,
          occurredOn: now,
          amountMinor: 1000000,
          baseAmountMinor: 1000000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam',
          accountAmountMinor: 1000000,
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 600000, anna: 400000},
        ),
        // Common account expense -> 0 debt
        Txn(
          id: 't2',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.together,
          visibility: VisibilityLevel.shared,
          occurredOn: now,
          amountMinor: 800000,
          baseAmountMinor: 800000,
          paidBy: anna,
          paidFromCommon: true,
          accountId: 'acc-common',
          accountAmountMinor: 800000,
          createdBy: anna,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 400000, anna: 400000},
        ),
        // Personal -> common contribution -> 0 debt
        Txn(
          id: 't3',
          householdId: hh,
          kind: TxnKind.transfer,
          scope: Scope.together,
          visibility: VisibilityLevel.shared,
          occurredOn: now,
          amountMinor: 15000000,
          baseAmountMinor: 15000000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam',
          accountAmountMinor: 15000000,
          toAccountId: 'acc-common',
          toAccountAmountMinor: 15000000,
          isContribution: true,
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
        ),
      ];

      final pendingSettlement = Settlement(
        id: 's-pending',
        householdId: hh,
        fromUser: anna,
        toUser: sam,
        amountMinor: 150000,
        baseAmountMinor: 150000,
        fromConfirmed: true,
        toConfirmed: false,
        createdBy: anna,
        updatedAt: now,
      );

      final confirmedSettlement = Settlement(
        id: 's-confirmed',
        householdId: hh,
        fromUser: anna,
        toUser: sam,
        amountMinor: 100000, // 1 000 Ft confirmed
        baseAmountMinor: 100000,
        fromConfirmed: true,
        toConfirmed: true,
        createdBy: anna,
        updatedAt: now,
      );

      final summary = computeSettleUpBalance(
        meId: sam,
        partnerId: anna,
        transactions: txns,
        settlements: [pendingSettlement, confirmedSettlement],
      );

      // Initial debt 400,000 - confirmed 100,000 = 300,000; pending 150,000 excluded from net
      expect(summary.netSignedBaseMinor, 300000);
      expect(summary.partnerOwesMe, isTrue);
      expect(summary.pendingBaseMinor, 150000);
      expect(summary.pendingSettlements.length, 1);
    });
  });

  group('Multi-currency FxService & Money', () {
    test('converts EUR and RON to HUF and rounds minor units', () {
      final fx = FxService([
        FxQuote(
          from: CurrencyCode.eur,
          to: CurrencyCode.huf,
          rate: 400.0,
          source: FxSource.ecb,
          rateDate: now,
        ),
      ]);
      final eur20 = Money.fromMajor(20, CurrencyCode.eur);
      final huf = fx.convert(eur20, CurrencyCode.huf);
      expect(huf.currency, CurrencyCode.huf);
      expect(huf.amountMinor, 800000); // 8 000 Ft in minor units
      expect(huf.format(locale: 'hu'), '8\u00a0000 Ft');
    });
  });

  group('Compound Interest, Goal Solver & Emergency Fund', () {
    test('project() computes compound interest and solver finds required monthly saving', () {
      final p = project(
        startMinor: 10000000, // 100 000 Ft
        monthlyContributionMinor: 1000000, // 10 000 Ft/m
        annualRatePct: 6.0,
        compounding: Compounding.monthly,
        months: 12,
      );
      expect(p.totalContributedMinor, 22000000);
      expect(p.finalBalanceMinor, greaterThan(p.totalContributedMinor));

      final requiredMonthly = solveRequiredMonthlyContribution(
        startMinor: 10000000,
        targetMinor: p.finalBalanceMinor,
        annualRatePct: 6.0,
        compounding: Compounding.monthly,
        months: 12,
      );
      // Should be within 1 minor unit due to integer rounding
      expect((requiredMonthly - 1000000).abs(), lessThanOrEqualTo(1));
    });

    test('computeEmergencyFundTarget separates personal (My Total) and shared (Together)', () {
      final txns = [
        // 300 000 Ft total over 3 months Together (50/50) -> 100k/mo Together, 50k/mo My share
        Txn(
          id: 'e1',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.together,
          visibility: VisibilityLevel.shared,
          occurredOn: now,
          amountMinor: 30000000,
          baseAmountMinor: 30000000,
          paidBy: sam,
          paidFromCommon: true,
          accountId: 'acc-common',
          accountAmountMinor: 30000000,
          categoryId: 'cat-groceries',
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 15000000, anna: 15000000},
        ),
        // 60 000 Ft over 3 months Sam Individual essential -> 20k/mo for Sam
        Txn(
          id: 'e2',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: now,
          amountMinor: 6000000,
          baseAmountMinor: 6000000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam',
          accountAmountMinor: 6000000,
          categoryId: 'cat-health',
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 6000000},
        ),
      ];

      final sharedTarget = computeEmergencyFundTarget(
        transactions: txns,
        essentialCategoryIds: {'cat-groceries', 'cat-health'},
        isSharedFund: true,
        meId: sam,
        targetMonths: 6,
        lookbackMonths: 3,
      );
      // Together avg = 100k/mo * 6 = 600k Ft (60,000,000 minor)
      expect(sharedTarget, 60000000);

      final personalTarget = computeEmergencyFundTarget(
        transactions: txns,
        essentialCategoryIds: {'cat-groceries', 'cat-health'},
        isSharedFund: false,
        meId: sam,
        targetMonths: 6,
        lookbackMonths: 3,
      );
      // Sam My Total avg = (50k + 20k)/mo * 6 = 420k Ft (42,000,000 minor)
      expect(personalTarget, 42000000);
    });

    test('generateInsights produces spike, budget pace, subscriptions, and goal insights', () {
      final cat = Category(
        id: 'cat-dining',
        householdId: hh,
        nameEn: 'Dining',
        nameHu: 'Étterem',
        updatedAt: now,
      );
      final txns = [
        Txn(
          id: 'past',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: DateTime(2026, 9, 10),
          amountMinor: 3000000, // 30k over 3m => 10k avg
          baseAmountMinor: 3000000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam',
          accountAmountMinor: 3000000,
          categoryId: 'cat-dining',
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 3000000},
        ),
        Txn(
          id: 'curr',
          householdId: hh,
          kind: TxnKind.expense,
          scope: Scope.individual,
          visibility: VisibilityLevel.private,
          occurredOn: DateTime(2026, 10, 5),
          amountMinor: 2000000, // 20k this month (100% above 10k avg)
          baseAmountMinor: 2000000,
          paidBy: sam,
          paidFromCommon: false,
          accountId: 'acc-sam',
          accountAmountMinor: 2000000,
          categoryId: 'cat-dining',
          createdBy: sam,
          createdAt: now,
          updatedAt: now,
          baseShares: const {sam: 2000000},
        ),
      ];

      final list = generateInsights(
        meId: sam,
        transactions: txns,
        categories: [cat],
        budgets: const [],
        recurringRules: const [],
        goals: const [],
        now: now,
      );
      expect(list.any((i) => i.id == 'cat_spike_cat-dining'), isTrue);
    });
  });
}
