import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../db/app_database.dart';
import '../sync/supabase_adapter.dart';
import '../sync/sync_engine.dart';
import 'secure_store.dart';

// main() explicitly enables production mode. Widget/domain previews can opt into
// the isolated demo without a real session or platform keystore.
final productionModeProvider = Provider<bool>((ref) => false);
final backendSessionProvider = ChangeNotifierProvider<BackendSession>(
    (ref) => throw StateError('Backend session not initialized'));

class BackendSession extends ChangeNotifier {
  BackendSession(
      {required this.client, required this.store, required this.projectUrl}) {
    _dbSubscription = db.changes.listen((_) {
      if (!_loading && verified) {
        unawaited(_saveAfterChange());
      }
    });
  }
  final SupabaseClient? client;
  final SecureStore store;
  final String projectUrl;
  final AppDatabase db =
      AppDatabase(seedDemo: false, serverManagedActivity: true);
  StreamSubscription<void>? _dbSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _debounce;
  Timer? _periodic;
  Future<void> _writes = Future.value();
  User? _user;
  bool _loading = true;
  bool _syncing = false;
  bool recovery = false;
  bool localSaveFailed = false;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  DateTime? lastSyncedAt;

  User? get user => _user;
  String? get userId => _user?.id;
  bool get verified => _user?.emailConfirmedAt != null;
  bool get loading => _loading;
  bool get syncing => _syncing;
  bool get configured => client != null;
  String get partnerId =>
      db.profiles
          .where((p) => p.id != userId && p.householdId == db.household?.id)
          .firstOrNull
          ?.id ??
      '';
  String _cacheKey(String uid) =>
      '${projectStoragePrefix(projectUrl)}.data.$uid';

  Future<void> initialize() async {
    if (client == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    _authSubscription = client!.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (state.session?.user.id != userId) {
        unawaited(_activate(state.session?.user));
      } else {
        _user = state.session?.user;
        notifyListeners();
      }
    });
    await _activate(client!.auth.currentUser);
    _periodic = Timer.periodic(const Duration(seconds: 30), (_) {
      if (verified && !_loading) unawaited(syncNow());
    });
  }

  Future<void> _activate(User? user) async {
    final generation = ++_generation;
    _debounce?.cancel();
    _loading = true;
    error = null;
    _user = user;
    lastSyncedAt = null;
    db.clear();
    notifyListeners();
    if (user == null || !verified) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      final saved = await store.read(_cacheKey(user.id));
      if (generation != _generation) return;
      if (saved != null) {
        db.restoreLocalState(
            Map<String, dynamic>.from(jsonDecode(saved) as Map),
            meId: user.id);
      }
      await syncNow();
    } catch (_) {
      if (generation == _generation) {
        error =
            'Secure local data could not be loaded. Sign out and try again.';
      }
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _persist() async {
    final uid = userId;
    if (uid == null || !verified) return;
    final key = _cacheKey(uid);
    final snapshot = jsonEncode(db.exportLocalState());
    final next =
        _writes.catchError((_) {}).then((_) => store.write(key, snapshot));
    _writes = next;
    try {
      await next;
      localSaveFailed = false;
    } catch (_) {
      localSaveFailed = true;
      rethrow;
    }
  }

  Future<void> _saveAfterChange() async {
    try {
      await _persist();
      if (!_syncing) {
        _debounce?.cancel();
        _debounce = Timer(
            const Duration(milliseconds: 500), () => unawaited(syncNow()));
      }
    } catch (_) {
      error =
          'Changes could not be saved securely on this device. Keep the app open and retry.';
    }
    notifyListeners();
  }

  Future<void> syncNow() async {
    if (!verified || client == null || _syncing) return;
    final generation = _generation;
    _syncing = true;
    notifyListeners();
    try {
      await _persist();
      final adapter = SupabaseSyncAdapter(client!);
      final engine = SyncEngine(
          db: db,
          remote: adapter,
          isCurrent: () => generation == _generation && verified);
      await engine.syncNow();
      if (generation != _generation) return;
      await _persist();
      error = null;
      lastSyncedAt = DateTime.now();
    } on AuthException {
      if (generation == _generation) {
        error = 'Your session needs attention. Sign in again to sync.';
      }
    } catch (_) {
      if (generation == _generation) {
        error = localSaveFailed
            ? 'Secure local storage failed. Keep the app open and retry.'
            : 'Cloud sync is unavailable. Changes remain queued on this device; retry when connected.';
      }
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> onboard(
      {required String displayName,
      required String householdName,
      String? inviteCode, String locale = 'en'}) async {
    if (!verified || client == null) {
      throw const AuthException('Verify your email first');
    }
    if (db.household != null) throw StateError('Already in a household');
    await client!.rpc(
        inviteCode == null ? 'create_household' : 'join_household',
        params: {
          if (inviteCode == null)
            'p_name': householdName.trim()
          else
            'p_invite_code': inviteCode.trim(),
          'p_display_name': displayName.trim(),
          'p_color': '#4F46E5',
        }).timeout(const Duration(seconds: 20));
    await client!.from('profiles').update({'locale': locale == 'hu' ? 'hu' : 'en'}).eq('id', userId!).select().single().timeout(const Duration(seconds:20));
    await syncNow();
    if (db.household == null) {
      throw StateError('Household could not be loaded; retry sync');
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    final uid = userId;
    ++_generation;
    _loading = true;
    _debounce?.cancel();
    notifyListeners();
    // Keep queued writes in this user's encrypted cache for the next sign-in,
    // but immediately remove all in-memory access and revoke the refresh token.
    try {
      await _persist();
    } finally {
      db.clear();
      _user = null;
      recovery = false;
      error = null;
      try {
        await client?.auth.signOut(scope: SignOutScope.local);
      } finally {
        _loading = false;
        notifyListeners();
      }
    }
    if (uid == null) return;
  }

  Future<void> retryLoad() => _activate(client?.auth.currentUser);
  Future<void> flushLocal() => _persist();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _periodic?.cancel();
    _debounce?.cancel();
    _authSubscription?.cancel();
    _dbSubscription?.cancel();
    super.dispose();
  }
}
