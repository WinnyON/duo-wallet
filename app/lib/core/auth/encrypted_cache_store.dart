import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'secure_store.dart';

/// Financial snapshots live in authenticated-encrypted private files, rather
/// than large platform-channel/SharedPreferences values. Only their keys enter
/// the OS keystore. Each successful write atomically replaces the old snapshot.
class EncryptedCacheStore implements SecureStore {
  EncryptedCacheStore({required this.keys, required this.directory});
  final SecureStore keys;
  final Directory directory;
  final _cipher = AesGcm.with256bits();
  bool _isSnapshot(String key) => key.contains('.data.');
  File _file(String key) =>
      File('${directory.path}/${sha256.convert(utf8.encode(key))}.enc');

  Future<SecretKey> _key(String key, {required bool create}) async {
    final saved = await keys.read('$key.key');
    if (saved != null) return SecretKey(base64Decode(saved));
    if (!create) throw StateError('Secure cache key unavailable');
    final generated = await _cipher.newSecretKey();
    await keys.write('$key.key', base64Encode(await generated.extractBytes()));
    return generated;
  }

  @override
  Future<String?> read(String key) async {
    if (!_isSnapshot(key)) return keys.read(key);
    final file = _file(key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.first != 1) {
      throw const FormatException('Unsupported encrypted cache');
    }
    final box = SecretBox.fromConcatenation(bytes.sublist(1),
        nonceLength: 12, macLength: 16);
    return utf8.decode(
        await _cipher.decrypt(box, secretKey: await _key(key, create: false)));
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_isSnapshot(key)) return keys.write(key, value);
    await directory.create(recursive: true);
    final box = await _cipher.encrypt(utf8.encode(value),
        secretKey: await _key(key, create: true));
    final temporary = File('${_file(key).path}.tmp');
    await temporary.writeAsBytes([1, ...box.concatenation()], flush: true);
    await temporary.rename(_file(key).path);
  }

  @override
  Future<void> delete(String key) async {
    if (!_isSnapshot(key)) return keys.delete(key);
    final file = _file(key);
    if (await file.exists()) await file.delete();
    await keys.delete('$key.key');
  }
}
