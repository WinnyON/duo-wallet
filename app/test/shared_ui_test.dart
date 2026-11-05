import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/features/auth/presentation/auth_screen.dart';
import 'package:duo_wallet/router.dart';
import 'package:duo_wallet/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ux_review_probe_test.dart' show loadUiFonts;

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

Future<ProviderContainer> mountApp(WidgetTester tester) async {
  await loadUiFonts(tester);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(appLocaleProvider.notifier).state = 'en';
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const DuoWalletApp(),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('masked activity never exposes stored prose, including legacy types',
      () {
    for (final type in [
      'expense_added',
      'income_added',
      'transaction_added',
      'transfer_added',
      'contribution_added',
      'goal_milestone',
      'settlement_proposed',
      'settlement_confirmed',
      'legacy_event',
    ]) {
      final event = ActivityEvent(
        id: type,
        householdId: 'household',
        actorId: 'actor',
        eventType: type,
        summaryEn: 'Shop 123: Anna paid 987654 HUF',
        summaryHu: 'Bolt 123: Anna fizetett 987654 Ft',
        amountMinor: 98765400,
        createdAt: DateTime(2026, 11, 4),
      );
      for (final locale in ['en', 'hu']) {
        final masked =
            activityDisplaySummary(event, locale: locale, hideAmounts: true);
        expect(masked, isNotEmpty);
        expect(masked, isNot(contains(RegExp(r'\d'))));
        expect(masked, isNot(contains('Anna')));
        expect(
            activityDisplaySummary(event, locale: locale, hideAmounts: false),
            event.localizedSummary(locale));
      }
    }
  });

  for (final theme in [AppTheme.light(), AppTheme.dark()]) {
    testWidgets(
        'functional tokens and solid badges have readable contrast ${theme.brightness}',
        (tester) async {
      final scheme = theme.colorScheme;
      final duo = theme.extension<DuoColors>()!;
      expect(contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5));
      expect(contrast(duo.muted, scheme.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(duo.positive, scheme.surface), greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(body: DuoBadge('Recorded', solid: true))));
      final text = tester.widget<Text>(find.text('Recorded'));
      final background = tester.widget<Container>(find
          .descendant(
              of: find.byType(DuoBadge), matching: find.byType(Container))
          .first);
      final decoration = background.decoration! as BoxDecoration;
      expect(contrast(text.style!.color!, decoration.color!),
          greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('Pressable is focusable and keyboard activation fires once',
      (tester) async {
    var calls = 0;
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
              body: Pressable(
            onTap: () => calls++,
            child: const Text('Open details'),
          ))));
      expect(tester.getSize(find.byType(InkWell)).height,
          greaterThanOrEqualTo(48));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(calls, 2);
      final node = tester.getSemantics(find.byType(InkWell));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Hungarian primary labels stay on one line at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = await mountApp(tester);
    container.read(appLocaleProvider.notifier).state = 'hu';
    await tester.pumpAndSettle();
    for (final label in [
      'Kezdő',
      'Tételek',
      'Számlák',
      'Elemzés',
      'Rendezés'
    ]) {
      final finder = find.text(label).last;
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: label.length));
      expect(boxes.map((b) => b.top).toSet(), hasLength(1), reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction search survives tab changes', (tester) async {
    final container = await mountApp(tester);
    container.read(appRouterProvider).go('/transactions');
    await tester.pumpAndSettle();
    final search =
        find.widgetWithText(TextField, 'Search merchant, note or tag');
    await tester.enterText(search, 'preserve this filter');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Accounts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Entries').last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text,
        'preserve this filter');
    expect(find.text('No matching transactions.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'every primary tab can open menu and reach goals budgets settings',
      (tester) async {
    final container = await mountApp(tester);
    final router = container.read(appRouterProvider);
    for (final primary in [
      '/',
      '/transactions',
      '/accounts',
      '/stats',
      '/settle-up'
    ]) {
      for (final destination in [
        ('Goals & Emergency Fund', '/goals'),
        ('Budgets', '/budgets'),
        ('Settings', '/settings')
      ]) {
        router.go(primary);
        await tester.pumpAndSettle();
        final menu = find.byWidgetPredicate((widget) =>
            widget is Icon &&
            (widget.icon == Icons.menu || widget.icon == Icons.menu_rounded));
        expect(menu, findsOneWidget, reason: primary);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        final tile = find.descendant(
            of: find.byType(Drawer),
            matching: find.widgetWithText(ListTile, destination.$1));
        await tester.scrollUntilVisible(tile, 180,
            scrollable: find
                .descendant(
                    of: find.byType(Drawer), matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(router.state.uri.path, destination.$2);
        expect(tester.takeException(), isNull,
            reason: '$primary → ${destination.$2}');
      }
    }
  });

  testWidgets(
      'profile Keep editing preserves exact draft and Discard leaves it unsaved',
      (tester) async {
    final container = await mountApp(tester);
    final db = container.read(appDatabaseProvider);
    final id = container.read(currentUserIdProvider);
    final previous = db.findProfile(id)!.displayName;
    final router = container.read(appRouterProvider);
    router.go('/auth');
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, 'Display name');
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Long draft 👩🏽‍💻 123');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    final field = tester.widget<TextFormField>(name);
    expect(field.controller!.text, 'Long draft 👩🏽‍💻 123');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(db.findProfile(id)!.displayName, previous);
    expect(tester.takeException(), isNull);
  });
}
