import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../app_log.dart';

/// Local (on-device) notifications for two workflow events:
///   • a recording finished uploading to the scribe, and
///   • a note is ready for the clinician to review.
///
/// **HIPAA / PHI:** notification content is intentionally GENERIC — it never
/// includes a patient name, MRN, or any clinical detail, because notifications
/// surface on the lock screen where a bystander could read them. The clinician
/// opens the app to see who/what; the notification only says *that* something
/// happened. These are purely local (no push server, no PHI leaves the device).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Distinct channels so the clinician can tune each in Android settings.
  static const _uploadChannelId = 'notenra_uploads';
  static const _reviewChannelId = 'notenra_reviews';

  /// Notification ids. Fixed ids per category so a newer alert replaces the
  /// previous one rather than stacking many rows.
  static const _uploadId = 1001;
  static const _reviewId = 1002;

  Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      // We ask for permission explicitly (below) at a sensible moment, not on
      // the very first frame, so don't request it during init on iOS.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: darwin),
      );
      _ready = true;
    } catch (e) {
      AppLog.log('NOTIF', 'init failed: $e');
    }
  }

  /// Ask the OS for permission to post notifications. On Android 13+ this shows
  /// the runtime POST_NOTIFICATIONS prompt; on older Android it's a no-op. Safe
  /// to call more than once. Best-effort — never throws.
  Future<void> requestPermission() async {
    if (!_ready) await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      AppLog.log('NOTIF', 'permission request failed: $e');
    }
  }

  /// A queued recording reached the scribe (e.g. after connectivity returned).
  Future<void> recordingUploaded() => _show(
        id: _uploadId,
        channelId: _uploadChannelId,
        channelName: 'Recording uploads',
        channelDescription:
            'Tells you when a visit recording has been sent to the scribe.',
        title: 'Recording uploaded',
        body: 'Your visit recording has been sent to the scribe.',
      );

  /// A scribe finished a note; the clinician can now review it.
  Future<void> noteReady() => _show(
        id: _reviewId,
        channelId: _reviewChannelId,
        channelName: 'Notes ready for review',
        channelDescription:
            'Tells you when a note is ready for you to review.',
        title: 'Note ready for review',
        body: 'A note is ready for you to review in Notenra.',
      );

  Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      final android = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        // Belt-and-braces: even the "public" lock-screen version carries no PHI.
        visibility: NotificationVisibility.public,
      );
      const darwin = DarwinNotificationDetails();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android, iOS: darwin),
      );
      AppLog.log('NOTIF', 'shown: $title');
    } catch (e) {
      AppLog.log('NOTIF', 'show failed: $e');
    }
  }
}
