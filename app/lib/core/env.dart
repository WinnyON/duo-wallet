import 'dart:convert';
import 'package:flutter/foundation.dart';

class Env {
  static const demoMode = bool.fromEnvironment('DUO_DEMO_MODE');
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY',
          defaultValue: 'placeholder-anon-key'));
  static const releaseManifestUrl = String.fromEnvironment(
    'RELEASE_MANIFEST_URL',
    defaultValue:
        'https://placeholder.supabase.co/storage/v1/object/public/releases/latest.json',
  );

  static bool get isConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null || uri.host.isEmpty || uri.host.contains('placeholder')) {
      return false;
    }
    final local =
        kDebugMode && ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (uri.scheme != 'https' && !local) return false;
    if (supabaseAnonKey.startsWith('sb_publishable_')) return true;
    try {
      final payload = jsonDecode(utf8.decode(base64Url
          .decode(base64Url.normalize(supabaseAnonKey.split('.')[1]))));
      return payload['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }
}
