import 'package:home_widget/home_widget.dart';

import '../../core/db/app_database.dart';
import '../../core/db/tables/tables.dart';
import '../../core/domain/views.dart';
import '../../core/money/currency.dart';
import '../../core/money/money.dart';

class HomeWidgetSnapshot {
  final String remainingBudgetFormatted;
  final String myTotalMonthFormatted;
  final bool hideAmounts;

  const HomeWidgetSnapshot({
    required this.remainingBudgetFormatted,
    required this.myTotalMonthFormatted,
    required this.hideAmounts,
  });

  Map<String, String> toKeyValues() => {
    'remaining_budget': remainingBudgetFormatted,
    'my_total_month': myTotalMonthFormatted,
    'hide_amounts': hideAmounts.toString(),
  };
}

/// Bridges visible monthly budget & My Total spend to the Android Home-Screen Widget.
/// Never reads or exposes partner's private records, and masks values when `hideAmounts` is enabled.
class HomeWidgetBridge {
  static const androidProviderName = 'DuoWidgetProvider';

  static HomeWidgetSnapshot buildSnapshot({
    required AppDatabase db,
    required String meId,
    required bool hideAmounts,
    required DateTime now,
    String locale = 'hu',
  }) {
    final baseCurrency = db.household?.baseCurrency ?? CurrencyCode.huf;
    var myTotalSpentMinor = 0;
    var togetherSpentMinor = 0;

    for (final t in db.transactions) {
      if (t.occurredOn.year == now.year && t.occurredOn.month == now.month) {
        myTotalSpentMinor += amountFor(t, ExpenseView.myTotal, meId);
        togetherSpentMinor += amountFor(t, ExpenseView.together, meId);
      }
    }

    // Prefer user's personal total budget ("My" budget); fallback to Together total budget
    Budget? totalBudget;
    for (final b in db.budgets) {
      if (b.categoryId != null) continue;
      if (b.scope == Scope.individual && b.ownerId == meId) {
        totalBudget = b;
        break;
      }
      if (b.scope == Scope.together && totalBudget == null) {
        totalBudget = b;
      }
    }

    final budgetMinor = totalBudget?.amountMinor ?? 0;
    final usedMinor = totalBudget?.scope == Scope.together
        ? togetherSpentMinor
        : myTotalSpentMinor;
    final remainingMinor = budgetMinor - usedMinor;

    return HomeWidgetSnapshot(
      remainingBudgetFormatted: Money(remainingMinor, baseCurrency)
          .format(locale: locale, hideAmounts: hideAmounts),
      myTotalMonthFormatted: Money(myTotalSpentMinor, baseCurrency)
          .format(locale: locale, hideAmounts: hideAmounts),
      hideAmounts: hideAmounts,
    );
  }

  static Future<HomeWidgetSnapshot> syncToAndroidWidget({
    required AppDatabase db,
    required String meId,
    required bool hideAmounts,
    DateTime? now,
    String locale = 'hu',
  }) async {
    final snap = buildSnapshot(
      db: db,
      meId: meId,
      hideAmounts: hideAmounts,
      now: now ?? DateTime.now(),
      locale: locale,
    );
    try {
      for (final entry in snap.toKeyValues().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(androidName: androidProviderName);
    } catch (_) {
      // Ignored in headless unit tests or non-Android environments
    }
    return snap;
  }
}
