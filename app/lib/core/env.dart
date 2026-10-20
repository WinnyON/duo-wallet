class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://placeholder.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'placeholder-anon-key',
  );
  static const releaseManifestUrl = String.fromEnvironment(
    'RELEASE_MANIFEST_URL',
    defaultValue: 'https://placeholder.supabase.co/storage/v1/object/public/releases/latest.json',
  );

  static bool get isConfigured =>
      !supabaseUrl.contains('placeholder.supabase.co') &&
      supabaseAnonKey != 'placeholder-anon-key';
}
