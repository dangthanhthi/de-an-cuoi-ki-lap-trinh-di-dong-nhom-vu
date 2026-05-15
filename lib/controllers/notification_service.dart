import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static int reminderIdForNote(String noteId) {
    var hash = 0x811C9DC5;
    for (final unit in noteId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<void> init() async {
    // Khoi tao mui gio de bao thuc chay chinh xac.
    tz.initializeTimeZones();

    const androidInitSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    await _notificationsPlugin.initialize(initSettings);
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!AppState.notificationsEnabledNotifier.value) return;
    if (scheduledTime.isBefore(DateTime.now())) return;

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledTime, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'snote_reminder_channel',
          'Nhac nho Ghi chu',
          channelDescription: 'Kenh gui thong bao nhac nho ghi chu cua SNote',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancel(int id) async {
    await _notificationsPlugin.cancel(id);
  }

  static Future<void> cancelNoteReminder(String noteId) async {
    if (noteId.trim().isEmpty) return;
    await cancel(reminderIdForNote(noteId));
  }

  static Future<void> syncNoteReminder({
    required String noteId,
    required String title,
    required String body,
    DateTime? scheduledTime,
  }) async {
    if (noteId.trim().isEmpty) return;
    final id = reminderIdForNote(noteId);
    await cancel(id);
    if (scheduledTime == null) return;
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
    );
  }

  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!AppState.notificationsEnabledNotifier.value) return;
    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'snote_realtime_channel',
          'Thong bao SNote',
          channelDescription: 'Thong bao loi moi, ghi chu moi va tin nhan',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  static Future<void> checkAndNotifyPending() async {
    final summary = await FirebaseService.getReLoginSummary();
    if (summary.isEmpty) return;
    await showReLoginSummary(summary);
  }

  static Future<void> showReLoginSummary(Map<String, int> summary) async {
    final unread = summary['unreadMessages'] ?? 0;
    final invites = (summary['friendRequests'] ?? 0) +
        (summary['noteInvites'] ?? 0) +
        (summary['groupInvites'] ?? 0) +
        (summary['groupRequests'] ?? 0);
    final reminders = summary['todayReminders'] ?? 0;

    if (unread == 0 && invites == 0 && reminders == 0) return;

    final List<String> parts = [];
    if (unread > 0) parts.add('$unread tin nhắn mới');
    if (invites > 0) parts.add('$invites lời mời/yêu cầu');
    if (reminders > 0) parts.add('$reminders việc cần làm hôm nay');

    String body = "";
    if (parts.isEmpty) return;

    if (parts.length == 1) {
      body = "Bạn có ${parts[0]}.";
    } else if (parts.length == 2) {
      body = "Bạn có ${parts[0]} và ${parts[1]}.";
    } else {
      body = "Bạn có ${parts[0]}, ${parts[1]} và ${parts[2]}.";
    }

    await showNow(
      id: 999,
      title: "Chào mừng bạn trở lại!",
      body: body,
    );
  }
}


