import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
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

      // 1. Dashboard loads with the focused spending overview
      expect(find.text('Together this month'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);

      // 2. Navigate to Transactions tab via icon-only bottom bar
      await tester.tap(find.byIcon(Icons.receipt_long_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('All-time spending · current filters'), findsOneWidget);

      // Switch to Personal view tab
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Personal'))
              .selected,
          isTrue);

      // Switch to All Mine view tab
      await tester.tap(find.text('All Mine'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All Mine'))
              .selected,
          isTrue);

      // 3. Navigate to Settle Up tab via icon-only bottom bar
      await tester.tap(find.byIcon(Icons.handshake_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Propose settlement'), findsOneWidget);

      // 4. Switch language EN -> HU and verify Hungarian localization
      container.read(appLocaleProvider.notifier).state = 'hu';
      await tester.pumpAndSettle();

      expect(find.text('Elszámolás kezdeményezése'), findsOneWidget);

      // Switch back HU -> EN
      container.read(appLocaleProvider.notifier).state = 'en';
      await tester.pumpAndSettle();
      expect(find.text('Propose settlement'), findsOneWidget);
    },
  );
}
