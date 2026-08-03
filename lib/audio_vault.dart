import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:path_provider/path_provider.dart';

import 'secure_store.dart';

/// Encrypts recorded clinical audio at rest with AES-GCM. The 256-bit key lives
/// in the OS Keystore/Keychain (never in the file or the code), so even if the
/// `.enc` files are read off the device or land in a backup they are useless
/// without the keystore — a HIPAA encryption-at-rest safeguard for PHI audio.
class AudioVault {
  static const _secure = SecureStore();
  static const _keyName = 'audio_key_v1';
  static const _ivLen = 12; // GCM nonce length

  static Future<enc.Key> _key() async {
    var b64 = await _secure.read(key: _keyName);
    if (b64 == null || b64.isEmpty) {
      final rnd = Random.secure();
      final bytes =
          Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
      b64 = base64.encode(bytes);
      await _secure.write(key: _keyName, value: b64);
    }
    return enc.Key.fromBase64(b64);
  }

  static bool isEncrypted(String path) => path.endsWith('.enc');

  /// Encrypts [plainPath] to a sibling `.enc` file (IV prepended), deletes the
  /// plaintext original, and returns the encrypted path. On failure the
  /// original path is returned unchanged so recording is never lost.
  ///
  /// The AES-GCM work is CPU-bound and, for a long visit (tens of MB), takes
  /// seconds — so it runs in a background isolate to keep the UI responsive.
  /// Doing it on the main thread froze the app when stopping a long recording
  /// (an ANR). The key is fetched here (secure storage is main-isolate only)
  /// and passed to the worker as raw bytes.
  static Future<String> encryptInPlace(String plainPath) async {
    try {
      final keyBytes = (await _key()).bytes;
      return await Isolate.run(() => _encryptFile(plainPath, keyBytes));
    } catch (_) {
      return plainPath; // fail-safe: keep the (unencrypted) recording
    }
  }

  /// Isolate worker: read → AES-GCM encrypt → write `.enc` → delete plaintext.
  static Future<String> _encryptFile(String plainPath, Uint8List keyBytes) async {
    final iv = enc.IV.fromSecureRandom(_ivLen);
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.gcm));
    final bytes = await File(plainPath).readAsBytes();
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);
    final out = '$plainPath.enc';
    await File(out).writeAsBytes(
        Uint8List.fromList([...iv.bytes, ...encrypted.bytes]),
        flush: true);
    try {
      await File(plainPath).delete();
    } catch (_) {}
    return out;
  }

  /// Decrypts an `.enc` file to a temporary file for playback/upload and
  /// returns its path. The caller is responsible for deleting the temp file.
  /// Like [encryptInPlace], the heavy AES work runs off the UI thread.
  static Future<String> decryptToTemp(String encPath) async {
    final keyBytes = (await _key()).bytes;
    final dir = await getTemporaryDirectory();
    final tmp =
        '${dir.path}/play_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await Isolate.run(() => _decryptFile(encPath, keyBytes, tmp));
    return tmp;
  }

  /// Isolate worker: read `.enc` → AES-GCM decrypt → write plaintext to [outPath].
  static Future<void> _decryptFile(
      String encPath, Uint8List keyBytes, String outPath) async {
    final encrypter =
        enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.gcm));
    final data = await File(encPath).readAsBytes();
    final iv = enc.IV(Uint8List.fromList(data.sublist(0, _ivLen)));
    final cipher = Uint8List.fromList(data.sublist(_ivLen));
    final clear = encrypter.decryptBytes(enc.Encrypted(cipher), iv: iv);
    await File(outPath).writeAsBytes(clear, flush: true);
  }
}
