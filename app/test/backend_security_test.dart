import 'dart:convert';
import 'dart:io';
import 'package:duo_wallet/core/auth/encrypted_cache_store.dart';
import 'package:duo_wallet/app.dart';
import 'package:duo_wallet/core/auth/backend_session.dart';
import 'package:duo_wallet/core/auth/password_policy.dart';
import 'package:duo_wallet/core/auth/secure_store.dart';
import 'package:duo_wallet/core/db/app_database.dart';
import 'package:duo_wallet/core/sync/supabase_adapter.dart';
import 'package:duo_wallet/core/sync/sync_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class RecordingRemote implements RemoteSyncAdapter {
  Future<void> Function(String, Map<String, dynamic>)? onWrite;
  @override
  Future<void> upsertRows(String table, List<Map<String, dynamic>> rows) async {
    for (final row in rows) {
      await onWrite?.call(table, row);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchChangedRows(
          String table, DateTime? since) async =>
      [];
}

void main() {
  test('email and strong-password policy rejects invalid and oversized input',
      () {
    expect(isValidEmail(' user@example.com '), isTrue);
    for (final s in [
      '',
      'a@',
      'a b@example.com',
      '@example.com',
      'a@example'
    ]) {
      expect(isValidEmail(s), isFalse);
    }
    expect(isStrongPassword('Example-Strong-Password9'), isTrue);
    for (final s in [
      '',
      'shortA1!',
      'longlowercaseonly123!',
      'LONGUPPERCASE123!',
      'NoNumbersHere!',
      'NoSymbolsHere123',
      'A1!${'é' * 40}'
    ]) {
      expect(isStrongPassword(s), isFalse, reason: s);
    }
  });

  test(
      'financial cache is authenticated-encrypted with fresh nonces and tamper rejection',
      () async {
    final directory = await Directory.systemTemp.createTemp('duo-cache-test-');
    try {
      final keys = MemorySecureStore();
      final cache = EncryptedCacheStore(keys: keys, directory: directory);
      const key = 'duo.project.data.user-a';
      const value = '{"merchant":"Private bank secret", "amount":12345}';
      await cache.write(key, value);
      final file = directory.listSync().whereType<File>().single;
      final first = await file.readAsBytes();
      expect(utf8.decode(first, allowMalformed: true),
          isNot(contains('Private bank secret')));
      expect(keys.values.values, isNot(contains(value)));
      expect(await cache.read(key), value);
      await cache.write(key, value);
      final second = await file.readAsBytes();
      expect(second, isNot(first));
      second[second.length - 1] ^= 1;
      await file.writeAsBytes(second);
      await expectLater(cache.read(key), throwsA(anything));
      expect(await cache.read('duo.project.data.user-b'), isNull);
      await cache.delete(key);
      expect(await cache.read(key), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('session keys are scoped to project and never store raw passwords',
      () async {
    final store = MemorySecureStore();
    final a = SecureSessionStorage(store, 'https://one.supabase.co');
    final b = SecureSessionStorage(store, 'https://two.supabase.co');
    await a.persistSession('{"access_token":"test-token"}');
    expect(await a.hasAccessToken(), isTrue);
    expect(await b.hasAccessToken(), isFalse);
    await a.removePersistedSession();
    expect(await a.accessToken(), isNull);
  });

  test(
      'encrypted-cache payload retains tombstones and exact queued versions across restart',
      () {
    final db = AppDatabase();
    final original = db.transactions.first;
    db.softDeleteTransaction(original.id);
    final snapshot =
        jsonDecode(jsonEncode(db.exportLocalState())) as Map<String, dynamic>;
    final restarted = AppDatabase(seedDemo: false);
    restarted.restoreLocalState(snapshot, meId: 'user-sam');
    expect(restarted.transactions.any((e) => e.id == original.id), isFalse);
    expect(restarted.pendingOutbox.map((e) => e.id),
        db.pendingOutbox.map((e) => e.id));
    expect((restarted.exportLocalState()['data'] as Map)['transactions'],
        (snapshot['data'] as Map)['transactions']);
  });

  test('no adapter and failed server writes never acknowledge unsaved changes',
      () async {
    final db = AppDatabase();
    db.upsertAccount(db.accounts.first);
    final id = db.pendingOutbox.single.id;
    expect(await SyncEngine(db: db).pushOutbox(), 0);
    expect(db.pendingOutbox.single.id, id);
    final remote = RecordingRemote()
      ..onWrite = (_, __) async {
        throw StateError('offline');
      };
    await expectLater(
        SyncEngine(db: db, remote: remote).pushOutbox(), throwsStateError);
    expect(db.pendingOutbox.single.id, id);
  });

  test('server acknowledgement cannot discard a newer concurrent edit',
      () async {
    final db = AppDatabase();
    final account = db.accounts.first;
    db.upsertAccount(account);
    final old = db.pendingOutbox.single.id;
    final remote = RecordingRemote()
      ..onWrite = (_, __) async {
        db.upsertAccount(account);
      };
    await SyncEngine(db: db, remote: remote).pushOutbox();
    expect(db.pendingOutbox, hasLength(1));
    expect(db.pendingOutbox.single.id, isNot(old));
  });

  test(
      'session change prevents an in-flight write from acknowledging another session',
      () async {
    final db = AppDatabase();
    db.upsertAccount(db.accounts.first);
    var current = true;
    final remote = RecordingRemote()
      ..onWrite = (_, __) async {
        current = false;
      };
    await expectLater(
        SyncEngine(db: db, remote: remote, isCurrent: () => current)
            .pushOutbox(),
        throwsStateError);
    expect(db.pendingOutbox, hasLength(1));
  });

  test(
      'remote model mappings preserve shares, recurring dates and native goal amounts',
      () {
    final db = AppDatabase();
    final txn = db.transactions.first;
    final remote = SupabaseSyncAdapter.toRemote('transactions', txn.toJson());
    expect(remote.containsKey('shares'), isFalse);
    remote['transaction_shares'] = [
      for (final e in txn.shares.entries)
        {
          'user_id': e.key,
          'share_minor': e.value,
          'share_base_minor': txn.baseShares[e.key]
        }
    ];
    final restored = SupabaseSyncAdapter.fromRemote('transactions', remote);
    expect(restored['shares'], txn.shares);
    expect(restored['base_shares'], txn.baseShares);
    for (final table in ['recurring_rules', 'goals']) {
      final source = table == 'goals'
          ? db.goals.first.toJson()
          : db.recurringRules.first.toJson();
      final row = SupabaseSyncAdapter.fromRemote(
          table, SupabaseSyncAdapter.toRemote(table, source));
      for (final e in source.entries) {
        expect(row[e.key], e.value, reason: '$table ${e.key}');
      }
    }
  });

  testWidgets(
      'production without configuration fails closed instead of showing demo money',
      (tester) async {
    final backend = BackendSession(
        client: null,
        store: MemorySecureStore(),
        projectUrl: 'https://missing.supabase.co');
    await backend.initialize();
    await tester.pumpWidget(ProviderScope(overrides: [
      productionModeProvider.overrideWithValue(true),
      backendSessionProvider.overrideWith((ref) => backend)
    ], child: const DuoWalletApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cloud connection is not configured'),
        findsOneWidget);
    expect(find.text('Hi, Sam'), findsNothing);
    expect(find.byIcon(Icons.receipt_long_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
