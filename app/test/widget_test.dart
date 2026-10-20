import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/domain/views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'DuoWalletApp navigates across Dashboard, Transactions (3 views), Settle Up, and switches EN <-> HU',
    (WidgetTester tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const DuoWalletApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Dashboard loads with default English strings and overview cards
      expect(find.textContaining('Duo Wallet'), findsWidgets);
      expect(find.text('Transactions'), findsWidgets);

      // 2. Navigate to Transactions tab via bottom NavigationBar
      await tester.tap(find.text('Transactions').last);
      await tester.pumpAndSettle();

      expect(
        find.byType(SegmentedButton<ExpenseView>),
        findsOneWidget,
      );
      expect(find.text('Together Expenses (Full Amount)'), findsOneWidget);

      // Switch to Individual view tab
      await tester.tap(find.text('Individual'));
      await tester.pumpAndSettle();
      expect(
        find.text('My Individual Expenses (🔒 Private)'),
        findsOneWidget,
      );

      // Switch to My Total view tab
      await tester.tap(find.text('My Total'));
      await tester.pumpAndSettle();
      expect(
        find.text('My Total (Individual + My Share of Together)'),
        findsOneWidget,
      );

      // 3. Navigate to Settle Up tab
      await tester.tap(find.text('Settle Up').last);
      await tester.pumpAndSettle();
      expect(find.text('Propose Settlement'), findsOneWidget);

      // 4. Switch language EN -> HU and verify Hungarian localization
      container.read(appLocaleProvider.notifier).state = 'hu';
      await tester.pumpAndSettle();

      expect(find.text('Elszámolás kezdeményezése'), findsOneWidget);
      expect(find.text('Tranzakciók'), findsWidgets);

      // Switch back HU -> EN
      container.read(appLocaleProvider.notifier).state = 'en';
      await tester.pumpAndSettle();
      expect(find.text('Propose Settlement'), findsOneWidget);
    },
  );
}
