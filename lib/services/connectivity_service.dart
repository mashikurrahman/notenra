import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Tracks online/offline state to drive the offline-first sync engine.
class ConnectivityService {
  final _connectivity = Connectivity();

  final ValueNotifier<bool> online = ValueNotifier<bool>(true);

  /// Fires when connectivity transitions from offline -> online.
  void Function()? onReconnected;

  Future<void> init() async {
    online.value = _isOnline(await _connectivity.checkConnectivity());
    _connectivity.onConnectivityChanged.listen((result) {
      final now = _isOnline(result);
      final wasOffline = !online.value;
      online.value = now;
      if (now && wasOffline) onReconnected?.call();
    });
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
