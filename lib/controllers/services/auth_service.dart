import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../controllers/app_state.dart';

class AuthService extends BaseService {
  static Future<void> migrateLegacyUserData() async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) return;

    try {
      final legacyGroups = await BaseService.db
          .collection('groups')
          .where('memberEmails', arrayContains: myEmail)
          .get();
      for (final doc in legacyGroups.docs) {
        final data = doc.data();
        // Use logic from FirebaseService (will be moved to GroupService later)
        final members = (<String>{
          ...BaseService.normalizeEmailList(data['members']),
          ...BaseService.normalizeEmailList(data['memberEmails']),
        }).toList();
        
        if (members.isEmpty) continue;
        await doc.reference.set({
          'members': members,
          'managerEmails': BaseService.normalizeEmailList(data['managerEmails']),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Legacy group migration skipped: $e');
    }

    try {
      final userDoc = await BaseService.db.collection('users').doc(uid).get();
      final blockedEmails = BaseService.normalizeEmailList(
        userDoc.data()?['blockedEmails'],
      );
      for (final email in blockedEmails) {
        await BaseService.db
            .collection('users')
            .doc(uid)
            .collection('blocks')
            .doc(email)
            .set({
              'type': 'user',
              'targetEmail': email,
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Legacy block migration skipped: $e');
    }
  }

  static Future<void> hydrateUser(User user, {String? fallbackEmail}) async {
    AppState.currentUserEmail = user.email ?? fallbackEmail ?? "";
    final userDoc = await BaseService.db.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data()!;
      AppState.currentUserName = (data['name'] ?? user.displayName ?? "User").toString();
      AppState.currentUserAvatar = (data['avatar'] ?? user.photoURL ?? "https://ui-avatars.com/api/?background=random").toString();
      AppState.currentUserRole = (data['role'] ?? "User").toString();
    } else {
      AppState.currentUserName = (user.displayName ?? "User").toString();
      AppState.currentUserAvatar = (user.photoURL ?? "https://ui-avatars.com/api/?background=random").toString();
      AppState.currentUserRole = "User";
      await BaseService.db.collection('users').doc(user.uid).set({
        'email': AppState.currentUserEmail,
        'name': AppState.currentUserName,
        'avatar': AppState.currentUserAvatar,
        'role': AppState.currentUserRole,
        'isOnline': true,
        'lastActive': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Stream<DocumentSnapshot> getUserProfileStream() {
    return BaseService.db.collection('users').doc(BaseService.currentUid).snapshots();
  }

  static Future<void> updateUserProfile({String? name, String? avatar}) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;
    if (data.isNotEmpty) {
      await BaseService.db.collection('users').doc(uid).update(data);
    }
  }

  static Future<String> updateUserSettings({
    bool? darkMode,
    bool? notificationsEnabled,
  }) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return "Chưa đăng nhập";
    try {
      final data = <String, dynamic>{};
      if (darkMode != null) data['settings.darkMode'] = darkMode;
      if (notificationsEnabled != null) {
        data['settings.notificationsEnabled'] = notificationsEnabled;
      }
      if (data.isNotEmpty) {
        await BaseService.db.collection('users').doc(uid).update(data);
      }
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }
}
