import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Drop-in replacement for [FlutterSecureStorage] (same `read`/`write`/`delete`
/// API and `aOptions`) that keeps the app launchable when the platform keychain
/// is unavailable.
///
/// Why this exists: an **unsigned iOS Simulator build** (e.g. the build we run
/// on Appetize for testing) has no signing/entitlement, so the iOS Keychain
/// rejects every access with `errSecMissingEntitlement` (-34018). With the raw
/// plugin that throws during startup and the app never paints.
///
/// Behaviour:
///   * Normal devices (Android, and **signed** iOS / TestFlight / App Store) —
///     the keychain works, so this is a thin pass-through with zero change.
///   * Keychain throws **and** this is a debug build — fall back to an
///     in-process (RAM-only, never written to disk) store so the UI is testable
///     on the simulator. The fallback latches for the session.
///   * Keychain throws in a **release** build — re-throw. Production stays
///     fail-closed: PHI keys are never silently downgraded out of the keychain.
class SecureStore {
  const SecureStore({this.aOptions});

  final AndroidOptions? aOptions;

  // `encryptedSharedPreferences` is intentionally omitted: flutter_secure_storage
  // v10 already stores values under strong custom ciphers on Android and
  // deprecated that flag (it's ignored and slated for removal in v11).
  // `resetOnError` recovers the store if the platform keystore entry is corrupt
  // rather than throwing on every read.
  static const _defaultAndroidOptions = AndroidOptions(
    resetOnError: true,
  );

  FlutterSecureStorage get _ks =>
      FlutterSecureStorage(aOptions: aOptions ?? _defaultAndroidOptions);

  // Shared across every SecureStore instance; RAM-only, lost on app exit.
  static final Map<String, String> _mem = {};
  static bool _fellBack = false;

  Future<String?> read({required String key}) async {
    if (_fellBack) return _mem[key];
    try {
      return await _ks.read(key: key);
    } catch (e) {
      if (_degrade(e)) return _mem[key];
      rethrow;
    }
  }

  Future<void> write({required String key, required String value}) async {
    if (_fellBack) {
      _mem[key] = value;
      return;
    }
    try {
      await _ks.write(key: key, value: value);
    } catch (e) {
      if (_degrade(e)) {
        _mem[key] = value;
        return;
      }
      rethrow;
    }
  }

  Future<void> delete({required String key}) async {
    if (_fellBack) {
      _mem.remove(key);
      return;
    }
    try {
      await _ks.delete(key: key);
    } catch (e) {
      if (_degrade(e)) {
        _mem.remove(key);
        return;
      }
      rethrow;
    }
  }

  /// Latches the in-memory fallback when the keychain is unusable on a debug
  /// build; returns false in release so the caller re-throws (fail-closed).
  bool _degrade(Object e) {
    if (!kDebugMode) return false;
    if (!_fellBack) {
      _fellBack = true;
      debugPrint('SecureStore: keychain unavailable ($e) — using RAM-only '
          'fallback for this debug session.');
    }
    return true;
  }
}
