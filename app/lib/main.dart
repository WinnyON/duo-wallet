import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'app.dart';
import 'core/auth/backend_session.dart';
import 'core/auth/secure_store.dart';
import 'core/auth/encrypted_cache_store.dart';
import 'core/db/app_database.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Env.demoMode) {
    runApp(const ProviderScope(child: DuoWalletApp()));
    return;
  }
  const store = DeviceSecureStore();
  SupabaseClient? client;
  if (Env.isConfigured) {
    try {
      await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabaseAnonKey,
        authOptions: FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          localStorage: SecureSessionStorage(store, Env.supabaseUrl),
          pkceAsyncStorage: SecurePkceStorage(store, Env.supabaseUrl),
        ),
      );
      client = Supabase.instance.client;
    } catch (_) {
      // Fail closed: initialization failure must never select demo financial data.
    }
  }
  SecureStore cacheStore = store;
  try {
    final support = await getApplicationSupportDirectory();
    cacheStore = EncryptedCacheStore(
        keys: store, directory: Directory('${support.path}/duo-cache'));
  } catch (_) {
    client = null;
  }
  final session = BackendSession(
      client: client, store: cacheStore, projectUrl: Env.supabaseUrl);
  runApp(ProviderScope(overrides: [
    productionModeProvider.overrideWithValue(true),
    backendSessionProvider.overrideWith((ref) => session),
    appDatabaseProvider.overrideWithValue(session.db),
    appLocaleProvider.overrideWith((ref) => ref.watch(backendSessionProvider.select((s) => s.db.findProfile(s.userId ?? '')?.locale ?? 'en'))),
    currentUserIdProvider
        .overrideWith((ref) => ref.watch(backendSessionProvider).userId ?? ''),
    partnerUserIdProvider
        .overrideWith((ref) => ref.watch(backendSessionProvider).partnerId),
  ], child: const DuoWalletApp()));
  unawaited(session.initialize());
}
