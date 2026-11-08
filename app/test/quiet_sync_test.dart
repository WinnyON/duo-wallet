import 'package:duo_wallet/core/auth/backend_session.dart';
import 'package:duo_wallet/core/auth/cloud_status.dart';
import 'package:duo_wallet/core/db/tables/tables.dart';
import 'package:duo_wallet/core/l10n/generated/app_localizations.dart';
import 'package:duo_wallet/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'backend_security_test.dart' show MemorySecureStore;

class CountingSession extends BackendSession {
  CountingSession()
      : super(
            client: null,
            store: MemorySecureStore(),
            projectUrl: 'https://unit.supabase.co');
  int syncCalls = 0;
  bool polling = false;
  @override
  bool get verified => true;
  @override
  String get userId => 'test-user';
  @override
  bool get syncing => polling;
  @override
  Future<void> syncNow() async {
    syncCalls++;
  }
}

void main() {
  testWidgets(
      'remote database notifications do not schedule another sync; local edits do',
      (tester) async {
    final session = CountingSession();
    await session.initialize();
    final household =
        Household(id: 'household', name: 'Home', createdAt: DateTime(2026));
    session.db.upsertHousehold(household, fromSync: true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(session.syncCalls, 0);
    session.db.upsertHousehold(household);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(session.syncCalls, 1);
    session.dispose();
  });

  testWidgets('home hides routine polling but retains actionable sync failures',
      (tester) async {
    final session = CountingSession();
    await session.initialize();
    await tester.pumpWidget(ProviderScope(
        overrides: [backendSessionProvider.overrideWith((ref) => session)],
        child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [AppLocalizations.delegate],
            home: const Scaffold(body: CloudStatusCard(compact: true)))));
    expect(find.text('Cloud up to date'), findsNothing);
    session.polling = true;
    session.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Syncing'), findsNothing);
    expect(find.byType(Text), findsNothing);
    session.error = 'offline';
    session.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Cloud connection needs attention'),
        findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
