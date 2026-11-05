import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/features/transactions/presentation/transactions_screen.dart';
import 'package:duo_wallet/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'money_flows_test.dart' show mountMoneyApp, scaffoldContext, tapVisible;

void main() {
  for (final common in [false, true]) {
    testWidgets('solo transaction has valid owner shares on common=$common',
        (tester) async {
      final container = await mountMoneyApp(tester);
      container.read(partnerUserIdProvider.notifier).state = '';
      final db = container.read(appDatabaseProvider);
      final me = container.read(currentUserIdProvider);
      final account = db.accounts.firstWhere(
          (a) => a.isCommon == common && (common || a.ownerId == me));
      final before = db.transactions.map((t) => t.id).toSet();
      QuickAddTransactionSheet.show(scaffoldContext(tester),
          initialAccountId: account.id);
      await tester.pumpAndSettle();
      if (!common) {
        expect(
            tester
                .widget<ChoiceChip>(
                    find.widgetWithText(ChoiceChip, 'Shared').last)
                .onSelected,
            isNull);
        expect(
            tester
                .widget<ChoiceChip>(
                    find.widgetWithText(ChoiceChip, 'Personal').last)
                .selected,
            isTrue);
      }
      await tester.enterText(find.byType(TextFormField).first, '123.45');
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      final saved = db.transactions.singleWhere((t) => !before.contains(t.id));
      expect(saved.scope, common ? Scope.together : Scope.individual);
      expect(saved.shares, {me: saved.amountMinor});
      expect(saved.baseShares, {me: saved.baseAmountMinor});
      expect(tester.takeException(), isNull);
    });

    testWidgets('solo recurring form and generation on common=$common',
        (tester) async {
      final container = await mountMoneyApp(tester);
      container.read(partnerUserIdProvider.notifier).state = '';
      final db = container.read(appDatabaseProvider);
      final me = container.read(currentUserIdProvider);
      final account = db.accounts.firstWhere(
          (a) => a.isCommon == common && (common || a.ownerId == me));
      for (final rule in db.recurringRules) {
        db.upsertRecurringRule(RecurringRule.fromJson({
          ...rule.toJson(),
          'auto_create': false,
        }));
      }
      container.read(appRouterProvider).go('/recurring');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add rule'));
      await tester.pumpAndSettle();
      final segment = tester
          .widget<SegmentedButton<Scope>>(find.byType(SegmentedButton<Scope>));
      expect(segment.selected, {Scope.individual});
      expect(segment.segments.first.enabled, isFalse);
      await tester.enterText(find.byType(TextFormField).at(0), 'Solo bill');
      await tester.enterText(find.byType(TextFormField).at(1), '123.45');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(account.name).last);
      await tester.pumpAndSettle();
      await tapVisible(
          tester, find.byType(DropdownButtonFormField<String>).at(1));
      await tester.tap(find
          .text(db.categories.firstWhere((c) => c.kind == 'expense').nameEn)
          .last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Save'));
      final rule = db.recurringRules.singleWhere((r) => r.title == 'Solo bill');
      expect(rule.scope, common ? Scope.together : Scope.individual);
      expect(rule.splitPctCreator, 100);
      await tester.tap(find.text('Record due bills'));
      await tester.pumpAndSettle();
      final saved =
          db.transactions.singleWhere((t) => t.recurringRuleId == rule.id);
      expect(saved.scope, common ? Scope.together : Scope.individual);
      expect(saved.shares, {me: saved.amountMinor});
      expect(saved.baseShares, {me: saved.baseAmountMinor});
      expect(tester.takeException(), isNull);
    });
  }

  test('JSON instant timestamps are UTC while calendar dates retain their day',
      () {
    final db = AppDatabase();
    final local = DateTime(2026, 11, 5, 0, 30);
    final date = DateTime(2026, 11, 5);
    final account = Account.fromJson({
      ...db.accounts.first.toJson(),
      'opening_date': date.toIso8601String(),
      'maturity_date': date.toIso8601String(),
      'updated_at': local.toIso8601String(),
      'deleted_at': local.toIso8601String(),
    }).toJson();
    final transaction = Txn.fromJson({
      ...db.transactions.first.toJson(),
      'occurred_on': date.toIso8601String(),
      'created_at': local.toIso8601String(),
      'updated_at': local.toIso8601String(),
      'deleted_at': local.toIso8601String(),
    }).toJson();
    for (final json in [account, transaction]) {
      for (final key in ['created_at', 'updated_at', 'deleted_at']) {
        if (json.containsKey(key)) {
          expect(json[key], local.toUtc().toIso8601String(), reason: key);
        }
      }
    }
    expect(account['opening_date'], '2026-11-05');
    expect(account['maturity_date'], '2026-11-05');
    expect(transaction['occurred_on'], '2026-11-05');
  });
}
