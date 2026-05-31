import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app_state.dart';
import '../models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../views/note_detail_screen.dart';
import '../views/chat_screen.dart';
import '../views/group_notes_screen.dart';
import '../views/requests_screen.dart';

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

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        if (payload == null) return;

        if (payload.startsWith('note:')) {
          final noteId = payload.substring(5);
          try {
            final doc = await FirebaseFirestore.instance
                .collection('notes')
                .doc(noteId)
                .get();
            if (doc.exists) {
              final note = FirebaseService.noteFromDocument(doc);
              final context = AppState.navigatorKey.currentContext;
              if (context != null && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NoteDetailScreen(note: note),
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error navigating to note: $e');
          }
        } else if (payload.startsWith('chat:')) {
          final friendEmail = payload.substring(5);
          try {
            final userQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: friendEmail)
                .limit(1)
                .get();
            if (userQuery.docs.isNotEmpty) {
              final userData = userQuery.docs.first.data();
              final name = userData['name'] ?? friendEmail;
              final avatar = userData['avatar'] ?? '';
              final context = AppState.navigatorKey.currentContext;
              if (context != null && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(
                      friendName: name.toString(),
                      friendEmail: friendEmail,
                      friendAvatar: avatar.toString(),
                    ),
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error navigating to chat: $e');
          }
        } else if (payload.startsWith('group:')) {
          final groupId = payload.substring(6);
          try {
            final doc = await FirebaseFirestore.instance
                .collection('groups')
                .doc(groupId)
                .get();
            if (doc.exists) {
              final groupName = doc.data()?['name'] ?? 'Nhóm';
              final context = AppState.navigatorKey.currentContext;
              if (context != null && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupNotesScreen(
                      groupId: groupId,
                      groupName: groupName.toString(),
                    ),
                  ),
                );
              }
            }
          } catch (e) {
            debugPrint('Error navigating to group: $e');
          }
        } else if (payload == 'requests') {
          final context = AppState.navigatorKey.currentContext;
          if (context != null && context.mounted) {
            try {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RequestsScreen(),
                ),
              );
            } catch (e) {
              debugPrint('Error navigating to requests: $e');
            }
          }
        }
      },
    );
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
    final id = reminderIdForNote(noteId);
    await cancel(id);
    await cancel(id + 1); // Hủy thông báo công việc chưa hoàn thành (nếu có)
  }

  static Future<void> syncNoteReminder({
    required String noteId,
    required String title,
    required String body,
    DateTime? scheduledTime,
    List<TodoItem>? todos,
  }) async {
    if (noteId.trim().isEmpty) return;
    final id = reminderIdForNote(noteId);
    final incompleteId = id + 1;

    await cancel(id);
    await cancel(incompleteId);

    if (scheduledTime == null) return;

    // 1. Lên lịch nhắc nhở chính
    await scheduleNotification(
      id: id,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
    );

    // 2. Lên lịch thông báo lúc 00:00 AM của ngày nhắc nhở nếu có công việc chưa hoàn thành
    if (todos != null && todos.isNotEmpty) {
      final incompleteTasks = todos
          .where((todo) => !todo.isDone && todo.task.trim().isNotEmpty)
          .toList();
      if (incompleteTasks.isNotEmpty) {
        final midnight = DateTime(
          scheduledTime.year,
          scheduledTime.month,
          scheduledTime.day,
          0,
          0,
          0,
        );
        // Chỉ lên lịch nếu mốc 00:00 AM nằm ở tương lai và trước thời điểm nhắc nhở chính
        if (midnight.isAfter(DateTime.now()) && midnight.isBefore(scheduledTime)) {
          final tasksStr = incompleteTasks.map((t) => '• ${t.task}').join('\n');
          await scheduleNotification(
            id: incompleteId,
            title: "Công việc chưa hoàn thành trong ngày: ${title.replaceFirst('Nhắc nhở: ', '').replaceFirst('SNote nhắc nhở: ', '')}",
            body: "Bạn có ${incompleteTasks.length} việc chưa làm hôm nay:\n$tasksStr",
            scheduledTime: midnight,
          );
        }
      }
    }
  }

  static Future<void> scheduleNoteReminder(String noteId, Note note) async {
    await syncNoteReminder(
      noteId: noteId,
      title: "Nhắc nhở: ${note.title}",
      body: note.content.isEmpty ? "Đến giờ ghi chú rồi!" : note.content,
      scheduledTime: note.reminderTime,
      todos: note.todos,
    );
  }

  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
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
      payload: payload,
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


