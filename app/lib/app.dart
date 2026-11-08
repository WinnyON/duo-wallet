import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/db/app_database.dart';
import 'core/auth/backend_session.dart';
import 'core/auth/backend_gate.dart';
import 'core/l10n/generated/app_localizations.dart';
import 'router.dart';
import 'theme.dart';

class DuoWalletApp extends ConsumerWidget {
  const DuoWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final localeCode = ref.watch(appLocaleProvider);

    return MaterialApp.router(
      title: 'Duo Wallet',
      builder: (context, child) => ref.watch(productionModeProvider)
          ? Navigator(
              pages: [MaterialPage(child: BackendGate(child: child!))],
              onDidRemovePage: (_) {},
            )
          : child!,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      locale: Locale(localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
