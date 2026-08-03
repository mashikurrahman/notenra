import 'package:flutter/foundation.dart';

/// Lightweight diagnostic log for the upload/sync pipeline, kept in a small
/// in-memory ring buffer (viewable on-device if needed).
///
/// HIPAA: in **release** builds nothing is written to the device log (logcat),
/// and callers must NEVER pass PHI (patient names, note text) — ids only.
class AppLog {
  AppLog._();

  static final List<String> buffer = <String>[];

  static void log(String area, String msg) {
    final ts = DateTime.now().toIso8601String();
    final line = '[NOTENRA][$area] ${ts.substring(11, 23)}  $msg';
    buffer.add(line);
    if (buffer.length > 400) buffer.removeRange(0, buffer.length - 400);
    // Only emit to the OS log off production, so a distributed build never
    // leaks request paths / ids into logcat.
    if (!kReleaseMode) {
      // ignore: avoid_print
      print(line);
    }
  }
}
