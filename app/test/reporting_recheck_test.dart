import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/router.dart';
import 'package:duo_wallet/core/domain/cash_flow.dart';
import 'package:duo_wallet/core/domain/views.dart';
import 'package:duo_wallet/core/money/currency.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reporting_test.dart' show record, mount, tapVisible;

void selectFirstYear(WidgetTester tester) {
  final line = tester.widget<LineChart>(find.byType(LineChart));
  final bar = line.data.lineBarsData.first;
  line.data.lineTouchData.touchCallback!(
      FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
      LineTouchResponse([TouchLineBarSpot(bar, 0, bar.spots.first, 0)]));
}

Finder periodSelector() => find.byWidgetPredicate((w) =>
    w is DropdownButtonFormField<int> &&
    w.key.toString().contains('bucket-selector'));

void main() {
  test('cash-flow totals use HUF base amounts and recorded personal shares',
      () {
    final day = DateTime(2024, 2, 29);
    final txns = [
      record('eur-expense', day, TxnKind.expense, 1000).copyWith(
          currency: CurrencyCode.eur,
          fxRateToBase: 400,
          baseAmountMinor: 400000,
          shares: {'user-sam': 400, 'partner': 600},
          baseShares: {'user-sam': 160000, 'partner': 240000}),
      record('personal-expense', day, TxnKind.expense, 5000, shared: false),
      record('eur-income', day, TxnKind.income, 2000).copyWith(
          currency: CurrencyCode.eur,
          fxRateToBase: 400,
          paidFromCommon: true,
          baseAmountMinor: 800000,
          shares: {'user-sam': 1000, 'partner': 1000},
          baseShares: {'user-sam': 400000, 'partner': 400000}),
      record('personal-income', day, TxnKind.income, 20000, shared: false),
      record('hidden-income', day, TxnKind.income, 9999999,
          shared: false, owner: 'partner'),
      record('transfer', day, TxnKind.transfer, 9999999),
      record('deleted', day, TxnKind.expense, 9999999).copyWith(deletedAt: day),
    ];
    for (final expected in [
      (ExpenseView.together, 400000, 800000),
      (ExpenseView.individual, 5000, 20000),
      (ExpenseView.myTotal, 165000, 420000),
    ]) {
      for (final range in ReportingRange.values) {
        final buckets = cashFlowBuckets(
            transactions: txns,
            range: range,
            year: 2024,
            month: 2,
            view: expected.$1,
            meId: 'user-sam',
            now: day);
        expect(buckets.fold<int>(0, (sum, b) => sum + b.expenseMinor),
            expected.$2);
        expect(
            buckets.fold<int>(0, (sum, b) => sum + b.incomeMinor), expected.$3);
        expect(buckets.fold<int>(0, (sum, b) => sum + b.balanceMinor),
            expected.$3 - expected.$2);
      }
    }
  });

  test('daily boundaries include the last minute and exclude the next month',
      () {
    final buckets = cashFlowBuckets(
        transactions: [
          record('last-minute', DateTime(2024, 3, 31, 23, 59), TxnKind.expense,
              1200),
          record('next-month', DateTime(2024, 4, 1), TxnKind.expense, 9000),
        ],
        range: ReportingRange.month,
        year: 2024,
        month: 3,
        view: ExpenseView.together,
        meId: 'user-sam',
        now: DateTime(2024, 3));
    expect(buckets.length, 31);
    expect(buckets.last.expenseMinor, 1200);
    expect(buckets.last.contains(DateTime(2024, 3, 31, 23, 59)), isTrue);
    expect(buckets.last.contains(DateTime(2024, 4, 1)), isFalse);
  });

  testWidgets('reopening the same chart period clears a later entries search',
      (tester) async {
    final db = AppDatabase(seedDemo: false);
    db.saveTransaction(
        record('visible', DateTime(2024, 2), TxnKind.expense, 1000),
        fromSync: true);
    final c = await mount(tester, db);
    c.read(appRouterProvider).go('/stats');
    await tester.pumpAndSettle();
    selectFirstYear(tester);
    await tester.pumpAndSettle();
    await tapVisible(
        tester, find.widgetWithText(OutlinedButton, 'View entries'));
    final search =
        find.widgetWithText(TextField, 'Search merchant, note or tag');
    await tester.enterText(search, 'nothing matches this');
    await tester.pumpAndSettle();
    c.read(appRouterProvider).go('/stats');
    await tester.pumpAndSettle();
    await tapVisible(
        tester, find.widgetWithText(OutlinedButton, 'View entries'));
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await tester.scrollUntilVisible(find.text('Entry visible'), 400,
        scrollable: find.byType(Scrollable).hitTestable().first);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selected year stays selected when older data arrives',
      (tester) async {
    final db = AppDatabase(seedDemo: false);
    db.saveTransaction(
        record('current', DateTime(2024, 2), TxnKind.expense, 1000),
        fromSync: true);
    final c = await mount(tester, db);
    c.read(appRouterProvider).go('/stats');
    await tester.pumpAndSettle();
    selectFirstYear(tester);
    await tester.pumpAndSettle();
    db.saveTransaction(
        record('older', DateTime(2023, 2), TxnKind.expense, 9000),
        fromSync: true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(periodSelector(), 300,
        scrollable: find.byType(Scrollable).hitTestable().first);
    final selector = tester.widget<DropdownButton<int>>(find.descendant(
        of: periodSelector(),
        matching: find.byWidgetPredicate((w) => w is DropdownButton<int>)));
    final choice =
        selector.items!.singleWhere((item) => item.value == selector.value);
    expect((choice.child as Text).data, '2024');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a removed last page does not return after another record is added',
      (tester) async {
    final db = AppDatabase(seedDemo: false);
    for (var i = 0; i < 51; i++) {
      db.saveTransaction(
          record('$i', DateTime(2024, 2, 15, 0, i), TxnKind.expense, 1000),
          fromSync: true);
    }
    final c = await mount(tester, db);
    c.read(appRouterProvider).go('/transactions?from=2024-02-01&to=2024-02-29');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Next'));
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Next'));
    db.softDeleteTransaction('0');
    await tester.pumpAndSettle();
    final pager = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+ / \d+$').hasMatch(w.data ?? ''));
    await tester.scrollUntilVisible(pager, 600,
        scrollable: find.byType(Scrollable).hitTestable().first,
        maxScrolls: 60);
    expect(tester.widget<Text>(pager).data, '2 / 2');
    db.saveTransaction(
        record('new', DateTime(2024, 2, 16), TxnKind.expense, 1000),
        fromSync: true);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(pager, 600,
        scrollable: find.byType(Scrollable).hitTestable().first,
        maxScrolls: 60);
    expect(tester.widget<Text>(pager).data, '2 / 3');
    expect(tester.takeException(), isNull);
  });
}
