import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecureStore implements SecureStore {
  const DeviceSecureStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

String projectStoragePrefix(String url) =>
    'duo.${sha256.convert(utf8.encode(url)).toString().substring(0, 20)}';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.store, String projectUrl)
      : key = '${projectStoragePrefix(projectUrl)}.session';
  final SecureStore store;
  final String key;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() => store.read(key);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) =>
      store.write(key, persistSessionString);
  @override
  Future<void> removePersistedSession() => store.delete(key);
}

class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this.store, String projectUrl)
      : prefix = '${projectStoragePrefix(projectUrl)}.pkce.';
  final SecureStore store;
  final String prefix;
  @override
  Future<String?> getItem({required String key}) => store.read('$prefix$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      store.write('$prefix$key', value);
  @override
  Future<void> removeItem({required String key}) => store.delete('$prefix$key');
}
