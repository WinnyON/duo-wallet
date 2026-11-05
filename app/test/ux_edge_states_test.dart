import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ux_review_probe_test.dart' show auditRoutes, loadUiFonts;

const extremeMinor = 9876543210123;
final longName = List.filled(8, 'Árvíztűrő👩🏽‍💻家族').join();
final longNote = List.filled(30,
        'Hosszú megjegyzés: árvíztűrő tükörfúrógép, részletek és címkék 👨‍👩‍👧‍👦.')
    .join(' ');

AppDatabase extremeDatabase() {
  final db = AppDatabase();
  final household = db.household!;
  db.upsertHousehold(
      Household.fromJson({...household.toJson(), 'name': longName}));
  for (final profile in db.profiles) {
    db.upsertProfile(Profile.fromJson({
      ...profile.toJson(),
      'display_name': '${profile.id} $longName',
      'monthly_common_contribution_minor': extremeMinor,
      'avatar_type': 'initials',
    }));
  }
  for (var i = 0; i < db.accounts.length; i++) {
    final account = db.accounts[i];
    db.upsertAccount(Account.fromJson({
      ...account.toJson(),
      'name': longName,
      'opening_balance_minor': i.isEven ? extremeMinor : -extremeMinor,
    }));
  }
  for (final category in db.categories) {
    db.upsertCategory(Category.fromJson({
      ...category.toJson(),
      'name_en': longName,
      'name_hu': longName,
    }));
  }
  for (final budget in db.budgets) {
    db.upsertBudget(
        Budget.fromJson({...budget.toJson(), 'amount_minor': extremeMinor}));
  }
  for (final goal in db.goals) {
    db.upsertGoal(Goal.fromJson({
      ...goal.toJson(),
      'name': longName,
      'target_amount_minor': extremeMinor,
      'saved_amount_minor': extremeMinor ~/ 3,
    }));
  }
  for (final rule in db.recurringRules) {
    db.upsertRecurringRule(RecurringRule.fromJson({
      ...rule.toJson(),
      'title': longName,
      'amount_minor': extremeMinor,
    }));
  }
  for (final transaction in db.transactions) {
    db.saveTransaction(transaction.copyWith(
      merchant: longName,
      note: longNote,
      tags: [longName, '餐飲👩🏽‍💻'],
      occurredOn: DateTime.now(),
      amountMinor: extremeMinor,
      baseAmountMinor: extremeMinor,
      accountAmountMinor: extremeMinor,
      baseShares: {
        'user-sam': extremeMinor ~/ 2,
        'user-anna': extremeMinor - extremeMinor ~/ 2
      },
      shares: {
        'user-sam': extremeMinor ~/ 2,
        'user-anna': extremeMinor - extremeMinor ~/ 2
      },
    ));
  }
  db.addActivity(ActivityEvent(
    id: 'extreme-activity',
    householdId: household.id,
    actorId: 'user-sam',
    eventType: 'expense_added',
    summaryEn: longNote,
    summaryHu: longNote,
    amountMinor: extremeMinor,
    createdAt: DateTime.now(),
  ));
  return db;
}

void main() {
  for (final empty in [true, false]) {
    testWidgets(
        '${empty ? 'empty local data' : 'long names and extreme signed amounts'} fit all 16 routes at HU320/1.5',
        (tester) async {
      await loadUiFonts(tester);
      final db = empty ? AppDatabase(seedDemo: false) : extremeDatabase();
      final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)]);
      final initialTransactions =
          db.transactions.map((t) => t.toJson()).toList();
      final initialAccounts = db.accounts.map((a) => a.toJson()).toList();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      try {
        container.read(appLocaleProvider.notifier).state = 'hu';
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container, child: const DuoWalletApp()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'initial dashboard');
        final router = container.read(appRouterProvider);
        for (final route in auditRoutes) {
          router.go(route);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${empty ? 'empty' : 'extreme'} $route initial viewport');
          // Lazy lists must also lay out the lower settings/profile/history rows.
          for (var scroll = 0; scroll < 6; scroll++) {
            final lists = find.byType(ListView).hitTestable();
            if (lists.evaluate().isEmpty) break;
            await tester.drag(lists.first, const Offset(0, -420));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${empty ? 'empty' : 'extreme'} $route scroll $scroll');
          }
        }
        // Visiting a missing household must not silently create demo identities/data;
        // inspecting extreme fixtures must not rewrite their signed balances/entries.
        expect(db.transactions.map((t) => t.toJson()).toList(),
            initialTransactions);
        expect(db.accounts.map((a) => a.toJson()).toList(), initialAccounts);
        if (empty) {
          expect(db.household, isNull);
          expect(db.profiles, isEmpty);
          expect(db.categories, isEmpty);
          expect(db.goals, isEmpty);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        container.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  }
}
