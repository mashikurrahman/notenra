
import '../secure_store.dart';

/// Holds the backend base URL — the single source of truth for where the app
/// sends PHI.
///
/// The value is chosen at BUILD time via `--dart-define=API_BASE_URL=…`, so a
/// dev/staging/production build can be pointed at a different server without a
/// code change:
///
///   flutter build apk --dart-define=API_BASE_URL=https://api.example.com/api
///
/// The URL must include whatever path prefix the server mounts its routes
/// under (the app appends bare paths like `/visits`), and must be HTTPS —
/// cleartext is blocked at the platform level on both Android
/// (`usesCleartextTraffic="false"`) and iOS (App Transport Security).
///
/// There is deliberately no release UI for changing this: a clinician-editable
/// server field would let PHI uploads be redirected to an arbitrary host. The
/// [setBaseUrl] override exists for debug/QA builds only.
class ApiConfig {
  static const _secure = SecureStore();
  static const _key = 'api_base_url';

  /// Compile-time default. Falls back to the Anot Health production API when no
  /// `API_BASE_URL` define is passed, so existing builds are unaffected.
  static const defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://app.anot.health/api',
  );

  static String _baseUrl = defaultBaseUrl;
  static String get baseUrl => _baseUrl;

  /// True when a debug/QA override is in effect rather than the built-in value.
  static bool get isOverridden => _baseUrl != defaultBaseUrl;

  /// Host of the active server, for read-only display in the UI (support needs
  /// to be able to ask "which server is this device on?"). Never the full URL
  /// with path — the host is the part that matters and the part that fits.
  static String get displayHost {
    final uri = Uri.tryParse(_baseUrl);
    final host = uri?.host;
    return (host == null || host.isEmpty) ? _baseUrl : host;
  }

  static Future<void> load() async {
    final saved = await _secure.read(key: _key);
    if (saved != null && saved.isNotEmpty) _baseUrl = saved;
  }

  static Future<void> setBaseUrl(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    _baseUrl = clean;
    await _secure.write(key: _key, value: clean);
  }

  /// Discard any saved override and return to the compiled-in default.
  static Future<void> clearOverride() async {
    _baseUrl = defaultBaseUrl;
    await _secure.delete(key: _key);
  }
}
