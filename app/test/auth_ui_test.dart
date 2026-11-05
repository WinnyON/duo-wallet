import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/auth/backend_session.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_security_test.dart' show MemorySecureStore;
import 'ux_review_probe_test.dart' show loadUiFonts;

Future<void> tapAuthButton(WidgetTester tester, Finder button) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(button, 120,
      scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in ['en', 'hu']) {
    testWidgets(
        'real auth forms validate and fit keyboard at 320px/200% $locale',
        (tester) async {
      await loadUiFonts(tester);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final client = (await tester.runAsync(() async => SupabaseClient(
          'https://unit.supabase.co', 'public-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false))))!;
      final backend = BackendSession(
          client: client,
          store: MemorySecureStore(),
          projectUrl: 'https://unit.supabase.co');
      await backend.initialize();
      try {
        await tester.pumpWidget(ProviderScope(overrides: [
          productionModeProvider.overrideWithValue(true),
          backendSessionProvider.overrideWith((ref) => backend),
          appLocaleProvider.overrideWith((ref) => locale)
        ], child: const DuoWalletApp()));
        await tester.pumpAndSettle();
        expect(find.text('Hi, Sam'), findsNothing);
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.first, 'not-an-email');
        await tester.enterText(fields.at(1), 'weak');
        await tapAuthButton(
            tester,
            find.widgetWithText(
                FilledButton, locale == 'en' ? 'Sign in' : 'Bejelentkezés'));
        expect(
            find.text(locale == 'en'
                ? 'Enter a valid email address.'
                : 'Adj meg érvényes e-mail-címet.'),
            findsOneWidget);
        expect(backend.user, isNull);
        expect(backend.db.transactions, isEmpty);
        await tapAuthButton(
            tester,
            find.widgetWithText(TextButton,
                locale == 'en' ? 'Create an account' : 'Fiók létrehozása'));
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(tester.takeException(), isNull);
        backend.recovery = true;
        backend.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNWidgets(2));
        await tester.enterText(
            find.byType(TextFormField).first, 'Example-Strong-Password9');
        await tester.enterText(
            find.byType(TextFormField).last, 'Different-Password9');
        await tapAuthButton(
            tester,
            find.widgetWithText(FilledButton,
                locale == 'en' ? 'Save password' : 'Jelszó mentése'));
        expect(
            find.text(locale == 'en'
                ? 'Passwords must match.'
                : 'A jelszavaknak egyezniük kell.'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(client.dispose);
      }
    });
  }
}
