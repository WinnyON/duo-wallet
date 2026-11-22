import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/money/money.dart';
import 'package:duo_wallet/features/transactions/presentation/transaction_period_picker.dart';
import 'package:duo_wallet/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'reporting_test.dart' show record, mount, tapVisible;

void main() {
  test('calendar periods include leap days and weeks spanning years', () {
    expect(transactionPeriod(DateTime(2024, 2, 15), TransactionPeriod.month),
        DateTimeRange(start: DateTime(2024, 2), end: DateTime(2024, 2, 29)));
    expect(
        transactionPeriod(DateTime(2025, 1, 1), TransactionPeriod.week),
        DateTimeRange(
            start: DateTime(2024, 12, 30), end: DateTime(2025, 1, 5)));
    expect(transactionPeriod(DateTime(2024, 12, 31), TransactionPeriod.year),
        DateTimeRange(start: DateTime(2024), end: DateTime(2024, 12, 31)));
  });

  testWidgets('transactions default and clear filters to the current month',
      (tester) async {
    final now = DateTime.now();
    final db = AppDatabase(seedDemo: false);
    for (final item in [
      record(
          'current', DateTime(now.year, now.month, 1), TxnKind.expense, 1000),
      record('old', DateTime(now.year, now.month, 0), TxnKind.expense, 9000),
    ]) {
      db.saveTransaction(item, fromSync: true);
    }
    final container = await mount(tester, db);
    container.read(appRouterProvider).go('/transactions');
    await tester.pumpAndSettle();
    String? total() => tester
        .widget<Text>(find.byKey(const ValueKey('transaction-spending-total')))
        .data;
    expect(total(), const Money(1000).format(locale: 'en'));
    container.read(appRouterProvider).go(
        '/transactions?from=${DateTime(now.year, now.month, 0).toIso8601String()}&to=${DateTime(now.year, now.month, 0).toIso8601String()}');
    await tester.pumpAndSettle();
    expect(total(), const Money(9000).format(locale: 'en'));
    await tapVisible(
        tester, find.widgetWithText(TextButton, 'Clear filters').first);
    expect(total(), const Money(1000).format(locale: 'en'));
  });

  testWidgets('picker applies whole periods and retains custom range selection',
      (tester) async {
    DateTimeRange? selected;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () async {
                selected = await showTransactionPeriodPicker(
                    context: context,
                    initialRange: DateTimeRange(
                        start: DateTime(2024, 2), end: DateTime(2024, 2, 29)));
              },
              child: const Text('Open')));
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(selected,
        DateTimeRange(start: DateTime(2024), end: DateTime(2024, 12, 31)));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date range'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });
}
