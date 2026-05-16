import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../controllers/app_state.dart';

class ActivityService extends BaseService {
  static Future<void> saveActivity(
    String action,
    String detail, {
    String? groupId,
  }) async {
    try {
      final uid = BaseService.currentUid;
      if (uid.isEmpty) return;
      await BaseService.db
          .collection('users')
          .doc(uid)
          .collection('activities')
          .add({
            'action': action,
            'detail': detail,
            'groupId': groupId,
            'timestamp': FieldValue.serverTimestamp(),
          });

      if (groupId != null && groupId.isNotEmpty) {
        await BaseService.db
            .collection('groups')
            .doc(groupId)
            .collection('activities')
            .add({
              'action': action,
              'detail': detail,
              'userId': uid,
              'userEmail': AppState.currentUserEmail,
              'userName': AppState.currentUserName,
              'timestamp': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      debugPrint("Save Activity Error: $e");
    }
  }

  static Stream<QuerySnapshot> getActivitiesStream() {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return const Stream.empty();
    return BaseService.db
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot> getGroupActivitiesStream(String groupId) {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return const Stream.empty();
    return BaseService.db
        .collection('users')
        .doc(uid)
        .collection('activities')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Future<void> deleteActivity(String activityId) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty || activityId.isEmpty) return;
    await BaseService.db
        .collection('users')
        .doc(uid)
        .collection('activities')
        .doc(activityId)
        .delete();
  }

  static Future<void> clearMyActivities() async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return;
    final snapshot = await BaseService.db
        .collection('users')
        .doc(uid)
        .collection('activities')
        .get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
}
