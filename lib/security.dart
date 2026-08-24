import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'secure_store.dart';

/// HIPAA technical-safeguard helpers: password hashing + secure key storage.
class Security {
  static const _iterations = 120000; // PBKDF2 work factor
  static final _rng = Random.secure();

  // ---- Password hashing (PBKDF2-HMAC-SHA256) ----

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// PBKDF2 with a single SHA-256 output block (32 bytes == hLen).
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    // U1 = PRF(password, salt || INT_32_BE(1))
    final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final result = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  /// Returns an encoded string: `pbkdf2$<iter>$<saltB64>$<hashB64>`.
  static String hashPassword(String password) {
    final salt = _randomBytes(16);
    final hash = _pbkdf2(utf8.encode(password), salt, _iterations);
    return 'pbkdf2\$$_iterations\$${base64.encode(salt)}\$${base64.encode(hash)}';
  }

  /// Constant-time verification of a plaintext password against an encoded hash.
  static bool verifyPassword(String password, String encoded) {
    try {
      final parts = encoded.split('\$');
      if (parts.length != 4 || parts[0] != 'pbkdf2') return false;
      final iterations = int.parse(parts[1]);
      final salt = base64.decode(parts[2]);
      final expected = base64.decode(parts[3]);
      final actual = _pbkdf2(utf8.encode(password), salt, iterations);
      if (actual.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < actual.length; i++) {
        diff |= actual[i] ^ expected[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  // ---- Secure database key (Keystore / Keychain) ----

  static const _secure = SecureStore();
  static const _dbKeyName = 'phi_db_key_v1';

  /// Returns the SQLCipher passphrase, generating and persisting a random
  /// 256-bit key in the OS keystore on first run.
  static Future<String> getOrCreateDbKey() async {
    final existing = await _secure.read(key: _dbKeyName);
    if (existing != null && existing.isNotEmpty) return existing;
    final key = base64.encode(_randomBytes(32));
    await _secure.write(key: _dbKeyName, value: key);
    return key;
  }

  // ---- Device identity (audit attribution) ----

  static const _deviceIdName = 'device_id_v1';

  /// A stable, opaque identifier for this install, generated on first use and
  /// persisted in the OS keystore.
  ///
  /// Deliberately random rather than derived from any hardware id: it carries no
  /// PHI and nothing about the device or the clinician, so it is safe to log and
  /// to send to the server. It lets an audit reviewer group a phone's events
  /// together and tell two of a clinician's devices apart. It survives app
  /// restarts and is regenerated on reinstall (keystore entries are cleared with
  /// the app), which is the correct trade — a reinstalled app is, for audit
  /// purposes, a new device.
  static Future<String> getOrCreateDeviceId() async {
    final existing = await _secure.read(key: _deviceIdName);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = base64Url.encode(_randomBytes(16)).replaceAll('=', '');
    await _secure.write(key: _deviceIdName, value: id);
    return id;
  }
}
