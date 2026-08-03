import 'package:dio/dio.dart';

import '../app_log.dart';
import 'api_config.dart';
import 'token_store.dart';

/// A failed API call, with a human-readable [message] the UI can show directly.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'ApiException(${statusCode ?? '-'}): $message';
}

/// Single Dio instance for the Anot Health backend.
///
/// Deliberately simple and predictable:
///   • attaches the JWT on every request,
///   • sends JSON by default but lets Dio switch to multipart/form-data for
///     audio uploads (a hard-coded JSON header would corrupt those),
///   • turns EVERY failure — HTTP or network — into an [ApiException] whose
///     message states the real reason, so the app never shows a vague guess.
class ApiClient {
  final TokenStore tokens;

  /// Called when the API returns 401 (token expired/invalid) so the app can
  /// return to the sign-in screen.
  void Function()? onUnauthorized;

  late final Dio dio;

  // CSRF double-submit protection (added server-side): a token fetched from
  // GET /csrf-token must be sent on every mutating request both as a cookie and
  // as the `x-csrf-token` header, with the two values matching. The token is
  // long-lived, so we fetch it once per app run and refresh on a CSRF 403.
  String? _csrfToken;
  String _csrfCookieName = '__Host-csrf_token';

  // The server now also issues the session JWT as an httpOnly cookie
  // (`__Host-anot_session` in prod, `anot_session` in dev) instead of in the
  // response body. It still accepts a Bearer token, so we extract the JWT from
  // the cookie and keep using Bearer.
  static final RegExp _sessionCookieRe = RegExp(r'anot_session=([^;]+)');

  /// Pull the session JWT out of a response's Set-Cookie header(s), if present.
  /// Matches both `__Host-anot_session=` and the dev `anot_session=`.
  static String? sessionJwtFromHeaders(Headers headers) {
    final cookies = headers.map['set-cookie'];
    if (cookies == null) return null;
    for (final c in cookies) {
      final m = _sessionCookieRe.firstMatch(c);
      final jwt = m?.group(1);
      if (jwt != null && jwt.isNotEmpty) return jwt;
    }
    return null;
  }

  ApiClient(this.tokens) {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      // JSON by default — but set via `contentType` (NOT a raw header) so Dio
      // can correctly override it with multipart/form-data (+boundary) when the
      // body is FormData (audio upload). A raw 'Content-Type: application/json'
      // header collides with the multipart header and breaks uploads.
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // Accept all status codes into onResponse so the interceptor classifies
      // them itself; only genuine network/timeout errors reach onError.
      validateStatus: (s) => s != null && s < 600,
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Keep the base URL in sync if it was changed in Settings.
        options.baseUrl = ApiConfig.baseUrl;
        // Attach the stored JWT — but NEVER clobber an Authorization header the
        // caller set explicitly (e.g. the short-lived temporary token used for
        // the forced first-login password change). Overwriting it with a stale
        // session token makes the server reject the request as "invalid token".
        final hasExplicitAuth =
            options.headers.keys.any((k) => k.toLowerCase() == 'authorization');
        final t = tokens.token;
        if (t != null && t.isNotEmpty && !hasExplicitAuth) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        // Attach the CSRF token to mutating requests (the token fetch itself is
        // a GET and is skipped to avoid recursion).
        if (_isMutating(options.method) &&
            !options.path.contains('/csrf-token')) {
          final tok = await _ensureCsrf();
          if (tok != null) {
            options.headers['x-csrf-token'] = tok;
            options.headers['Cookie'] = '$_csrfCookieName=$tok';
          }
        }
        final isForm = options.data is FormData;
        AppLog.log('HTTP',
            '→ ${options.method} ${options.path}${isForm ? ' (multipart)' : ''}');
        handler.next(options);
      },
      onResponse: (response, handler) async {
        final code = response.statusCode ?? 0;
        AppLog.log('HTTP', '← $code ${response.requestOptions.path}');
        // Capture a freshly-issued session JWT from the cookie (login / MFA /
        // any future refresh) and keep it as the Bearer token.
        final sess = sessionJwtFromHeaders(response.headers);
        if (sess != null) tokens.save(sess);
        // A 403 from a stale/rotated CSRF token: refresh the token once and
        // replay the original request transparently.
        if (code == 403 &&
            _isCsrfError(response.data) &&
            response.requestOptions.extra['csrfRetried'] != true) {
          AppLog.log('CSRF', 'token rejected — refreshing and retrying');
          final tok = await _ensureCsrf(force: true);
          if (tok != null) {
            final ro = response.requestOptions;
            ro.extra['csrfRetried'] = true;
            ro.headers['x-csrf-token'] = tok;
            ro.headers['Cookie'] = '$_csrfCookieName=$tok';
            try {
              final retried = await dio.fetch(ro);
              handler.resolve(retried);
              return;
            } catch (_) {
              // fall through to normal error handling below
            }
          }
        }
        if (code >= 200 && code < 300) {
          // A 2xx whose body is an HTML page is NOT a real backend success — it's
          // a CloudFront/proxy page served while the origin is unreachable. Treat
          // it as a (retryable) gateway error so an upload is never falsely
          // marked "done" when the backend never saw it.
          if (_looksLikeHtml(response.data)) {
            handler.reject(DioException(
              requestOptions: response.requestOptions,
              response: response,
              error: ApiException(
                  'The server is temporarily unreachable (gateway). Please retry.',
                  statusCode: 502),
            ));
            return;
          }
          handler.next(response);
          return;
        }
        // A 401 anywhere except the login call means the session is gone.
        final isLogin =
            response.requestOptions.path.contains('/auth/login');
        if (code == 401 && !isLogin) onUnauthorized?.call();
        handler.reject(DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: ApiException(_httpMessage(response, isLogin: isLogin),
              statusCode: code),
        ));
      },
      onError: (e, handler) {
        // Network / timeout / cancellation (no HTTP status).
        AppLog.log('HTTP',
            '✗ ${e.requestOptions.method} ${e.requestOptions.path} — ${e.type.name}: ${e.message ?? ''}');
        handler.reject(DioException(
          requestOptions: e.requestOptions,
          response: e.response,
          error: ApiException(_networkMessage(e),
              statusCode: e.response?.statusCode),
        ));
      },
    ));
  }

  static bool _isMutating(String method) {
    switch (method.toUpperCase()) {
      case 'POST':
      case 'PUT':
      case 'PATCH':
      case 'DELETE':
        return true;
      default:
        return false;
    }
  }

  /// Fetch (and cache) the CSRF token from GET /csrf-token. The server returns
  /// `{csrfToken, cookieName}` and that token value is also the cookie value
  /// (double-submit), so we send it as both. Returns null if unavailable.
  Future<String?> _ensureCsrf({bool force = false}) async {
    if (!force && _csrfToken != null) return _csrfToken;
    try {
      final res = await dio.get('/csrf-token');
      final data = res.data;
      if (data is Map) {
        final tok = data['csrfToken']?.toString();
        final name = data['cookieName']?.toString();
        if (tok != null && tok.isNotEmpty) {
          _csrfToken = tok;
          if (name != null && name.isNotEmpty) _csrfCookieName = name;
          return tok;
        }
      }
    } catch (e) {
      AppLog.log('CSRF', 'fetch failed: $e');
    }
    return _csrfToken; // possibly null — request proceeds and may 403
  }

  static bool _isCsrfError(Object? data) {
    if (data is Map) {
      final msg = (data['error'] ?? data['message'])?.toString().toLowerCase();
      return msg != null && msg.contains('csrf');
    }
    return false;
  }

  /// True when a response body is an HTML document (a proxy/CDN page) rather
  /// than the JSON the API always returns — i.e. the backend wasn't actually hit.
  static bool _looksLikeHtml(Object? data) {
    if (data is String) {
      final s = data.trimLeft().toLowerCase();
      return s.startsWith('<!doctype html') || s.startsWith('<html');
    }
    return false;
  }

  /// Friendly message for a non-2xx HTTP response (prefers the server's own).
  static String _httpMessage(Response r, {required bool isLogin}) {
    final data = r.data;
    if (data is Map) {
      for (final k in ['error', 'message', 'msg']) {
        final v = data[k];
        if (v is String && v.isNotEmpty) return v;
      }
    }
    final code = r.statusCode ?? 0;
    if (code == 401) {
      return isLogin
          ? 'Incorrect email or password.'
          : 'Session expired. Please sign in again.';
    }
    if (code == 429) return 'Too many requests — please wait a moment.';
    if (code >= 500) return 'Server error ($code). Please try again.';
    return 'Request failed ($code).';
  }

  /// Friendly message for a transport-level failure.
  static String _networkMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out — check your internet.';
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond.';
      case DioExceptionType.sendTimeout:
        return 'Upload timed out.';
      case DioExceptionType.connectionError:
        return 'No connection to the server.';
      case DioExceptionType.badCertificate:
        return 'Secure connection failed.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.badResponse:
        final c = e.response?.statusCode;
        return c != null ? 'Request failed ($c).' : 'Unexpected server reply.';
      case DioExceptionType.unknown:
        return e.message?.isNotEmpty == true ? e.message! : 'Network error.';
    }
  }
}
