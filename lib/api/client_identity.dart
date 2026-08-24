import 'dart:io';

import '../app_log.dart';
import '../security.dart';

/// Who this client is, for server-side audit attribution.
///
/// Every request carries these headers so an audit reviewer reading the web
/// app's log can tell a phone-originated entry from a browser one. Without them
/// the backend sees no `User-Agent` at all and its dashboard classifies mobile
/// activity as "Desktop / other" — worse than unlabelled, because it is wrong.
///
/// Everything here is deliberately PHI-free: an app version, an OS name, and an
/// opaque random device id. Nothing identifies the clinician or the patient, so
/// these values are safe to log, to send, and to retain for the audit period.
class ClientIdentity {
  /// Keep in step with `version:` in pubspec.yaml.
  static const appVersion = '1.0.0';

  /// Distinguishes this client from the web app in the audit trail.
  static const client = 'mobile';

  static String _deviceId = '';
  static String get deviceId => _deviceId;

  static String _userAgent = 'Notenra/$appVersion';
  static String get userAgent => _userAgent;

  /// Resolve the device id and user-agent once at startup.
  ///
  /// Never throws: attribution is valuable but not worth blocking launch for. If
  /// the keystore read fails the device id stays empty and requests simply go
  /// out without that one header.
  static Future<void> init() async {
    try {
      _deviceId = await Security.getOrCreateDeviceId();
    } catch (e) {
      AppLog.log('CLIENT', 'device id unavailable: $e');
    }
    _userAgent = 'Notenra/$appVersion (${_platform()})';
  }

  /// Short OS descriptor, e.g. `Android 14; mobile`. Falls back to a bare
  /// `mobile` if the platform refuses to answer.
  static String _platform() {
    try {
      final os = Platform.isAndroid
          ? 'Android'
          : Platform.isIOS
              ? 'iOS'
              : Platform.operatingSystem;
      // operatingSystemVersion is verbose and inconsistent across platforms
      // ("Android 14 (API 34)", a long Darwin string) — take the leading digits
      // only, so the header stays short and stable.
      final v = RegExp(r'\d+(\.\d+)?')
          .firstMatch(Platform.operatingSystemVersion)
          ?.group(0);
      return v == null ? '$os; mobile' : '$os $v; mobile';
    } catch (_) {
      return 'mobile';
    }
  }

  /// Headers attached to every API request.
  static Map<String, String> get headers => {
        'User-Agent': _userAgent,
        'X-Notenra-Client': client,
        'X-Notenra-Client-Version': appVersion,
        if (_deviceId.isNotEmpty) 'X-Notenra-Device-Id': _deviceId,
      };
}
