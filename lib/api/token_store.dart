
import '../secure_store.dart';

/// Stores the JWT bearer token (and lightweight identity claims) in the OS
/// Keystore/Keychain. The token is the only credential the app persists.
class TokenStore {
  static const _secure = SecureStore();
  static const _tokenKey = 'jwt_token';

  String? _cached;
  String? get token => _cached;
  bool get hasToken => _cached != null && _cached!.isNotEmpty;

  Future<void> load() async {
    _cached = await _secure.read(key: _tokenKey);
  }

  Future<void> save(String token) async {
    _cached = token;
    await _secure.write(key: _tokenKey, value: token);
  }

  Future<void> clear() async {
    _cached = null;
    await _secure.delete(key: _tokenKey);
  }
}
