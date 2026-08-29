import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notenra/api/api_client.dart';

/// Session-JWT extraction from `Set-Cookie`.
///
/// This is the path that keeps a clinician signed in: the server issues the JWT
/// as an httpOnly cookie, and losing it mid-visit ends the session. The matcher
/// is two-stage — exact on the configured `SESSION_COOKIE_NAME`, then a
/// convention fallback for a server whose name we weren't told — so both stages
/// and the precedence between them are pinned here.
void main() {
  Headers cookies(List<String> setCookie) =>
      Headers.fromMap({'set-cookie': setCookie});

  const jwt = 'eyJhbGciOi.payload.sig';

  group('exact match on the configured cookie name', () {
    test('bare name', () {
      expect(
        ApiClient.sessionJwtFromHeaders(
            cookies(['${ApiClient.sessionCookieName}=$jwt; Path=/; HttpOnly'])),
        jwt,
      );
    });

    test('__Host- prefixed (production form)', () {
      expect(
        ApiClient.sessionJwtFromHeaders(cookies([
          '__Host-${ApiClient.sessionCookieName}=$jwt; Path=/; Secure; HttpOnly'
        ])),
        jwt,
      );
    });

    test('__Secure- prefixed', () {
      expect(
        ApiClient.sessionJwtFromHeaders(cookies(
            ['__Secure-${ApiClient.sessionCookieName}=$jwt; Path=/; Secure'])),
        jwt,
      );
    });

    test('found among several cookies', () {
      expect(
        ApiClient.sessionJwtFromHeaders(cookies([
          '__Host-csrf_token=abc123; Path=/; Secure; SameSite=Strict',
          '__Host-${ApiClient.sessionCookieName}=$jwt; Path=/; Secure; HttpOnly',
        ])),
        jwt,
      );
    });
  });

  group('convention fallback', () {
    test('accepts an unfamiliar but session-shaped cookie name', () {
      // A renamed backend must not silently cost us the JWT.
      expect(
        ApiClient.sessionJwtFromHeaders(
            cookies(['some_other_session=$jwt; Path=/; Secure; HttpOnly'])),
        jwt,
      );
    });

    test('accepts a bare "session" cookie', () {
      expect(
        ApiClient.sessionJwtFromHeaders(cookies(['session=$jwt; Path=/'])),
        jwt,
      );
    });

    test('exact match wins over a conventional one', () {
      // Precedence matters: a correct define must never be second-guessed, even
      // when another session-shaped cookie is present in the same response.
      expect(
        ApiClient.sessionJwtFromHeaders(cookies([
          'legacy_session=WRONG; Path=/',
          '__Host-${ApiClient.sessionCookieName}=$jwt; Path=/; Secure',
        ])),
        jwt,
      );
    });
  });

  group('rejects non-session cookies', () {
    test('the CSRF cookie is not mistaken for a session', () {
      // The API sets this on every csrf-token fetch, so a false match here would
      // overwrite the real JWT with a CSRF value on the next request.
      expect(
        ApiClient.sessionJwtFromHeaders(cookies([
          '__Host-csrf_token=abc123; Path=/; Secure; SameSite=Strict',
          'csrf_token=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
        ])),
        isNull,
      );
    });

    test('no Set-Cookie header at all', () {
      expect(ApiClient.sessionJwtFromHeaders(Headers.fromMap({})), isNull);
    });

    test('empty Set-Cookie list', () {
      expect(ApiClient.sessionJwtFromHeaders(cookies([])), isNull);
    });

    test('a session cookie being cleared yields no token', () {
      // Logout sends an empty value; treating '' as a JWT would store a blank
      // Bearer token and turn every later call into a 401.
      expect(
        ApiClient.sessionJwtFromHeaders(cookies([
          '${ApiClient.sessionCookieName}=; Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT'
        ])),
        isNull,
      );
    });
  });
}
