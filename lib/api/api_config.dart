
import '../secure_store.dart';

/// Holds the Anot Health backend base URL. Defaults to the production
/// CloudFront API from the platform docs; overridable in Settings.
class ApiConfig {
  static const _secure = SecureStore();
  static const _key = 'api_base_url';

  /// Production API (VITE_API_URL). Moved to the app.anot.health domain in the
  /// 2026-07-02 multi-portal SaaS restructure (was the CloudFront distribution
  /// URL, which now 502s).
  static const defaultBaseUrl = 'https://app.anot.health/api';

  static String _baseUrl = defaultBaseUrl;
  static String get baseUrl => _baseUrl;

  static Future<void> load() async {
    final saved = await _secure.read(key: _key);
    // Drop a stale saved override pointing at the retired CloudFront API so an
    // upgraded install isn't stranded on the dead host — fall back to the new
    // default. (A user-set custom URL to any other host is still honored.)
    if (saved != null &&
        saved.isNotEmpty &&
        !saved.contains('d3t0m4s0ayca85.cloudfront.net')) {
      _baseUrl = saved;
    }
  }

  static Future<void> setBaseUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    _baseUrl = clean;
    await _secure.write(key: _key, value: clean);
  }
}
