import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/domain/cash_flow.dart';
import 'package:duo_wallet/core/domain/views.dart';
import 'package:duo_wallet/core/money/money.dart';
import 'package:duo_wallet/router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ux_review_probe_test.dart' show loadUiFonts;

const me = 'user-sam';
Txn record(String id, DateTime date, TxnKind kind, int amount,
        {bool shared = true, String owner = me, Map<String, int>? shares}) =>
    Txn(
      id: id,
      householdId: 'hh',
      kind: kind,
      scope: shared ? Scope.together : Scope.individual,
      visibility: shared ? VisibilityLevel.shared : VisibilityLevel.private,
      occurredOn: date,
      amountMinor: amount,
      baseAmountMinor: amount,
      paidBy: owner,
      paidFromCommon: false,
      accountId: 'account',
      accountAmountMinor: amount,
      merchant: 'Entry $id',
      createdBy: owner,
      createdAt: date,
      updatedAt: date,
      shares: shares ?? {me: amount},
      baseShares: shares ?? {me: amount},
    );

Future<ProviderContainer> mount(WidgetTester tester, AppDatabase db) async {
  await loadUiFonts(tester);
  final container =
      ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: const DuoWalletApp()));
  await tester.pumpAndSettle();
  return container;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    tester
        .state<ScrollableState>(find.byType(Scrollable).hitTestable().first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 500,
        scrollable: find.byType(Scrollable).hitTestable().first,
        maxScrolls: 60);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('income respects personal shares, ownership, deletion and transfers',
      () {
    final shared = record('shared', DateTime(2024), TxnKind.income, 10000,
        shares: {me: 3000, 'partner': 7000});
    final personal =
        record('personal', DateTime(2024), TxnKind.income, 6000, shared: false);
    expect(incomeFor(shared, ExpenseView.together, me), 10000);
    expect(incomeFor(shared, ExpenseView.myTotal, me), 3000);
    expect(incomeFor(shared, ExpenseView.individual, me), 0);
    expect(incomeFor(personal, ExpenseView.myTotal, me), 6000);
    expect(incomeFor(personal, ExpenseView.together, me), 0);
    expect(
        incomeFor(
            record('partner', DateTime(2024), TxnKind.income, 6000,
                shared: false, owner: 'partner'),
            ExpenseView.myTotal,
            me),
        0);
    expect(
        incomeFor(shared.copyWith(deletedAt: DateTime(2024)),
            ExpenseView.together, me),
        0);
    expect(
        incomeFor(record('transfer', DateTime(2024), TxnKind.transfer, 999),
            ExpenseView.together, me),
        0);
    expect(
        incomeFor(
            record('unallocated', DateTime(2024), TxnKind.income, 8000,
                shares: {}),
            ExpenseView.myTotal,
            me),
        0);
  });

  test(
      'report buckets use years, months and leap-year days with exclusive boundaries',
      () {
    final txns = [
      record('old', DateTime(2023, 12, 31), TxnKind.expense, 100),
      record('leap', DateTime(2024, 2, 29), TxnKind.expense, 200),
      record('march', DateTime(2024, 3, 1), TxnKind.expense, 300),
      record('income', DateTime(2024, 2, 29), TxnKind.income, 1000),
      record('transfer', DateTime(2024, 2, 29), TxnKind.transfer, 99999),
      record('deleted', DateTime(2024, 2, 29), TxnKind.expense, 700)
          .copyWith(deletedAt: DateTime(2024)),
      record('hidden', DateTime(2000), TxnKind.expense, 9000,
          shared: false, owner: 'partner'),
    ];
    List<CashFlowBucket> buckets(ReportingRange range) => cashFlowBuckets(
        transactions: txns,
        range: range,
        year: 2024,
        month: 2,
        view: ExpenseView.together,
        meId: me,
        now: DateTime(2026));
    final all = buckets(ReportingRange.allTime);
    expect(all.map((b) => b.start.year), [2023, 2024]);
    expect(all.map((b) => b.expenseMinor), [100, 500]);
    final year = buckets(ReportingRange.year);
    expect(year.length, 12);
    expect(year[1].expenseMinor, 200);
    expect(year[1].incomeMinor, 1000);
    expect(year[2].expenseMinor, 300);
    final month = buckets(ReportingRange.month);
    expect(month.length, 29);
    expect(month.last.start, DateTime(2024, 2, 29));
    expect(month.last.end, DateTime(2024, 3));
    expect(month.last.balanceMinor, 800);
    expect(month.fold<int>(0, (sum, b) => sum + b.expenseMinor), 200);
    expect(
        cashFlowBuckets(
                transactions: [],
                range: ReportingRange.month,
                year: 2023,
                month: 2,
                view: ExpenseView.together,
                meId: me,
                now: DateTime(2026))
            .length,
        28);
    expect(
        cashFlowBuckets(
                transactions: [],
                range: ReportingRange.allTime,
                year: 2024,
                month: 2,
                view: ExpenseView.together,
                meId: me,
                now: DateTime(2026))
            .single
            .expenseMinor,
        0);
  });

  testWidgets(
      'entries paginate 25 records and retain full-filter income/spending totals',
      (tester) async {
    final db = AppDatabase(seedDemo: false);
    for (var i = 0; i < 57; i++) {
      db.saveTransaction(
          record('$i', DateTime(2024, 2, 15, 0, i),
              i < 30 ? TxnKind.expense : TxnKind.income, i < 30 ? 1000 : 2000),
          fromSync: true);
    }
    final container = await mount(tester, db);
    container.read(appRouterProvider).go('/transactions?from=2024-02-01&to=2024-02-29');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('transaction-spending-total')))
            .data,
        const Money(30000).format(locale: 'en'));
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('transaction-income-total')))
            .data,
        const Money(54000).format(locale: 'en'));
    await tester.scrollUntilVisible(find.text('1–25 of 57 entries'), 600,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Next'));
    await tester.scrollUntilVisible(find.text('26–50 of 57 entries'), 600,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Next'));
    await tester.scrollUntilVisible(find.text('51–57 of 57 entries'), 600,
        scrollable: find.byType(Scrollable).first, maxScrolls: 60);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Next'))
            .onPressed,
        isNull);
    final list =
        tester.widget<ListView>(find.byType(ListView).hitTestable().first);
    list.controller!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Search merchant, note or tag'),
        'Entry 56');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('1–1 of 1 entries'), 500,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Entry 56'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'period filters update all chart data and drill into matching entries',
      (tester) async {
    final db = AppDatabase(seedDemo: false);
    db.saveTransaction(
        record('feb-expense', DateTime(2024, 2, 29), TxnKind.expense, 20000),
        fromSync: true);
    db.saveTransaction(
        record('feb-income', DateTime(2024, 2, 29), TxnKind.income, 50000),
        fromSync: true);
    db.saveTransaction(
        record('march-expense', DateTime(2024, 3), TxnKind.expense, 90000),
        fromSync: true);
    db.saveTransaction(
        record('other-year', DateTime(2023, 2), TxnKind.expense, 70000),
        fromSync: true);
    final container = await mount(tester, db);
    container.read(appRouterProvider).go('/transactions');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Search merchant, note or tag'),
        'stale search');
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/stats');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .first
            .spots
            .length,
        2);
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Year'));
    final year = find.byKey(const ValueKey('statistics-year'));
    await tapVisible(tester, year);
    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    final line = tester.widget<LineChart>(find.byType(LineChart));
    expect(line.data.lineBarsData.first.spots.length, 12);
    expect(line.data.lineBarsData.first.spots[1].y, 20000);
    expect(line.data.lineBarsData.first.dotData.show, isTrue);
    final touched = [
      TouchLineBarSpot(
          line.data.lineBarsData[0], 0, line.data.lineBarsData[0].spots[1], 0),
      TouchLineBarSpot(
          line.data.lineBarsData[1], 1, line.data.lineBarsData[1].spots[1], 0),
    ];
    final tips =
        line.data.lineTouchData.touchTooltipData.getTooltipItems(touched);
    expect(tips.first!.text, contains('Expense'));
    expect(tips.last!.text, contains('Income'));
    line.data.lineTouchData.touchCallback!(
        FlTapUpEvent(TapUpDetails(kind: PointerDeviceKind.touch)),
        LineTouchResponse(touched));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byIcon(Icons.bar_chart));
    expect(tester.widget<BarChart>(find.byType(BarChart)).data.barGroups.length,
        12);
    final detail = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<int> &&
        w.key.toString().contains('bucket-selector'));
    await tapVisible(tester, detail);
    await tester.tap(find.text('February 2024').last);
    await tester.pumpAndSettle();
    await tapVisible(
        tester, find.widgetWithText(OutlinedButton, 'View entries'));
    expect(container.read(appRouterProvider).state.uri.queryParameters['from'],
        '2024-02-01');
    expect(container.read(appRouterProvider).state.uri.queryParameters['to'],
        '2024-02-29');
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('transaction-spending-total')))
            .data,
        const Money(20000).format(locale: 'en'));
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('transaction-income-total')))
            .data,
        const Money(50000).format(locale: 'en'));
    await tester.scrollUntilVisible(find.text('Entry feb-income'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Entry march-expense'), findsNothing);
    container.read(appRouterProvider).go('/stats');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Month'));
    final month = find.byKey(const ValueKey('statistics-month'));
    await tapVisible(tester, month);
    tester
        .state<ScrollableState>(find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .last)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('February').last);
    await tester.pumpAndSettle();
    final bars = tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(bars.length, 29);
    expect(bars.last.barRods.first.toY, 20000);
    await tester.scrollUntilVisible(find.byType(PieChart), 300,
        scrollable: find.byType(Scrollable).hitTestable().first);
    expect(
        tester
            .widget<PieChart>(find.byType(PieChart))
            .data
            .sections
            .single
            .value,
        20000);
    expect(tester.takeException(), isNull);
  });
  for (final locale in ['en', 'hu']) {
    testWidgets(
        'report controls and both charts fit narrow enlarged $locale text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await mount(tester, AppDatabase());
      container.read(appLocaleProvider.notifier).state = locale;
      container.read(appRouterProvider).go('/stats');
      await tester.pumpAndSettle();
      for (final label in locale == 'en'
          ? ['Year', 'Month', 'All time']
          : ['Év', 'Hónap', 'Összes idő']) {
        await tapVisible(tester, find.widgetWithText(ChoiceChip, label));
        for (final icon in [Icons.bar_chart, Icons.show_chart]) {
          await tapVisible(tester, find.byIcon(icon));
          await tester.drag(
              find.byType(ListView).hitTestable().first, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$locale $label $icon');
        }
      }
    });
  }
}
