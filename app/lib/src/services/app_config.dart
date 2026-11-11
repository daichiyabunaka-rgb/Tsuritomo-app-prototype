/// アプリの実行時設定。
/// Supabase の接続情報は --dart-define で渡す:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// 未指定の場合はモックモード（端末内データ）で動作する。
/// publishable key は公開鍵（RLS で保護される）なのでアプリに埋め込めるが、
/// サービスロールキー（sb_secret_...）は絶対に渡さないこと。
class AppConfig {
  /// 共有Supabaseプロジェクト内でこのアプリを識別するID。
  /// 犬とも！・飯とも！と同一プロジェクト・同一アカウント（auth.users）
  /// を共有し、プロフィール・募集・コミュニティ等のデータはこの
  /// app_idで分離する（docs/supabase_multiapp_migration.sql 参照）。
  static const String appId = 'tsuritomo';

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // 旧形式の anon key との互換
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get effectiveKey => supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;

  /// Google Maps SDK 用の API キー（未指定の場合は OpenStreetMap で表示）
  static const String googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// AI接客はベータ期間中ロック（本リリース後にビジネスプランとして解放）
  static const bool aiConciergeEnabled = false;

  /// Supabase が設定されているか（false = モックモード）
  static bool get useSupabase =>
      supabaseUrl.isNotEmpty && effectiveKey.isNotEmpty;
}
