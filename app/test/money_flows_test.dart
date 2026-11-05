import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/money/currency.dart';
import 'package:duo_wallet/features/accounts/presentation/accounts_screen.dart';
import 'package:duo_wallet/features/transactions/presentation/transactions_screen.dart';
import 'package:duo_wallet/features/transfers/presentation/transfer_sheet.dart';
import 'package:duo_wallet/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ux_review_probe_test.dart' show loadUiFonts;

Future<ProviderContainer> mountMoneyApp(WidgetTester tester) async {
  await loadUiFonts(tester);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: const DuoWalletApp()));
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/transactions');
  await tester.pumpAndSettle();
  return container;
}

BuildContext scaffoldContext(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('money and FX validation preserve their different precision rules', () {
    expect(parseSignedAccountAmount('-12,34'), -12.34);
    expect(parseSignedAccountAmount('NaN'), isNull);
    expect(parseSignedAccountAmount('--1'), isNull);
    expect(parsePositiveRate('0,00253164557'), closeTo(1 / 395, 1e-12));
    for (final value in ['0', '-1', 'NaN', 'Infinity', '1,2.3', '1e300']) {
      expect(parsePositiveRate(value), isNull, reason: value);
    }
  });

  testWidgets(
      'unchanged partner-paid edit preserves payer, account and exact shares',
      (tester) async {
    final container = await mountMoneyApp(tester);
    final db = container.read(appDatabaseProvider);
    final original = db.transactions
        .firstWhere(
            (t) => t.kind == TxnKind.expense && t.scope == Scope.together)
        .copyWith(
            id: 'partner-private-paid',
            paidBy: 'user-anna',
            paidFromCommon: false,
            accountId: 'partner-hidden-source',
            amountMinor: 12345,
            accountAmountMinor: 12345,
            baseAmountMinor: 12345,
            shares: {'user-sam': 4321, 'user-anna': 8024},
            baseShares: {'user-sam': 4321, 'user-anna': 8024});
    db.upsertAccount(Account(
        id: 'partner-hidden-source',
        householdId: db.household!.id,
        name: 'PRIVATE ANNA BANK',
        type: AccountType.bank,
        ownership: AccountOwnership.personal,
        ownerId: 'user-anna',
        openingDate: DateTime(2026),
        updatedAt: DateTime.now()));
    db.saveTransaction(original);
    QuickAddTransactionSheet.show(scaffoldContext(tester), existing: original);
    await tester.pumpAndSettle();
    final hiddenAccountName = db.findAccount(original.accountId)?.name;
    if (hiddenAccountName != null) {
      expect(find.text(hiddenAccountName), findsNothing);
    }
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
    final saved = db.transactions.firstWhere((t) => t.id == original.id);
    expect(saved.paidBy, original.paidBy);
    expect(saved.accountId, original.accountId);
    expect(saved.accountAmountMinor, original.accountAmountMinor);
    expect(saved.amountMinor, original.amountMinor);
    expect(saved.shares, original.shares);
    expect(saved.baseShares, original.baseShares);
    expect(saved.occurredOn, original.occurredOn);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'transfer starts with actual FX quote, validates and preserves edited amounts',
      (tester) async {
    final container = await mountMoneyApp(tester);
    final db = container.read(appDatabaseProvider);
    final now = DateTime.now();
    db.upsertAccount(Account(
        id: 'eur-test',
        householdId: db.household!.id,
        name: 'Euro test account',
        type: AccountType.bank,
        ownership: AccountOwnership.personal,
        ownerId: 'user-sam',
        currency: CurrencyCode.eur,
        openingDate: now,
        updatedAt: now));
    final beforeCount = db.transactions.length;
    TransferSheet.show(scaffoldContext(tester),
        initialFromAccountId: 'acc-sam-bank', initialToAccountId: 'eur-test');
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    final rateText =
        tester.widget<TextFormField>(fields.at(1)).controller!.text;
    expect(parsePositiveRate(rateText), closeTo(1 / 395, 1e-12));
    await tester.enterText(fields.first, '3950');
    await tester.enterText(fields.at(1), 'NaN');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Review transfer'));
    expect(find.text('Enter a valid positive number.'), findsOneWidget);
    expect(db.transactions.length, beforeCount);
    await tester.enterText(fields.at(1), rateText);
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Review transfer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pumpAndSettle();
    final saved =
        db.transactions.firstWhere((t) => t.toAccountId == 'eur-test');
    expect(saved.accountId, 'acc-sam-bank');
    expect(saved.accountAmountMinor, 395000);
    expect(saved.toAccountAmountMinor, 1000);
    expect(saved.isContribution, isFalse);
    QuickAddTransactionSheet.show(scaffoldContext(tester), existing: saved);
    await tester.pumpAndSettle();
    expect(find.byType(TransferSheet), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, 'Edited note');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Review transfer'));
    await tester.tap(find.widgetWithText(FilledButton, 'Record'));
    await tester.pumpAndSettle();
    final edited = db.transactions.firstWhere((t) => t.id == saved.id);
    expect(edited.accountAmountMinor, saved.accountAmountMinor);
    expect(edited.toAccountAmountMinor, saved.toAccountAmountMinor);
    expect(edited.occurredOn, saved.occurredOn);
    expect(edited.note, 'Edited note');
    expect(db.transactions.length, beforeCount + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-account transfer remains invalid', (tester) async {
    final container = await mountMoneyApp(tester);
    final db = container.read(appDatabaseProvider);
    final count = db.transactions.length;
    TransferSheet.show(scaffoldContext(tester),
        initialFromAccountId: 'acc-sam-bank',
        initialToAccountId: 'acc-sam-bank');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '10');
    await tapVisible(
        tester, find.widgetWithText(FilledButton, 'Review transfer'));
    expect(find.text('Choose two different accounts.'), findsNWidgets(2));
    expect(db.transactions.length, count);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'private account route rechecks access after local identity change',
      (tester) async {
    final container = await mountMoneyApp(tester);
    final router = container.read(appRouterProvider);
    router.go('/accounts/acc-sam-bank');
    await tester.pumpAndSettle();
    expect(find.text('Sam Personal Card'), findsOneWidget);
    container.read(currentUserIdProvider.notifier).state = 'user-anna';
    await tester.pumpAndSettle();
    expect(find.text('Account unavailable'), findsOneWidget);
    expect(find.text('Sam Personal Card'), findsNothing);
    expect(find.text('Edit account'), findsNothing);
    router.go('/accounts/missing');
    await tester.pumpAndSettle();
    expect(find.text('Account unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
