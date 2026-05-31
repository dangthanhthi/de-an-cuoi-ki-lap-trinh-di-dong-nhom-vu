import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import 'local_service.dart';
import 'firebase_service.dart';

export 'firebase_service.dart';

class AppState {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static String currentUserEmail = "";
  static String currentUserName = "";
  static String currentUserAvatar =
      "https://ui-avatars.com/api/?background=random";
  static String currentUserRole = "User";
  static String currentSessionId = "";

  static String generateSessionId() {
    currentSessionId = "${DateTime.now().microsecondsSinceEpoch}_${UniqueKey().hashCode}";
    return currentSessionId;
  }

  static List<Note> notes = [];
  static List<Note> allNotes = [];
  static List<Note> filteredNotes = [];
  static String searchQuery = "";
  static String selectedLabel = "Tất cả";
  static List<dynamic> activities = [];
  static List<dynamic> contacts = [];
  static const String otherLabel = 'Khác';
  static List<String> labels = [
    'Công việc',
    'Cá nhân',
    'Học tập',
    'Gia đình',
    'Du lịch',
    otherLabel,
  ];
  static final List<Color> noteColors = [
    Colors.blue.shade100,
    Colors.red.shade100,
    Colors.green.shade100,
    Colors.orange.shade100,
    Colors.purple.shade100,
    Colors.yellow.shade100,
    Colors.teal.shade100,
    Colors.pink.shade100,
    Colors.indigo.shade100,
    Colors.brown.shade100,
    Colors.cyan.shade100,
    Colors.lime.shade100,
  ];
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
    ThemeMode.light,
  );
  static final ValueNotifier<bool> notificationsEnabledNotifier = ValueNotifier(
    true,
  );

  static const String _prefDarkModeKey = 'app_dark_mode';
  static const String _prefNotificationsKey = 'app_notifications_enabled';
  static final Set<String> dismissedOverdueTodos = {};
  static const String _prefDismissedOverdueKey = 'dismissed_overdue_todos';

  static bool get isDarkModeActive {
    final themeMode = themeModeNotifier.value;
    if (themeMode == ThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return themeMode == ThemeMode.dark;
  }

  static Future<void> setLocalThemeMode(bool darkMode) async {
    themeModeNotifier.value = darkMode ? ThemeMode.dark : ThemeMode.light;
    await persistLocalSettings(darkMode: darkMode);

    // Sync to Firestore if logged in
    if (currentUserEmail.isNotEmpty) {
      await FirebaseService.updateUserSettings(darkMode: darkMode);
    }
  }

  static Future<void> loadLocalSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_prefDarkModeKey)) {
      themeModeNotifier.value = prefs.getBool(_prefDarkModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
    }
    if (prefs.containsKey(_prefNotificationsKey)) {
      notificationsEnabledNotifier.value =
          prefs.getBool(_prefNotificationsKey) ?? true;
    }
    if (prefs.containsKey(_prefDismissedOverdueKey)) {
      final list = prefs.getStringList(_prefDismissedOverdueKey) ?? [];
      dismissedOverdueTodos.clear();
      dismissedOverdueTodos.addAll(list);
    }
  }

  static Future<void> dismissOverdueTodo(String key) async {
    dismissedOverdueTodos.add(key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefDismissedOverdueKey, dismissedOverdueTodos.toList());
  }

  static Future<void> persistLocalSettings({
    bool? darkMode,
    bool? notificationsEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (darkMode != null) {
      await prefs.setBool(_prefDarkModeKey, darkMode);
    }
    if (notificationsEnabled != null) {
      await prefs.setBool(_prefNotificationsKey, notificationsEnabled);
    }
  }

  static void clearAllData() {
    currentUserEmail = "";
    currentUserName = "";
    currentUserAvatar = "https://ui-avatars.com/api/?background=random";
    currentUserRole = "User";
    currentSessionId = "";
    FirebaseService.currentGroupId = "";
    notes.clear();
    allNotes.clear();
    filteredNotes.clear();
    activities.clear();
    contacts.clear();
    dismissedOverdueTodos.clear();
    LocalService.clearSyncQueue();
    LocalService.clearNotesCache();
  }

  static void logActivity(dynamic arg1, [dynamic arg2]) {
    String action = arg1.toString();
    String detail = arg2 != null ? arg2.toString() : "";
    FirebaseService.saveActivity(action, detail);
  }

  static void addActivity(String action) {
    FirebaseService.saveActivity("Hoạt động", action);
  }

  static void applyUserSettings(Map<String, dynamic>? settings) {
    if (settings == null) return;

    final hasDarkMode = settings['darkMode'] is bool;
    final hasNotificationsEnabled = settings['notificationsEnabled'] is bool;

    if (hasDarkMode) {
      final darkMode = settings['darkMode'] as bool;
      if (themeModeNotifier.value !=
          (darkMode ? ThemeMode.dark : ThemeMode.light)) {
        themeModeNotifier.value = darkMode ? ThemeMode.dark : ThemeMode.light;
      }
    }

    if (hasNotificationsEnabled) {
      notificationsEnabledNotifier.value =
          settings['notificationsEnabled'] as bool;
    }

    persistLocalSettings(
      darkMode: hasDarkMode ? settings['darkMode'] as bool : null,
      notificationsEnabled: hasNotificationsEnabled
          ? settings['notificationsEnabled'] as bool
          : null,
    );
  }

  static Future<String?> hydrateSignedInUser(
    User user, {
    String? fallbackEmail,
  }) async {
    currentUserEmail = user.email ?? fallbackEmail ?? '';
    final sid = generateSessionId();

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final isDeleted = data['isDeleted'] == true;
        final isBanned = data['isBanned'] == true;
        if (isDeleted || isBanned) {
          await FirebaseAuth.instance.signOut();
          clearAllData();
          return isDeleted
              ? 'Tài khoản này đã bị xóa khỏi hệ thống.'
              : 'Tài khoản này đã bị khóa do vi phạm chính sách! Vui lòng liên hệ Admin.';
        }

        currentUserName = (data['name'] ?? 'User').toString();
        currentUserAvatar =
            (data['avatar'] ?? "https://ui-avatars.com/api/?background=random")
                .toString();
        currentUserRole = (data['role'] ?? 'User').toString();
        if (data['settings'] is Map<String, dynamic>) {
          applyUserSettings(data['settings'] as Map<String, dynamic>);
        }

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'sessionId': sid});

        await FirebaseService.migrateLegacyUserData();
        return null;
      }

      // Create new user if not exists
      currentUserName = user.email?.split('@')[0] ?? 'User';
      currentUserRole = 'User';
      currentUserAvatar =
          user.photoURL ??
          "https://ui-avatars.com/api/?name=$currentUserName&background=random";

      await FirebaseService.hydrateUser(user, fallbackEmail: fallbackEmail);
      await FirebaseService.migrateLegacyUserData();
      return null;
    } catch (e) {
      return "Lỗi đồng bộ dữ liệu: $e";
    }
  }
}
