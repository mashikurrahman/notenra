import 'package:dio/dio.dart';

import 'api_client.dart';
import 'token_store.dart';

/// Outcome of a login attempt, including the first-login gates the server may
/// require before granting a full session.
enum LoginOutcome {
  success,
  forcePasswordChange,
  phiTraining,
  mfaEnrollment, // first-time TOTP setup (scan QR + verify a code)
  mfaChallenge, // already enrolled — enter the current 6-digit code
  failure,
}

class LoginResult {
  final LoginOutcome outcome;
  final String? message;
  final String? temporaryToken; // for gate completion
  final Map<String, dynamic>? user;
  LoginResult(this.outcome, {this.message, this.temporaryToken, this.user});
}

/// Authentication against /api/auth. Exact response field names are confirmed
/// against the live API during integration; parsing is defensive.
class AuthApi {
  final ApiClient api;
  final TokenStore tokens;
  AuthApi(this.api, this.tokens);

  Future<LoginResult> login(String email, String password) async {
    try {
      final res = await api.dio.post('/auth/login', data: {
        'email': email.trim(),
        'password': password,
      });
      final raw = res.data;
      final data =
          raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
      return await _classifyAuthBody(data,
          cookieToken: ApiClient.sessionJwtFromHeaders(res.headers));
    } on DioException catch (e) {
      // The client interceptor wraps non-2xx responses as a DioException whose
      // `.error` is an ApiException — unwrap it (or the raw body) for the real
      // server message instead of a generic "network" error.
      final resp = e.response;
      if (resp?.data is Map) {
        final m = resp!.data as Map;
        final msg = (m['error'] ?? m['message'])?.toString();
        if (msg != null && msg.isNotEmpty) {
          return LoginResult(LoginOutcome.failure, message: msg);
        }
      }
      final err = e.error;
      if (err is ApiException) {
        return LoginResult(LoginOutcome.failure, message: err.message);
      }
      return LoginResult(LoginOutcome.failure,
          message: e.message ?? 'Could not sign in. Please try again.');
    } catch (e) {
      return LoginResult(LoginOutcome.failure, message: 'Sign-in failed: $e');
    }
  }

  /// Complete the forced first-login password change. The short-lived
  /// [temporaryToken] from login authorizes the change (its
  /// `require_password_change` claim means the server doesn't ask for the
  /// current password). Returns null on success, or a server/validation
  /// message (e.g. the password policy) to show the user.
  Future<String?> completeForcedPasswordChange({
    required String temporaryToken,
    required String newPassword,
  }) async {
    try {
      await api.dio.put('/auth/change-password',
          data: {'newPassword': newPassword},
          options:
              Options(headers: {'Authorization': 'Bearer $temporaryToken'}));
      return null;
    } on DioException catch (e) {
      return _errorFrom(e) ?? 'Could not change the password. Please try again.';
    }
  }

  /// Complete the PHI-training gate. The server reads [temporaryToken] from the
  /// request BODY (it must never be honored as a Bearer credential). On success
  /// it returns EITHER a full session (token + user) OR the next gate — the
  /// server enforces MFA right after PHI training — so this returns a
  /// [LoginResult] the caller routes the same way as a login.
  Future<LoginResult> acknowledgePhiTraining(String temporaryToken) async {
    try {
      final res = await api.dio.post('/auth/acknowledge-phi-training',
          data: {'temporaryToken': temporaryToken});
      final data = (res.data as Map).cast<String, dynamic>();
      return await _classifyAuthBody(data,
          cookieToken: ApiClient.sessionJwtFromHeaders(res.headers));
    } on DioException catch (e) {
      return LoginResult(LoginOutcome.failure,
          message: _errorFrom(e) ?? 'Could not record the acknowledgement.');
    }
  }

  /// Classify a 200 auth-response body into a [LoginResult]: a first-login gate
  /// to complete, a full session (token saved + user), or a failure. Shared by
  /// [login] and [acknowledgePhiTraining] — both can hand back the next gate
  /// (e.g. PHI ack → MFA). Gate precedence matches the server: password change →
  /// PHI training → MFA.
  Future<LoginResult> _classifyAuthBody(Map<String, dynamic> data,
      {String? cookieToken}) async {
    final tempToken = (data['temporaryToken'] ?? data['tempToken'])?.toString();
    if (tempToken != null && tempToken.isNotEmpty) {
      final forcePw = data['requirePasswordChange'] == true ||
          data['force_password_change'] == true ||
          data['forcePasswordChange'] == true;
      final requireMfa = data['requireMfa'] == true;
      final isPhi = !forcePw &&
          !requireMfa &&
          (data['requirePhiTraining'] == true ||
              data['requiresPhiTraining'] == true ||
              data['phiTrainingRequired'] == true ||
              (data['reason']?.toString().contains('phi') ?? false));
      final LoginOutcome outcome;
      if (forcePw) {
        outcome = LoginOutcome.forcePasswordChange;
      } else if (isPhi) {
        outcome = LoginOutcome.phiTraining;
      } else if (requireMfa) {
        outcome = data['enrollmentRequired'] == true
            ? LoginOutcome.mfaEnrollment
            : LoginOutcome.mfaChallenge;
      } else {
        outcome = LoginOutcome.forcePasswordChange; // temp token w/o a flag
      }
      return LoginResult(outcome,
          temporaryToken: tempToken, message: data['message']?.toString());
    }
    // The session JWT now arrives in the __Host-anot_session cookie rather than
    // the body, so fall back to the cookie-extracted token.
    final token =
        (data['token'] ?? data['jwt'] ?? data['accessToken'])?.toString() ??
            cookieToken;
    if (token != null && token.isNotEmpty) {
      await tokens.save(token);
      final user = data['user'] is Map
          ? (data['user'] as Map).cast<String, dynamic>()
          : data;
      return LoginResult(LoginOutcome.success, user: user);
    }
    return LoginResult(LoginOutcome.failure,
        message: data['message']?.toString() ?? 'Unexpected login response.');
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await api.dio.put('/auth/change-password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  // --- MFA / TOTP (mandatory for PHI access) ---

  /// Begin TOTP enrollment. The enrollment [temporaryToken] (claim
  /// `requireMfaEnrollment`) authorizes it. Returns the shared secret, the
  /// `otpauth://` URI, and a ready-to-render QR PNG (data-uri), or an error.
  Future<
      ({
        String? secret,
        String? otpauthUrl,
        String? qrCode,
        List<String> recoveryCodes,
        String? error
      })> mfaSetup(String temporaryToken) async {
    try {
      final res = await api.dio.post('/mfa/setup',
          data: const <String, dynamic>{},
          options:
              Options(headers: {'Authorization': 'Bearer $temporaryToken'}));
      final d = (res.data as Map).cast<String, dynamic>();
      final codes = (d['recoveryCodes'] is List)
          ? (d['recoveryCodes'] as List).map((e) => e.toString()).toList()
          : <String>[];
      return (
        secret: d['secret']?.toString(),
        otpauthUrl: d['otpauthUrl']?.toString(),
        qrCode: d['qrCode']?.toString(),
        recoveryCodes: codes,
        error: null,
      );
    } on DioException catch (e) {
      return (
        secret: null,
        otpauthUrl: null,
        qrCode: null,
        recoveryCodes: <String>[],
        error: _errorFrom(e) ?? 'Could not start MFA setup.',
      );
    }
  }

  /// Finish TOTP enrollment by submitting the current 6-digit [code]. Uses the
  /// enrollment [temporaryToken] as a Bearer credential; on success the server
  /// returns a real session token (persisted) + user.
  Future<({Map<String, dynamic>? user, String? error})> mfaEnrollVerify({
    required String temporaryToken,
    required String code,
  }) async {
    try {
      final res = await api.dio.post('/mfa/verify',
          data: {'token': code},
          options:
              Options(headers: {'Authorization': 'Bearer $temporaryToken'}));
      return _saveSessionFrom(res.data, res.headers);
    } on DioException catch (e) {
      return (user: null, error: _errorFrom(e) ?? 'Could not verify the code.');
    }
  }

  /// Verify the per-login MFA challenge for an already-enrolled user. The
  /// challenge [temporaryToken] is rejected as a Bearer on every protected
  /// route, so it goes in the BODY (like the PHI endpoint) alongside the
  /// 6-digit [code]. On success the server returns a real session + user.
  Future<({Map<String, dynamic>? user, String? error})> mfaChallengeVerify({
    required String temporaryToken,
    required String code,
  }) async {
    try {
      // The server expects the temp token AND the 6-digit code in the body,
      // where `token` carries the code (confirmed against the live API).
      final res = await api.dio.post('/auth/verify-mfa',
          data: {'temporaryToken': temporaryToken, 'token': code});
      return _saveSessionFrom(res.data, res.headers);
    } on DioException catch (e) {
      return (user: null, error: _errorFrom(e) ?? 'Could not verify the code.');
    }
  }

  /// Persist the session token from an MFA verify response and return the user.
  /// The challenge response may omit the user object, so fall back to GET
  /// /auth/me once the session token is in place.
  Future<({Map<String, dynamic>? user, String? error})> _saveSessionFrom(
      Object? data, Headers headers) async {
    final map = data is Map ? data.cast<String, dynamic>() : const {};
    // Body token, else the session JWT from the __Host-anot_session cookie.
    final token =
        (map['token'] ?? map['jwt'] ?? map['accessToken'])?.toString() ??
            ApiClient.sessionJwtFromHeaders(headers);
    if (token == null || token.isEmpty) {
      return (user: null, error: 'Unexpected response. Please sign in again.');
    }
    await tokens.save(token);
    if (map['user'] is Map) {
      return (user: (map['user'] as Map).cast<String, dynamic>(), error: null);
    }
    // No user in the response — fetch it with the new session token.
    try {
      final me = await this.me();
      final u = (me?['user'] ?? me);
      if (u is Map) return (user: u.cast<String, dynamic>(), error: null);
    } catch (_) {}
    return (user: <String, dynamic>{}, error: null); // signed in; profile later
  }

  /// Pull the human-readable `{error|message}` out of a failed response (the
  /// client interceptor may also wrap it as an ApiException) so the UI can show
  /// the real server reason — a rejected password policy, an expired token, …
  String? _errorFrom(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      final m = (d['error'] ?? d['message'])?.toString();
      if (m != null && m.isNotEmpty) return m;
    }
    final err = e.error;
    if (err is ApiException && err.message.isNotEmpty) return err.message;
    return e.message;
  }

  Future<Map<String, dynamic>?> me() async {
    final res = await api.dio.get('/auth/me');
    return res.data is Map ? (res.data as Map).cast<String, dynamic>() : null;
  }

  Future<void> logout() async {
    try {
      await api.dio.post('/auth/logout');
    } catch (_) {}
    await tokens.clear();
  }
}
