import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/router.dart';
import 'package:duo_wallet/theme.dart';
import 'package:duo_wallet/features/transactions/presentation/transactions_screen.dart';
import 'package:duo_wallet/features/transfers/presentation/transfer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Use the fonts bundled with the active SDK: Ahem does not model real label widths.
Future<void> loadUiFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final config =
        jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
            as Map<String, dynamic>;
    final packages = config['packages'] as List;
    final flutter = packages.firstWhere((p) => p['name'] == 'flutter') as Map;
    final packageUri = File('.dart_tool/package_config.json')
        .absolute
        .uri
        .resolve(flutter['rootUri'] as String);
    final sdk = Directory.fromUri(packageUri).parent.parent;
    for (final font in [
      ('Roboto', 'Roboto-Regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf')
    ]) {
      final bytes =
          File('${sdk.path}/bin/cache/artifacts/material_fonts/${font.$2}')
              .readAsBytesSync();
      final loader = FontLoader(font.$1)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });
}

Future<void> pumpUi(WidgetTester tester) async {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint(details.toString());
    previous?.call(details);
  };
  try {
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previous;
  }
}

Future<void> captureUi(WidgetTester tester, GlobalKey boundary,
    String directory, String name) async {
  await tester.runAsync(() async {
    Directory(directory).createSync(recursive: true);
    final shot = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
    File('$directory/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    shot.dispose();
  });
}

const auditRoutes = [
  '/',
  '/transactions',
  '/accounts',
  '/accounts/acc-common',
  '/stats',
  '/budgets',
  '/settle-up',
  '/goals',
  '/savings',
  '/recurring',
  '/history',
  '/categories',
  '/activity',
  '/export',
  '/settings',
  '/auth'
];

void main() {
  for (final config in [
    (360.0, 800.0, 1.0, 'en'),
    (320.0, 640.0, 1.0, 'hu'),
    (320.0, 640.0, 1.5, 'hu'),
    (360.0, 800.0, 2.0, 'en'),
    (320.0, 568.0, 2.0, 'hu')
  ]) {
    testWidgets(
        'all routes fit ${config.$1}x${config.$2} ${config.$4} text ${config.$3}',
        (tester) async {
      await loadUiFonts(tester);
      final previousShadows = debugDisableShadows;
      final capture = (Platform.environment['DUO_UI_EVIDENCE_DIR'] ??
              const String.fromEnvironment('DUO_UI_EVIDENCE_DIR'))
          .isNotEmpty;
      if (capture) debugDisableShadows = false;
      try {
        tester.view.physicalSize = Size(config.$1, config.$2);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.read(appLocaleProvider.notifier).state = config.$4;
        final boundary = GlobalKey();
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child:
                RepaintBoundary(key: boundary, child: const DuoWalletApp())));
        await pumpUi(tester);
        for (final route in auditRoutes) {
          container.read(appRouterProvider).go(route);
          await pumpUi(tester);
          expect(tester.takeException(), isNull, reason: '$route at $config');
          final evidenceDir = Platform.environment['DUO_UI_EVIDENCE_DIR'] ??
              const String.fromEnvironment('DUO_UI_EVIDENCE_DIR');
          if (evidenceDir.isNotEmpty && config.$3 == 1) {
            final name = route == '/'
                ? 'dashboard'
                : route.substring(1).replaceAll('/', '_');
            await captureUi(
                tester, boundary, evidenceDir, '${config.$4}_$name');
          }
          final lists = find.byType(ListView).hitTestable();
          if (lists.evaluate().isNotEmpty) {
            for (var i = 0; i < 5; i++) {
              await tester.drag(lists.first, const Offset(0, -450));
              await pumpUi(tester);
              expect(tester.takeException(), isNull,
                  reason: 'scroll $i of $route at $config');
            }
          }
        }
        container.read(themeModeProvider.notifier).state = ThemeMode.dark;
        container.read(appRouterProvider).go('/');
        await pumpUi(tester);
        expect(tester.takeException(), isNull,
            reason: 'dark dashboard at $config');
        final evidenceDir = Platform.environment['DUO_UI_EVIDENCE_DIR'] ??
            const String.fromEnvironment('DUO_UI_EVIDENCE_DIR');
        if (evidenceDir.isNotEmpty && config.$3 == 1) {
          final list = find.byType(ListView).hitTestable();
          if (list.evaluate().isNotEmpty) {
            for (var i = 0; i < 5; i++) {
              await tester.drag(list.first, const Offset(0, 700));
              await pumpUi(tester);
            }
          }
          await captureUi(
              tester, boundary, evidenceDir, '${config.$4}_dashboard_dark');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDisableShadows = previousShadows;
      }
    });
  }

  for (final transfer in [false, true]) {
    testWidgets(
        '${transfer ? 'transfer' : 'transaction'} sheet fits with keyboard and large Hungarian text',
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
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appLocaleProvider.notifier).state = 'hu';
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container, child: const DuoWalletApp()));
      await pumpUi(tester);
      final context = tester.element(find.byType(Scaffold).last);
      if (transfer) {
        TransferSheet.show(context);
      } else {
        QuickAddTransactionSheet.show(context);
      }
      await pumpUi(tester);
      expect(tester.takeException(), isNull);
      final scroll = find.byType(SingleChildScrollView).hitTestable();
      if (scroll.evaluate().isNotEmpty) {
        for (var i = 0; i < 8; i++) {
          await tester.drag(scroll.last, const Offset(0, -250));
          await pumpUi(tester);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
