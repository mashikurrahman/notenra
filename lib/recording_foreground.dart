import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app process alive while recording so Android doesn't kill capture
/// when the screen locks or the app is backgrounded. Runs a `microphone`
/// foreground service with a persistent notification. iOS keeps recording via
/// the `audio` UIBackgroundMode (Info.plist); this service is a no-op there
/// beyond the (disabled) notification.
@pragma('vm:entry-point')
void recordingServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_RecordingTaskHandler());
}

/// Minimal handler — the actual recording runs in the main isolate; this just
/// has to exist so the foreground service stays alive.
class _RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class RecordingForeground {
  static bool _inited = false;

  static void _ensureInited() {
    if (_inited) return;
    _inited = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notenra_recording',
        channelName: 'Visit recording',
        channelDescription: 'Shown while a visit is being recorded.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Start (or update) the recording foreground service.
  static Future<void> start({
    required String title,
    required String text,
  }) async {
    try {
      _ensureInited();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title, notificationText: text);
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 451,
        notificationTitle: title,
        notificationText: text,
        callback: recordingServiceCallback,
      );
    } catch (_) {
      // Never let foreground-service issues break recording itself.
    }
  }

  static Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }
}
