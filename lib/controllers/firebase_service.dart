import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/app_models.dart';
import 'notification_service.dart';
import '../utils/media_utils.dart';
import 'local_service.dart';
import 'app_state.dart';

export 'services/auth_service.dart';
export 'services/note_service.dart';
export 'services/group_service.dart';
export 'services/chat_service.dart';
export 'services/activity_service.dart';
export 'services/contact_service.dart';
export 'services/base_service.dart';

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instanceFor(
    bucket: 'snote-e8384.firebasestorage.app',
  );
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static String get currentUid => _auth.currentUser?.uid ?? "";
  static const int maxAttachmentBytes = 30 * 1024 * 1024;
  static const int maxInlineAttachmentBytes = 700 * 1024;

  static String currentGroupId = "";

  static Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }


  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static String normalizeLabel(String value) {
    final cleanValue = value.trim();
    switch (cleanValue.toLowerCase()) {
      case 'work':
        return 'Công việc';
      case 'personal':
        return 'Cá nhân';
      case 'study':
        return 'Học tập';
      case 'family':
        return 'Gia đình';
      default:
        return cleanValue.isEmpty ? AppState.labels.first : cleanValue;
    }
  }

  static List<TodoItem> _readTodos(dynamic value) {
    if (value is! List) return <TodoItem>[];
    return value
        .whereType<dynamic>()
        .map((item) => TodoItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  static List<TodoItem> _personalTodos(List<TodoItem> todos) {
    return todos.map((todo) {
      final isDone = todo.isDone || todo.status == TodoStatus.done;
      return todo.copyWith(
        isDone: isDone,
        status: isDone ? TodoStatus.done : TodoStatus.todo,
        clearCompletedAt: !isDone,
      );
    }).toList();
  }

  static Note noteFromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final dateValue = data['date'];
    final dateText = dateValue is String && dateValue.length >= 10
        ? dateValue.substring(0, 10)
        : 'Không rõ';

    return Note(
      id: doc.id,
      title: (data['title'] ?? 'Không tiêu đề').toString(),
      content: (data['content'] ?? '').toString(),
      titleTextColor: (data['titleTextColor'] ?? '').toString(),
      titleIsBold: data['titleIsBold'] != false,
      titleIsItalic: data['titleIsItalic'] == true,
      titleIsUnderlined: data['titleIsUnderlined'] == true,
      titleFontSize: (data['titleFontSize'] ?? 26.0).toDouble(),
      label: normalizeLabel(
        (data['label'] ?? AppState.labels.first).toString(),
      ),
      date: dateText,
      coverColor: data['color'] != null
          ? Color(data['color'] as int)
          : Colors.blue.shade100,
      isTodo: data['isTodo'] == true,
      todos: _readTodos(data['todos']),
      sharedWith: _normalizeEmailList(data['sharedWith']),
      hasReminder: data['hasReminder'] == true,
      reminderTime: _readDateTime(data['reminderTime']),
      attachments: _normalizeStringList(data['attachments']),
      isPinned: data['isPinned'] == true,
      priority: NotePriority.normalize(
        (data['priority'] ?? NotePriority.none).toString(),
      ),
      createdByEmail: (data['createdByEmail'] ?? '').toString(),
      createdByName: (data['createdByName'] ?? '').toString(),
      groupId: (data['groupId'] ?? '').toString(),
      groupName: (data['groupName'] ?? '').toString(),
      isRichText: data['isRichText'] == true,
      pinnedBy: _normalizeEmailList(data['pinnedBy']),
      viewedBy: _normalizeEmailList(data['viewedBy']),
      hiddenBy: _normalizeEmailList(data['hiddenBy']),
      titleIsStrikethrough: data['titleIsStrikethrough'] == true,
      contentIsStrikethrough: data['contentIsStrikethrough'] == true,
      isArchived: data['isArchived'] == true,
      isLocked: data['isLocked'] == true,
      isShared: data['isShared'] == true,
      isHidden: data['isHidden'] == true,
      isFavorite: data['isFavorite'] == true,
      isChecklist: data['isChecklist'] == true,
      backgroundColor: data['backgroundColor'] as int?,
      userId: (data['userId'] ?? '').toString(),
      assignedTo: _normalizeEmailList(data['assignedTo']),
      lastViewedAt: _readDateTime(data['lastViewedAt']),
      viewCount: (data['viewCount'] ?? 0) as int,
      status: TodoStatus.normalize((data['status'] ?? '').toString()),
    );
  }

  static Map<String, dynamic> _notePayload(Note note, {String? groupId}) {
    final assigneeEmails = note.todos
        .map((t) => t.assigneeEmail.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    return {
      'title': note.title,
      'content': note.content,
      'titleTextColor': note.titleTextColor,
      'status': TodoStatus.normalize(note.status),
      'titleIsBold': note.titleIsBold,
      'titleIsItalic': note.titleIsItalic,
      'titleIsUnderlined': note.titleIsUnderlined,
      'titleFontSize': note.titleFontSize,
      'contentTextColor': note.contentTextColor,
      'contentIsBold': note.contentIsBold,
      'contentIsItalic': note.contentIsItalic,
      'contentIsUnderlined': note.contentIsUnderlined,
      'contentFontSize': note.contentFontSize,
      'label': note.label,
      'isTodo': note.isTodo,
      'todos': note.todos.map((t) => t.toMap()).toList(),
      'assigneeEmails': assigneeEmails,
      'sharedWith': _normalizeEmailList(note.sharedWith),
      'color': note.coverColor.toARGB32(),
      'groupId': groupId ?? note.groupId,
      'groupName': note.groupName,
      'createdByEmail': note.createdByEmail,
      'createdByName': note.createdByName,
      'isPinned': note.isPinned,
      'priority': NotePriority.normalize(note.priority),
      'hasReminder': note.hasReminder,
      'reminderTime': note.reminderTime?.toIso8601String(),
      'attachments': _normalizeStringList(note.attachments),
      'isRichText': note.isRichText,
      'titleIsStrikethrough': note.titleIsStrikethrough,
      'contentIsStrikethrough': note.contentIsStrikethrough,
      'isArchived': note.isArchived,
      'isLocked': note.isLocked,
      'isShared': note.isShared,
      'isHidden': note.isHidden,
      'isFavorite': note.isFavorite,
      'isChecklist': note.isChecklist,
      'backgroundColor': note.backgroundColor,
      'userId': note.userId,
      'assignedTo': note.assignedTo,
      'lastViewedAt': note.lastViewedAt?.toIso8601String(),
      'viewCount': note.viewCount,
    };
  }

  static Reference _attachmentRef(String fileName) {
    final safeName = sanitizeFileName(fileName);
    final uid = currentUid;
    if (uid.isEmpty) throw Exception('User UID is empty. Please login again.');

    return _storage
        .ref()
        .child('note_attachments')
        .child(uid)
        .child('${DateTime.now().millisecondsSinceEpoch}_$safeName');
  }

  static SettableMetadata _attachmentMetadata(String fileName) {
    return SettableMetadata(
      contentType: guessMimeType(fileName),
      customMetadata: {
        'ownerUid': currentUid,
        'ownerEmail': AppState.currentUserEmail,
        'fileName': sanitizeFileName(fileName),
      },
    );
  }

  static Future<void> _deleteStoredAttachments(
    Iterable<String> attachments,
  ) async {
    for (final attachment in attachments) {
      await deleteAttachment(attachment);
    }
  }

  static Future<void> _deleteRemovedAttachments({
    required Iterable<String> previous,
    required Iterable<String> next,
  }) async {
    final nextSet = next
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    final removed = previous.where(
      (item) => item.trim().isNotEmpty && !nextSet.contains(item.trim()),
    );
    await _deleteStoredAttachments(removed);
  }

  static Future<void> _deleteCollectionDocs(
    CollectionReference<Object?> collection,
  ) async {
    final snapshot = await collection.get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  static Future<void> _deleteNoteRecord(
    DocumentReference<Map<String, dynamic>> noteRef,
    Map<String, dynamic> noteData,
  ) async {
    final attachments = List<String>.from(noteData['attachments'] ?? const []);
    await NotificationService.cancelNoteReminder(noteRef.id);
    await _deleteStoredAttachments(attachments);
    await _deleteCollectionDocs(noteRef.collection('comments'));
    await _deleteCollectionDocs(noteRef.collection('history'));
    await noteRef.delete();
  }

  static List<String> _normalizeEmailList(dynamic rawValue) {
    if (rawValue is! List) return <String>[];
    return rawValue
        .map((item) => item.toString().toLowerCase().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<String> _normalizeStringList(dynamic rawValue) {
    if (rawValue is! List) return <String>[];
    return rawValue
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<String> _groupManagerEmails(Map<String, dynamic> data) {
    return _normalizeEmailList(data['managerEmails']);
  }

  static List<String> _groupMemberEmails(Map<String, dynamic> data) {
    return {
      ..._normalizeEmailList(data['members']),
      ..._normalizeEmailList(data['memberEmails']),
    }.toList();
  }

  static Future<void> migrateLegacyUserData() async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) return;

    try {
      final legacyGroups = await _db
          .collection('groups')
          .where('memberEmails', arrayContains: myEmail)
          .get();
      for (final doc in legacyGroups.docs) {
        final data = doc.data();
        final members = _groupMemberEmails(data);
        if (members.isEmpty) continue;
        await doc.reference.set({
          'members': members,
          'managerEmails': _groupManagerEmails(data),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Legacy group migration skipped: $e');
    }

    try {
      final userDoc = await _db.collection('users').doc(currentUid).get();
      final blockedEmails = _normalizeEmailList(
        userDoc.data()?['blockedEmails'],
      );
      for (final email in blockedEmails) {
        await _db
            .collection('users')
            .doc(currentUid)
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

  static Future<String> _readGroupName(String groupId) async {
    final cleanGroupId = groupId.trim();
    if (cleanGroupId.isEmpty) return '';
    final groupDoc = await _db.collection('groups').doc(cleanGroupId).get();
    if (!groupDoc.exists) return '';
    final data = groupDoc.data() ?? <String, dynamic>{};
    return (data['name'] ?? '').toString().trim();
  }

  static Future<bool> _canManageNoteOwnerActions(
    Map<String, dynamic> noteData,
  ) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final creatorEmail = (noteData['createdByEmail'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    // 1. Nếu là người tạo, luôn có quyền
    if (creatorEmail == myEmail && myEmail.isNotEmpty) {
      return true;
    }

    // 2. Nếu là Admin hệ thống, luôn có quyền
    if (AppState.currentUserRole.toLowerCase() == 'admin') {
      return true;
    }

    // 3. Nếu là ghi chú trong nhóm, kiểm tra quyền Trưởng nhóm/Điều phối
    final groupId = (noteData['groupId'] ?? '').toString();
    if (groupId.isNotEmpty) {
      return await canCurrentUserManageGroupTasks(groupId);
    }

    // 4. Case đặc biệt: Ghi chú cá nhân không có creator (dữ liệu cũ) - Chỉ cho phép nếu là chủ sở hữu doc
    if (creatorEmail.isEmpty && (noteData['userId'] == currentUid)) {
      return true;
    }

    return false;
  }

  static Future<bool> canCurrentUserManageGroupTasks(String groupId) async {
    if (currentUid.isEmpty || groupId.trim().isEmpty) return false;
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return false;
    final data = groupDoc.data() ?? <String, dynamic>{};
    if (data['leaderId'] == currentUid) return true;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return _groupManagerEmails(data).contains(myEmail);
  }

  static Future<void> saveActivity(
    String action,
    String detail, {
    String? groupId,
  }) => ActivityService.saveActivity(action, detail, groupId: groupId);

  static Stream<QuerySnapshot> getActivitiesStream() => ActivityService.getActivitiesStream();

  static Stream<QuerySnapshot> getGroupActivitiesStream(String groupId) => ActivityService.getGroupActivitiesStream(groupId);

  static Future<void> deleteActivity(String activityId) => ActivityService.deleteActivity(activityId);

  static Future<void> clearMyActivities() => ActivityService.clearMyActivities();

  static Future<void> hydrateUser(User user, {String? fallbackEmail}) async {
    AppState.currentUserEmail = user.email ?? fallbackEmail ?? "";
    final userDoc = await _db.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final data = userDoc.data()!;
      AppState.currentUserName = (data['name'] ?? user.displayName ?? "User")
          .toString();
      AppState.currentUserAvatar =
          (data['avatar'] ??
                  user.photoURL ??
                  "https://ui-avatars.com/api/?background=random")
              .toString();
      AppState.currentUserRole = (data['role'] ?? "User").toString();
    } else {
      AppState.currentUserName = (user.displayName ?? "User").toString();
      AppState.currentUserAvatar =
          (user.photoURL ?? "https://ui-avatars.com/api/?background=random")
              .toString();
      AppState.currentUserRole = "User";
      await _db.collection('users').doc(user.uid).set({
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
    return _db.collection('users').doc(currentUid).snapshots();
  }

  static Future<void> updateUserProfile({String? name, String? avatar}) async {
    if (currentUid.isEmpty) return;
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (avatar != null) data['avatar'] = avatar;
    if (data.isNotEmpty) {
      await _db.collection('users').doc(currentUid).update(data);
    }
  }

  static Future<String> updateUserSettings({
    bool? darkMode,
    bool? notificationsEnabled,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final data = <String, dynamic>{};
      if (darkMode != null) data['settings.darkMode'] = darkMode;
      if (notificationsEnabled != null) {
        data['settings.notificationsEnabled'] = notificationsEnabled;
      }
      if (data.isNotEmpty) {
        await _db.collection('users').doc(currentUid).update(data);
      }
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  // --- 3. Phần danh bạ ---

  static Future<String> sendFriendRequest(String email) => ContactService.sendFriendRequest(email);
  static Stream<QuerySnapshot> getFriendRequestsStream() => ContactService.getFriendRequestsStream();
  static Future<String> acceptFriendRequest(String requestId, Map<String, dynamic> requestData) => ContactService.acceptFriendRequest(requestId, requestData);
  static Future<String> rejectFriendRequest(String requestId) => ContactService.rejectFriendRequest(requestId);
  static Stream<QuerySnapshot> getContactsStream() => ContactService.getContactsStream();
  static Future<String> removeContact(String contactDocId, String contactEmail) => ContactService.removeContact(contactDocId, contactEmail);
  static Future<String> updateContactName(String contactDocId, String name) => ContactService.updateContactName(contactDocId, name);
  static Future<String> getContactDocIdByEmail(String email) => ContactService.getContactDocIdByEmail(email);
  static Future<String> checkFriendshipStatus(String email) => ContactService.checkFriendshipStatus(email);

  static String chatIdForEmails(String a, String b) => ChatService.chatIdForEmails(a, b);

  static List<String> _cleanAttachments(List<String>? attachments) {
    if (attachments == null) return const [];
    return attachments
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _attachmentPreview(List<String> attachments) {
    if (attachments.isEmpty) return 'Đã gửi tin nhắn';
    final imageCount = attachments.where(isImageValue).length;
    final fileCount = attachments.length - imageCount;
    if (imageCount > 0 && fileCount > 0) {
      return 'Đã gửi $imageCount ảnh và $fileCount tệp';
    }
    if (imageCount > 0) {
      return imageCount == 1 ? 'Đã gửi 1 ảnh' : 'Đã gửi $imageCount ảnh';
    }
    return fileCount == 1 ? 'Đã gửi 1 tệp' : 'Đã gửi $fileCount tệp';
  }

  static Stream<QuerySnapshot> getMessagesStream(String friendEmail) => ChatService.getMessagesStream(friendEmail);
  static Stream<QuerySnapshot> getChatListStream() => ChatService.getChatListStream();
  static Stream<DocumentSnapshot> getChatStream(String friendEmail) => ChatService.getChatStream(friendEmail);

  static Future<bool> isChatPinned(String friendEmail) => ChatService.isChatPinned(friendEmail);

  static Future<String> sendMessage(
    String friendEmail,
    String text, {
    List<String>? attachments,
    Map<String, dynamic>? replyToData,
  }) => ChatService.sendMessage(friendEmail, text, attachments: attachments, replyToData: replyToData);

  static Future<String> editMessage(String friendEmail, String messageId, String newText) =>
      ChatService.editMessage(friendEmail, messageId, newText);

  static Future<void> _refreshChatSummary(String chatId) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final latestMessage = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestMessage.docs.isEmpty) {
      await chatRef.set({
        'lastMessage': '',
        'lastSender': '',
        'lastAttachmentCount': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final data = latestMessage.docs.first.data();
    final attachments = List<String>.from(data['attachments'] ?? const []);
    final text = (data['text'] ?? '').toString().trim();
    await chatRef.set({
      'lastMessage': text.isNotEmpty ? text : _attachmentPreview(attachments),
      'lastSender': (data['senderEmail'] ?? '').toString(),
      'lastAttachmentCount': attachments.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> toggleChatPin(String friendEmail, bool shouldPin) =>
      ChatService.toggleChatPin(friendEmail, shouldPin);

  static Future<String> togglePinChatMessage(String friendEmail, String messageId, bool shouldPin) =>
      ChatService.togglePinChatMessage(friendEmail, messageId, shouldPin);

  static Future<String> pinChatMessage(String friendEmail, String messageId, String text, String senderName) =>
      ChatService.togglePinChatMessage(friendEmail, messageId, true);

  static Future<String> unpinChatMessage(String friendEmail, [String? messageId]) =>
      ChatService.togglePinChatMessage(friendEmail, messageId ?? '', false);

  static Future<String> deleteChatConversation(String friendEmail) =>
      ChatService.deleteChatConversation(friendEmail);

  static Future<String> deleteMessage(
    String friendEmail,
    String messageId, {
    bool deleteForEveryone = true,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (messageId.trim().isEmpty) return "Không tìm thấy tin nhắn";

    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, friendEmail);
    final messageRef = _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    if (deleteForEveryone) {
      final messageDoc = await messageRef.get();
      if (!messageDoc.exists) return "Tin nhắn không tồn tại";

      final data = messageDoc.data() ?? <String, dynamic>{};
      final senderEmail = (data['senderEmail'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (senderEmail != myEmail) {
        return "Bạn chỉ có thể thu hồi tin nhắn của mình";
      }

      await _deleteStoredAttachments(
        List<String>.from(data['attachments'] ?? const []),
      );
      await messageRef.update({
        'text': 'Tin nhắn đã bị thu hồi',
        'attachments': [],
        'isRecalled': true,
        'recalledAt': FieldValue.serverTimestamp(),
        'replyToId': FieldValue.delete(),
        'replyToText': FieldValue.delete(),
        'replyToSender': FieldValue.delete(),
      });
      await _refreshChatSummary(chatId);
      return "SUCCESS";
    } else {
      // Xóa ở phía tôi
      await messageRef.update({
        'hiddenBy': FieldValue.arrayUnion([myEmail]),
      });
      return "SUCCESS";
    }
  }

  static Stream<QuerySnapshot> getNoteCommentsStream(String noteId) {
    return _db
        .collection('notes')
        .doc(noteId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<String> addNoteComment(String noteId, String text) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanText = text.trim();
    if (noteId.isEmpty) return "Không tìm thấy ghi chú";
    if (cleanText.isEmpty) return "Bình luận không được để trống";

    await _db.collection('notes').doc(noteId).collection('comments').add({
      'userId': currentUid,
      'userEmail': AppState.currentUserEmail,
      'userName': AppState.currentUserName,
      'userAvatar': AppState.currentUserAvatar,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return "SUCCESS";
  }

  static Stream<QuerySnapshot> getGroupCommentsStream(String groupId) {
    return _db
        .collection('groups')
        .doc(groupId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> markGroupCommentAsSeen(
    String groupId,
    String commentId,
  ) async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final commentRef = _db
        .collection('groups')
        .doc(groupId)
        .collection('comments')
        .doc(commentId);
    await commentRef.update({
      'seenBy': FieldValue.arrayUnion([myEmail]),
    });
  }

  static Future<void> markMessageAsSeen(String chatId, String messageId) => ChatService.markMessageAsSeen(chatId, messageId);

  static Future<String> addGroupComment(
    String groupId,
    String text, {
    List<String>? attachments,
    Map<String, dynamic>? replyTo,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanText = text.trim();
    final cleanAttachments = _cleanAttachments(attachments);
    if (groupId.isEmpty) return "Không tìm thấy nhóm";
    if (cleanText.isEmpty && cleanAttachments.isEmpty) {
      return "Bình luận không được để trống";
    }

    final groupDoc = await _db.collection('groups').doc(groupId).get();
    final members = _groupMemberEmails(groupDoc.data() ?? <String, dynamic>{});
    final Map<String, dynamic> unreadUpdates = {};
    for (var m in members) {
      final email = m.toString().toLowerCase().trim();
      if (email != AppState.currentUserEmail.toLowerCase().trim()) {
        unreadUpdates['unreadCount.$email'] = FieldValue.increment(1);
      }
    }

    unreadUpdates['lastMessage'] = cleanText.isNotEmpty
        ? cleanText
        : _attachmentPreview(cleanAttachments);
    unreadUpdates['lastSender'] = AppState.currentUserEmail
        .toLowerCase()
        .trim();
    unreadUpdates['updatedAt'] = FieldValue.serverTimestamp();

    await _db.collection('groups').doc(groupId).update(unreadUpdates);

    await _db.collection('groups').doc(groupId).collection('comments').add({
      'userId': currentUid,
      'userEmail': AppState.currentUserEmail,
      'userName': AppState.currentUserName,
      'userAvatar': AppState.currentUserAvatar,
      'text': cleanText,
      'attachments': cleanAttachments,
      'replyTo': replyTo,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': [AppState.currentUserEmail.toLowerCase().trim()],
    });
    return "SUCCESS";
  }

  static Future<String> toggleGroupCommentPin(
    String groupId,
    String commentId,
    bool isPinned,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      if (isPinned) {
        final pinnedCount = await _db
            .collection('groups')
            .doc(groupId)
            .collection('comments')
            .where('isPinned', isEqualTo: true)
            .get()
            .then((s) => s.docs.length);

        if (pinnedCount >= 3) {
          return "Chỉ được ghim tối đa 3 tin nhắn";
        }
      }

      await _db
          .collection('groups')
          .doc(groupId)
          .collection('comments')
          .doc(commentId)
          .update({
            'isPinned': isPinned,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> editGroupComment(
    String groupId,
    String commentId,
    String newText,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (newText.trim().isEmpty) return "Nội dung không được để trống";
    try {
      await _db
          .collection('groups')
          .doc(groupId)
          .collection('comments')
          .doc(commentId)
          .update({
            'text': newText.trim(),
            'isEdited': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> deleteGroupComment(
    String groupId,
    String commentId, {
    bool deleteForEveryone = false,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (groupId.trim().isEmpty || commentId.trim().isEmpty) {
      return "Không tìm thấy bình luận";
    }

    try {
      final commentRef = _db
          .collection('groups')
          .doc(groupId)
          .collection('comments')
          .doc(commentId);
      final commentDoc = await commentRef.get();
      if (!commentDoc.exists) return "Bình luận không tồn tại";

      final data = commentDoc.data() ?? <String, dynamic>{};
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      final ownerEmail = (data['userEmail'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      if (deleteForEveryone) {
        final canDeleteEveryone =
            ownerEmail == myEmail ||
            await canCurrentUserManageGroupTasks(groupId);
        if (!canDeleteEveryone) {
          return "Bạn không có quyền xóa tin nhắn này với mọi người";
        }

        // Luôn dùng cơ chế "Thu hồi" (Recall) thay vì xóa hẳn document
        // Để giữ metadata và hiển thị thông báo "ai đã xóa" giống Zalo
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .get();
        final currentUserName = currentUserDoc.data()?['name'] ?? myEmail;

        await commentRef.update({
          'isRecalled': true,
          'recalledBy': myEmail,
          'recalledByName': currentUserName,
          'isPinned': false,
          'text': 'Tin nhắn đã bị thu hồi',
          'attachments': [],
          'replyTo': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Xóa tệp đính kèm vật lý để tiết kiệm dung lượng
        await _deleteStoredAttachments(
          List<String>.from(data['attachments'] ?? const []),
        );

        return "SUCCESS";
      } else {
        // Delete for me only (hide)
        await commentRef.update({
          'hiddenBy': FieldValue.arrayUnion([myEmail]),
        });
        return "SUCCESS";
      }
    } catch (e) {
      return "Lỗi khi xóa bình luận: $e";
    }
  }

  static Future<String> removeUserFromGroup(
    String groupId,
    String targetEmail,
  ) async {
    return removeMemberFromGroup(groupId, targetEmail);
  }

  // --- 4. Phần ghi chú ---
  static Future<String> addNote(Note note) async {
    if (currentUid.isEmpty) return "";
    final groupId = note.groupId.trim();
    final groupName = groupId.isEmpty ? '' : await _readGroupName(groupId);
    final canManageGroupTasks =
        groupId.isEmpty || await canCurrentUserManageGroupTasks(groupId);
    final todosForWrite = groupId.isEmpty
        ? _personalTodos(note.todos)
        : note.todos;
    final createdNote = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      label: note.label,
      date: note.date,
      coverColor: note.coverColor,
      isTodo: canManageGroupTasks ? note.isTodo : false,
      todos: canManageGroupTasks ? todosForWrite : const [],
      sharedWith: note.sharedWith,
      hasReminder: note.hasReminder,
      reminderTime: note.reminderTime,
      attachments: note.attachments,
      isPinned: note.isPinned,
      priority: note.priority,
      createdByEmail: AppState.currentUserEmail.toLowerCase().trim(),
      createdByName: AppState.currentUserName,
      groupId: groupId,
      groupName: groupName,
      titleTextColor: note.titleTextColor,
      titleIsBold: note.titleIsBold,
      titleIsItalic: note.titleIsItalic,
      titleIsUnderlined: note.titleIsUnderlined,
      titleFontSize: note.titleFontSize,
      contentTextColor: note.contentTextColor,
      contentIsBold: note.contentIsBold,
      contentIsItalic: note.contentIsItalic,
      contentIsUnderlined: note.contentIsUnderlined,
      contentFontSize: note.contentFontSize,
      isRichText: note.isRichText,
    );
    if (!await isOnline()) {
      final offlineNote = createdNote.copyWith(
        id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
      );
      LocalService.cacheNote(offlineNote);
      LocalService.addToSyncQueue(offlineNote, 'ADD');
      return offlineNote.id;
    }

    try {
      final docRef = await _db.collection('notes').add({
        ..._notePayload(createdNote, groupId: groupId),
        'userId': currentUid,
        'date': DateTime.now().toIso8601String(),
        'pinnedBy': _normalizeEmailList(createdNote.pinnedBy),
        'viewedBy': [AppState.currentUserEmail.toLowerCase().trim()],
        'hiddenBy': const <String>[],
      });
      await saveActivity(
        "Thêm ghi chú",
        "Đã thêm: ${note.title}",
        groupId: note.groupId.isNotEmpty ? note.groupId : null,
      );
      await docRef.collection('history').add({
        'action': 'create',
        'userEmail': AppState.currentUserEmail,
        'userName': AppState.currentUserName,
        'title': note.title,
        'content': note.content,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (_) {
      return "";
    }
  }

  static Future<void> syncOfflineChanges() async {
    if (!await isOnline()) return;

    final queue = LocalService.getSyncQueue();
    if (queue.isEmpty) return;

    for (final item in queue) {
      final String queueId = item['id'];
      final String action = item['action'];
      final Map<String, dynamic> noteMap = item['note'];
      final note = Note.fromJson(noteMap);

      try {
        if (action == 'ADD') {
          await addNote(note);
          LocalService.removeCachedNote(note.id);
        } else if (action == 'UPDATE') {
          if (!note.id.startsWith('offline_')) {
            await updateNote(note.id, note);
          }
        } else if (action == 'DELETE') {
          if (!note.id.startsWith('offline_')) {
            await deleteNote(note.id, note.title);
          }
        }
        LocalService.removeFromSyncQueue(queueId);
      } catch (e) {
        debugPrint('Sync failed for $queueId: $e');
      }
    }
  }

  static Future<void> updateNote(String noteId, Note note) async {
    if (currentUid.isEmpty || noteId.isEmpty) return;
    final noteRef = _db.collection('notes').doc(noteId);
    final beforeDoc = await noteRef.get();
    if (!beforeDoc.exists) {
      throw Exception('Ghi chú không tồn tại hoặc đã bị xóa.');
    }
    final beforeData = beforeDoc.data();
    final previousAttachments = List<String>.from(
      beforeData?['attachments'] ?? const <String>[],
    );
    var isTodoForWrite = note.isTodo;
    var todosForWrite = note.groupId.isEmpty
        ? _personalTodos(note.todos)
        : note.todos;
    final groupName = note.groupId.isEmpty
        ? ''
        : await _readGroupName(note.groupId);
    if (note.groupId.isNotEmpty &&
        !await canCurrentUserManageGroupTasks(note.groupId)) {
      isTodoForWrite = beforeData?['isTodo'] == true;
      todosForWrite = _readTodos(beforeData?['todos']);
    }
    final noteForWrite = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      label: note.label,
      date: note.date,
      coverColor: note.coverColor,
      isTodo: isTodoForWrite,
      todos: todosForWrite,
      sharedWith: note.sharedWith,
      hasReminder: note.hasReminder,
      reminderTime: note.reminderTime,
      attachments: note.attachments,
      isPinned: note.isPinned,
      priority: note.priority,
      createdByEmail: note.createdByEmail,
      createdByName: note.createdByName,
      groupId: note.groupId,
      groupName: groupName,
      titleTextColor: note.titleTextColor,
      titleIsBold: note.titleIsBold,
      titleIsItalic: note.titleIsItalic,
      titleIsUnderlined: note.titleIsUnderlined,
      titleFontSize: note.titleFontSize,
      contentTextColor: note.contentTextColor,
      contentIsBold: note.contentIsBold,
      contentIsItalic: note.contentIsItalic,
      contentIsUnderlined: note.contentIsUnderlined,
      contentFontSize: note.contentFontSize,
      isRichText: note.isRichText,
    );
    if (!await isOnline()) {
      LocalService.cacheNote(noteForWrite);
      LocalService.addToSyncQueue(noteForWrite, 'UPDATE');
      return;
    }

    await noteRef.update({
      ..._notePayload(noteForWrite),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByEmail': AppState.currentUserEmail,
      'updatedByName': AppState.currentUserName,
    });
    await _deleteRemovedAttachments(
      previous: previousAttachments,
      next: noteForWrite.attachments,
    );
    await saveActivity(
      "Cập nhật ghi chú",
      "Đã cập nhật: ${note.title}",
      groupId: note.groupId.isNotEmpty ? note.groupId : null,
    );
    try {
      await noteRef.collection('history').add({
        'action': 'update',
        'userEmail': AppState.currentUserEmail,
        'userName': AppState.currentUserName,
        'title': note.title,
        'content': note.content,
        'previousTitle': beforeData?['title'] ?? '',
        'previousContent': beforeData?['content'] ?? '',
        'previousLabel': beforeData?['label'] ?? '',
        'previousTodos': beforeData?['todos'] ?? const [],
        'previousPriority': beforeData?['priority'] ?? '',
        'previousIsPinned': beforeData?['isPinned'] ?? false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // History/activity failures should not block the note update.
    }
  }

  static Stream<QuerySnapshot> getNoteHistoryStream(String noteId) {
    return _db
        .collection('notes')
        .doc(noteId)
        .collection('history')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Future<String> updateTodoStatus(
    String noteId,
    int todoIndex,
    String status,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (noteId.isEmpty) return "ID ghi chú không hợp lệ";

    try {
      final noteRef = _db.collection('notes').doc(noteId);
      final noteDoc = await noteRef.get();
      if (!noteDoc.exists) return "Ghi chú không tồn tại";

      final data = noteDoc.data() as Map<String, dynamic>;
      final groupId = (data['groupId'] ?? '').toString();
      final todos = List<Map<String, dynamic>>.from(
        (data['todos'] ?? []).map((item) => Map<String, dynamic>.from(item)),
      );

      if (todoIndex < 0 || todoIndex >= todos.length) {
        return "Công việc không còn tồn tại";
      }

      // Check permission for group notes
      if (groupId.isNotEmpty &&
          !await canCurrentUserManageGroupTasks(groupId)) {
        final myEmail = AppState.currentUserEmail.toLowerCase().trim();
        final assigneeEmail = (todos[todoIndex]['assigneeEmail'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
        if (assigneeEmail.isNotEmpty && assigneeEmail != myEmail) {
          return "Chỉ người phụ trách mới được thực hiện";
        }
      }

      final cleanStatus = TodoStatus.normalize(status);
      final previousStatus = (todos[todoIndex]['status'] ?? '').toString();
      final previousCompletedAt = (todos[todoIndex]['completedAt'] ?? '')
          .toString();

      todos[todoIndex]['status'] = cleanStatus;
      todos[todoIndex]['isDone'] = cleanStatus == TodoStatus.done;
      todos[todoIndex]['completedAt'] = cleanStatus == TodoStatus.done
          ? (previousStatus == TodoStatus.done && previousCompletedAt.isNotEmpty
                ? previousCompletedAt
                : DateTime.now().toIso8601String())
          : null;

      await noteRef.update({
        'todos': todos,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByEmail': AppState.currentUserEmail,
        'updatedByName': AppState.currentUserName,
      });

      await noteRef.collection('history').add({
        'action': 'todo_status',
        'userEmail': AppState.currentUserEmail,
        'userName': AppState.currentUserName,
        'title': data['title'] ?? '',
        'todoTask': todos[todoIndex]['task'] ?? '',
        'previousStatus': previousStatus,
        'status': cleanStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi cập nhật trạng thái: $e";
    }
  }

  static Future<String> deleteNote(String noteId, String title) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (noteId.isEmpty) return "Không tìm thấy ghi chú";

    if (!await isOnline()) {
      LocalService.addToSyncQueue(
        Note(
          id: noteId,
          title: title,
          content: '',
          label: '',
          date: '',
          coverColor: Colors.transparent,
        ),
        'DELETE',
      );
      LocalService.removeCachedNote(noteId);
      return "SUCCESS";
    }

    try {
      final noteRef = _db.collection('notes').doc(noteId);
      final doc = await noteRef.get();
      if (!doc.exists) return "Ghi chú không tồn tại";

      final data = doc.data() ?? {};
      if (!await _canManageNoteOwnerActions(data)) {
        return "Bạn không có quyền xóa ghi chú này";
      }

      final String gId = (data['groupId'] ?? '').toString();
      await _deleteNoteRecord(noteRef, data);
      await saveActivity(
        "Xóa ghi chú",
        "Đã xóa: $title",
        groupId: gId.isNotEmpty ? gId : null,
      );
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi xóa ghi chú: $e";
    }
  }

  static Future<String> hideNoteForMe(String noteId) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      await _db.collection('notes').doc(noteId).update({
        'hiddenBy': FieldValue.arrayUnion([myEmail]),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi ẩn ghi chú: $e";
    }
  }

  static Future<String> removeSelfFromSharedNote(String noteId) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      await _db.collection('notes').doc(noteId).update({
        'sharedWith': FieldValue.arrayRemove([myEmail]),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi gỡ bỏ: $e";
    }
  }

  static Stream<QuerySnapshot> getMyNotesStream() {
    return _db
        .collection('notes')
        .where('userId', isEqualTo: currentUid)
        .where('groupId', isEqualTo: '')
        .snapshots();
  }

  static Stream<QuerySnapshot> getSharedNotesStream() {
    return _db
        .collection('notes')
        .where(
          'sharedWith',
          arrayContains: AppState.currentUserEmail.toLowerCase(),
        )
        .snapshots();
  }

  static Stream<List<Note>> getAllMyNotesStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    // 1. Personal notes
    final personal = _db
        .collection('notes')
        .where('userId', isEqualTo: currentUid)
        .where('groupId', isEqualTo: '')
        .snapshots();

    // 2. Shared notes
    final shared = _db
        .collection('notes')
        .where('sharedWith', arrayContains: myEmail)
        .snapshots();

    // 3. Assigned notes in groups
    final assigned = _db
        .collection('notes')
        .where('assigneeEmails', arrayContains: myEmail)
        .snapshots();

    final controller = StreamController<List<Note>>.broadcast();
    final Map<int, List<Note>> latestResults = {};
    final subscriptions = <StreamSubscription>[];
    final Map<String, StreamSubscription> groupNoteSubs = {};

    void emitMerged() {
      if (controller.isClosed) return;
      final allNotesMap = <String, Note>{};
      for (final notes in latestResults.values) {
        for (final note in notes) {
          // Chỉ thêm nếu không có trong danh sách ẩn của user hiện tại
          if (!note.hiddenBy.contains(myEmail)) {
            allNotesMap[note.id] = note;
          }
        }
      }
      controller.add(allNotesMap.values.toList());
    }

    final streams = [personal, shared, assigned];
    for (int i = 0; i < streams.length; i++) {
      subscriptions.add(
        streams[i].listen(
          (snapshot) {
            latestResults[i] = snapshot.docs.map(noteFromDocument).toList();
            emitMerged();
          },
          onError: (e) {
            debugPrint('Stream error $i: $e');
            latestResults[i] = [];
            emitMerged();
          },
        ),
      );
    }

    // 4. All group notes (nhóm mà mình là thành viên)
    // Key riêng cho mỗi nhóm: dùng groupId.hashCode + offset an toàn
    final Map<String, int> groupKeyMap = {};
    int nextGroupKey = 1000;
    subscriptions.add(
      _db
          .collection('groups')
          .where('members', arrayContains: myEmail)
          .snapshots()
          .listen((groupsSnapshot) {
            final currentGroupIds = <String>{};
            for (final groupDoc in groupsSnapshot.docs) {
              final groupId = groupDoc.id;
              currentGroupIds.add(groupId);
              if (groupNoteSubs.containsKey(groupId)) continue;

              // Gán key cố định cho mỗi nhóm
              groupKeyMap[groupId] ??= nextGroupKey++;

              groupNoteSubs[groupId] = _db
                  .collection('notes')
                  .where('groupId', isEqualTo: groupId)
                  .snapshots()
                  .listen(
                    (notesSnapshot) {
                      latestResults[groupKeyMap[groupId]!] = notesSnapshot.docs
                          .map(noteFromDocument)
                          .toList();
                      emitMerged();
                    },
                    onError: (e) {
                      debugPrint('Group notes stream error ($groupId): $e');
                    },
                  );
            }
            // Dọn dẹp nhóm đã rời
            final removedGroups = groupNoteSubs.keys.toSet().difference(
              currentGroupIds,
            );
            for (final removed in removedGroups) {
              groupNoteSubs[removed]?.cancel();
              groupNoteSubs.remove(removed);
              final key = groupKeyMap.remove(removed);
              if (key != null) latestResults.remove(key);
            }
            emitMerged();
          }),
    );

    controller.onCancel = () {
      for (final s in subscriptions) {
        s.cancel();
      }
      for (final s in groupNoteSubs.values) {
        s.cancel();
      }
      groupNoteSubs.clear();
      controller.close();
    };

    return controller.stream;
  }

  static Stream<QuerySnapshot> getNoteInvitesStream() {
    return _db
        .collection('note_invites')
        .where('toEmail', isEqualTo: AppState.currentUserEmail.toLowerCase())
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Future<String> shareNote(String noteId, String targetEmail) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final email = targetEmail.toLowerCase().trim();
    if (email == AppState.currentUserEmail.toLowerCase().trim()) {
      return "Không thể chia sẻ cho chính mình";
    }

    try {
      final noteDoc = await _db.collection('notes').doc(noteId).get();
      if (!noteDoc.exists) return "Ghi chú không tồn tại";

      final data = noteDoc.data()!;
      if (data['userId'] != currentUid) {
        return "Chỉ chủ sở hữu mới được chia sẻ";
      }

      final sharedWith = List<String>.from(data['sharedWith'] ?? []);
      if (sharedWith.contains(email)) return "Đã chia sẻ cho người này rồi";

      // Check for existing invite
      final existing = await _db
          .collection('note_invites')
          .where('noteId', isEqualTo: noteId)
          .where('toEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .get();
      if (existing.docs.isNotEmpty) return "Đã gửi lời mời cho người này rồi";

      await _db.collection('note_invites').add({
        'noteId': noteId,
        'noteTitle': data['title'] ?? 'Ghi chú không tiêu đề',
        'fromEmail': AppState.currentUserEmail,
        'fromName': AppState.currentUserName,
        'toEmail': email,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return "SUCCESS";
    } catch (e) {
      debugPrint("Share Note Error: $e");
      return "Lỗi khi chia sẻ ghi chú: ${e.toString()}";
    }
  }

  static Future<String> respondToNoteInvite(
    String inviteId,
    bool accept,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final inviteRef = _db.collection('note_invites').doc(inviteId);
      final inviteDoc = await inviteRef.get();
      if (!inviteDoc.exists) return "Lời mời không tồn tại";

      final data = inviteDoc.data()!;
      if (data['toEmail'] != AppState.currentUserEmail.toLowerCase()) {
        return "Bạn không có quyền thực hiện hành động này";
      }

      if (accept) {
        final noteId = data['noteId'];
        await _db.collection('notes').doc(noteId).update({
          'sharedWith': FieldValue.arrayUnion([
            AppState.currentUserEmail.toLowerCase(),
          ]),
        });
        await inviteRef.update({'status': 'accepted'});
      } else {
        await inviteRef.update({'status': 'rejected'});
      }
      return "SUCCESS";
    } catch (e) {
      return "Lỗi phản hồi lời mời: $e";
    }
  }

  static Future<String> uploadGroupAvatar(
    File file,
    String fileName,
    String groupId,
  ) async {
    if (currentUid.isEmpty) {
      throw Exception('Bạn cần đăng nhập để tải ảnh nhóm.');
    }
    if (groupId.isEmpty) {
      throw Exception('ID nhóm không hợp lệ.');
    }

    try {
      final safeName = sanitizeFileName(fileName);
      final uniqueName =
          "${DateTime.now().millisecondsSinceEpoch}_${safeName.hashCode.abs()}_$safeName";
      final ref = _storage.ref().child('group_avatars/$groupId/$uniqueName');

      debugPrint("Starting Group Avatar upload to: ${ref.fullPath}");

      final metadata = SettableMetadata(
        contentType: guessMimeType(fileName),
        customMetadata: {'groupId': groupId},
      );

      final uploadTask = ref.putFile(file, metadata);
      final snapshot = await uploadTask;

      debugPrint("Upload completed. State: ${snapshot.state}");

      if (snapshot.state != TaskState.success) {
        throw Exception("Tải lên thất bại với trạng thái: ${snapshot.state}");
      }

      final url = await _getDownloadUrlWithRetry(snapshot.ref);
      if (url.isEmpty) {
        throw Exception('Không lấy được link ảnh sau khi tải lên.');
      }
      return url;
    } catch (e) {
      debugPrint(
        "Storage Upload Failed (Group): $e. Checking Base64 fallback...",
      );
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length < 950 * 1024) {
          debugPrint(
            "Using Base64 fallback for Group Avatar (${bytes.length} bytes)",
          );
          return buildDataUri(bytes, fileName);
        }
      } catch (fallbackError) {
        debugPrint("Base64 Fallback failed: $fallbackError");
      }
      rethrow;
    }
  }

  static Future<String> uploadAttachmentFile(
    File file,
    String fileName, {
    int? fileSize,
  }) async {
    if (currentUid.isEmpty) {
      throw Exception('Bạn cần đăng nhập để tải tệp lên.');
    }
    try {
      if (!await file.exists()) {
        throw Exception("Tệp không tồn tại tại đường dẫn: ${file.path}");
      }
      final ref = _attachmentRef(fileName);

      debugPrint("Starting Attachment upload to: ${ref.fullPath}");

      final metadata = _attachmentMetadata(fileName);
      final uploadTask = ref.putFile(file, metadata);
      final snapshot = await uploadTask;

      debugPrint("Upload completed. State: ${snapshot.state}");

      if (snapshot.state != TaskState.success) {
        throw Exception("Tải lên thất bại với trạng thái: ${snapshot.state}");
      }

      final url = await _getDownloadUrlWithRetry(ref);
      if (url.isEmpty) {
        throw Exception('Không lấy được link tệp sau khi tải lên.');
      }
      return url;
    } on FirebaseException catch (e) {
      debugPrint("Firebase Storage Error (File): [${e.code}] ${e.message}");
      // Dự phòng Base64 cho ảnh nếu Storage bị chặn
      // Dự phòng Base64 cho TẤT CẢ các loại tệp nếu Storage bị chặn và tệp đủ nhỏ (<950KB)
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length < 950 * 1024) {
          debugPrint(
            "Using Base64 fallback for Document/File (${bytes.length} bytes)",
          );
          return buildDataUri(bytes, fileName);
        } else {
          debugPrint(
            "File too large for Base64 (${bytes.length} bytes). Storage is required.",
          );
        }
      } catch (_) {}
      rethrow;
    } catch (e) {
      debugPrint("Upload file error: $e");
      rethrow;
    }
  }

  static Future<void> toggleNotePin(String noteId, bool shouldPin) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    await _db.collection('notes').doc(noteId).update({
      'pinnedBy': shouldPin
          ? FieldValue.arrayUnion([myEmail])
          : FieldValue.arrayRemove([myEmail]),
    });
  }

  static Future<void> toggleGroupNotePin(String noteId, bool shouldPin) async {
    await _db.collection('notes').doc(noteId).update({'isPinned': shouldPin});
  }

  static Future<void> markNoteAsViewed(String noteId) async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    await _db.collection('notes').doc(noteId).update({
      'viewedBy': FieldValue.arrayUnion([myEmail]),
    });
  }

  static Future<void> markAllSharedNotesAsViewed() async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    // Get all unread shared notes
    final shared = await _db
        .collection('notes')
        .where('sharedWith', arrayContains: myEmail)
        .get();

    // Get all unread assigned notes
    final assigned = await _db
        .collection('notes')
        .where('assigneeEmails', arrayContains: myEmail)
        .get();

    final batch = _db.batch();
    int count = 0;

    for (var doc in [...shared.docs, ...assigned.docs]) {
      final viewedBy = List<String>.from(doc.data()['viewedBy'] ?? []);
      if (!viewedBy.contains(myEmail)) {
        batch.update(doc.reference, {
          'viewedBy': FieldValue.arrayUnion([myEmail]),
        });
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  static Future<String> uploadUserAvatar(File file, String fileName) async {
    if (currentUid.isEmpty) {
      throw Exception('Bạn cần đăng nhập để tải ảnh đại diện.');
    }
    try {
      final storage = _storage;
      final safeName = sanitizeFileName(fileName);
      final uniqueName =
          "${DateTime.now().millisecondsSinceEpoch}_${safeName.hashCode.abs()}_$safeName";
      final ref = storage.ref().child('avatars/$currentUid/$uniqueName');

      debugPrint(
        "Starting User Avatar upload to: ${ref.fullPath} (UID: $currentUid)",
      );

      final metadata = SettableMetadata(
        contentType: guessMimeType(fileName),
        customMetadata: {'uploadedBy': currentUid},
      );

      final uploadTask = ref.putFile(file, metadata);
      final snapshot = await uploadTask;

      debugPrint("Upload completed. State: ${snapshot.state}");

      if (snapshot.state != TaskState.success) {
        throw Exception("Tải lên thất bại với trạng thái: ${snapshot.state}");
      }

      final url = await _getDownloadUrlWithRetry(snapshot.ref);
      if (url.isEmpty) {
        throw Exception('Không lấy được link ảnh sau khi tải lên.');
      }
      return url;
    } catch (e) {
      debugPrint("Storage Upload Failed: $e. Checking Base64 fallback...");
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length < 950 * 1024) {
          debugPrint("Using Base64 fallback (Size: ${bytes.length} bytes)");
          return buildDataUri(bytes, fileName);
        } else {
          debugPrint("File too large for Base64 (${bytes.length} bytes)");
        }
      } catch (fallbackError) {
        debugPrint("Base64 Fallback failed: $fallbackError");
      }
      rethrow;
    }
  }

  static Future<String> uploadAttachment(
    Uint8List bytes,
    String fileName,
  ) async {
    if (currentUid.isEmpty) {
      throw Exception('Bạn cần đăng nhập để thực hiện tác vụ này.');
    }
    try {
      final ref = _attachmentRef(fileName);
      final metadata = _attachmentMetadata(fileName);
      debugPrint("Starting Byte Upload to Storage: ${ref.fullPath}");
      final task = ref.putData(bytes, metadata);

      final snapshot = await task;
      if (snapshot.state != TaskState.success) {
        throw Exception('Tải lên thất bại với trạng thái: ${snapshot.state}');
      }

      final url = await _getDownloadUrlWithRetry(snapshot.ref);
      if (url.isEmpty) {
        throw Exception('Đã tải lên nhưng không lấy được link truy cập.');
      }
      return url;
    } on FirebaseException catch (e) {
      debugPrint("Firebase Storage Error (Bytes): [${e.code}] ${e.message}");
      throw Exception('Lỗi Firebase Storage [${e.code}]: ${e.message}');
    } catch (e) {
      debugPrint("Upload bytes error: $e");
      throw Exception('Lỗi không xác định khi tải tệp: $e');
    }
  }

  static Future<String> _getDownloadUrlWithRetry(
    Reference ref, {
    int maxRetries = 10,
  }) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        if (i > 0) await Future.delayed(Duration(seconds: 2 + i));
        return await ref.getDownloadURL();
      } on FirebaseException catch (e) {
        if ((e.code == 'object-not-found' || e.code == 'canceled') &&
            i < maxRetries - 1) {
          debugPrint(
            "Storage: File not ready or busy (Attempt ${i + 1}), retrying...",
          );
          continue;
        }
        debugPrint("Storage Error: [${e.code}] ${e.message}");
        return '';
      }
    }
    return '';
  }

  static Future<void> deleteAttachment(String url) async {
    final value = url.trim();
    if (value.isEmpty || isDataUri(value)) return;
    if (!value.contains('firebasestorage.googleapis.com')) return;
    try {
      final ref = _storage.refFromURL(value);
      // Kiểm tra sự tồn tại trước khi xóa (best effort)
      try {
        await ref.delete();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint("Storage: Object already deleted.");
        } else {
          rethrow;
        }
      }
    } catch (e) {
      debugPrint("Storage Delete Error (Ignored): $e");
    }
  }

  static Future<String> createGroup(String name, [String? avatar]) async {
    try {
      if (currentUid.isEmpty) return "Lỗi: Bạn chưa đăng nhập";
      final cleanName = name.trim();
      if (cleanName.isEmpty) return "Tên nhóm không được để trống";

      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      if (myEmail.isEmpty) return "Lỗi: Không tìm thấy email người dùng";

      final code = _generateGroupCode();
      final groupRef = await _db.collection('groups').add({
        'name': cleanName,
        'avatar':
            avatar ??
            "https://ui-avatars.com/api/?name=$cleanName&background=random",
        'leaderId': currentUid,
        'leaderEmail': myEmail,
        'leaderName': AppState.currentUserName.isNotEmpty
            ? AppState.currentUserName
            : "Trưởng nhóm",
        'members': [myEmail],
        'managerEmails': [],
        'groupCode': code,
        'requiresApproval': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('group_codes').doc(code).set({
        'groupId': groupRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await saveActivity(
        "Tạo nhóm",
        "Đã tạo nhóm: $cleanName",
        groupId: groupRef.id,
      );

      return "SUCCESS";
    } catch (e) {
      debugPrint("Create Group Error: $e");
      return "Lỗi khi tạo nhóm: ${e.toString()}";
    }
  }

  static String _generateGroupCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(
      6,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static Future<void> addGroupSystemMessage(String groupId, String text) async {
    await _db.collection('groups').doc(groupId).collection('comments').add({
      'userId': 'system',
      'userEmail': 'system@snote.app',
      'userName': 'Hệ thống',
      'userAvatar': '',
      'text': text,
      'isSystem': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<String> updateGroupName(String groupId, String name) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanName = name.trim();
    if (groupId.isEmpty) return "Không tìm thấy nhóm";
    if (cleanName.isEmpty) return "Tên nhóm không được để trống";

    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return "Nhóm không tồn tại";
    final data = groupDoc.data() as Map<String, dynamic>;
    if (data['leaderId'] != currentUid) {
      return "Chỉ trưởng nhóm mới được đổi tên";
    }

    final previousName = data['name'] ?? '';
    await _db.collection('groups').doc(groupId).update({
      'name': cleanName,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final notes = await _db
        .collection('notes')
        .where('groupId', isEqualTo: groupId)
        .get();
    for (final noteDoc in notes.docs) {
      await noteDoc.reference.update({
        'groupName': cleanName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await addGroupSystemMessage(
      groupId,
      '${AppState.currentUserName} đã đổi tên nhóm từ "$previousName" thành "$cleanName".',
    );
    await saveActivity(
      "Sửa nhóm",
      "Đã đổi tên nhóm thành: $cleanName",
      groupId: groupId,
    );
    return "SUCCESS";
  }

  static Future<String> updateGroupAvatar(
    String groupId,
    String avatarUrl,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (groupId.isEmpty) return "Không tìm thấy nhóm";
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return "Nhóm không tồn tại";
    final data = groupDoc.data() as Map<String, dynamic>;
    if (data['leaderId'] != currentUid) {
      return "Chỉ trưởng nhóm mới được đổi ảnh nhóm";
    }

    await _db.collection('groups').doc(groupId).update({
      'avatar': avatarUrl.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addGroupSystemMessage(
      groupId,
      '${AppState.currentUserName} đã cập nhật ảnh nhóm.',
    );
    await saveActivity(
      "Sửa nhóm",
      "Đã đổi ảnh nhóm ${data['name'] ?? ''}",
      groupId: groupId,
    );
    return "SUCCESS";
  }

  static Future<String> toggleGroupPin(String groupId, bool shouldPin) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (groupId.isEmpty) return "Không tìm thấy nhóm";
    final email = AppState.currentUserEmail.toLowerCase().trim();
    await _db.collection('groups').doc(groupId).update({
      'pinnedBy': shouldPin
          ? FieldValue.arrayUnion([email])
          : FieldValue.arrayRemove([email]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await saveActivity(
      shouldPin ? "Ghim nhóm" : "Bỏ ghim nhóm",
      shouldPin ? "Đã ghim nhóm $groupId" : "Đã bỏ ghim nhóm $groupId",
      groupId: groupId,
    );
    return "SUCCESS";
  }

  static Future<bool> isGroupPinned(String groupId) async {
    if (currentUid.isEmpty || groupId.isEmpty) return false;
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return false;
    final data = groupDoc.data() ?? {};
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return _normalizeEmailList(data['pinnedBy']).contains(myEmail);
  }

  static Future<String> joinGroupByCode(String code) async {
    final cleanCode = code.toUpperCase().trim();
    if (currentUid.isEmpty) return "Chưa đăng nhập";

    try {
      final codeDoc = await _db.collection('group_codes').doc(cleanCode).get();
      if (!codeDoc.exists) {
        return "Mã nhóm không tồn tại! Vui lòng kiểm tra lại.";
      }

      final groupId = (codeDoc.data()?['groupId'] ?? '').toString().trim();
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";

      final data = groupDoc.data() ?? {};
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      final members = _groupMemberEmails(data);
      if (members.contains(myEmail)) return "Bạn đã ở trong nhóm này rồi!";

      final requiresApproval = data['requiresApproval'] == true;

      if (!requiresApproval) {
        // Tham gia trực tiếp nếu không cần duyệt
        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayUnion([myEmail]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await addGroupSystemMessage(
          groupId,
          '${AppState.currentUserName} đã tham gia nhóm bằng mã mời.',
        );
        await saveActivity(
          "Tham gia nhóm",
          "Đã tham gia nhóm $groupId bằng mã",
          groupId: groupId,
        );
        return "SUCCESS";
      }

      // Nếu cần duyệt, tạo yêu cầu như cũ
      final existing = await _db
          .collection('group_requests')
          .where('groupId', isEqualTo: groupId)
          .where('userEmail', isEqualTo: myEmail)
          .where('status', isEqualTo: 'pending')
          .get();
      if (existing.docs.isNotEmpty) {
        return "Bạn đã gửi yêu cầu rồi, hãy chờ trưởng nhóm duyệt";
      }

      await _db.collection('group_requests').add({
        'groupId': groupId,
        'groupName': (data['name'] ?? 'Nhóm không tên').toString(),
        'leaderId': data['leaderId'],
        'userEmail': myEmail,
        'userName': AppState.currentUserName,
        'userAvatar': AppState.currentUserAvatar,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return "WAIT_APPROVAL";
    } catch (e) {
      return "Lỗi hệ thống: $e";
    }
  }

  static Future<String> respondToGroupRequest(
    String requestId,
    bool approve,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final requestRef = _db.collection('group_requests').doc(requestId);
      final requestDoc = await requestRef.get();
      if (!requestDoc.exists) return "Yêu cầu không tồn tại";

      final data = requestDoc.data()!;
      final groupId = data['groupId'];
      if (!await canCurrentUserManageGroupTasks(groupId)) {
        return "Chỉ trưởng nhóm hoặc quản lý mới được duyệt yêu cầu";
      }

      if (approve) {
        final userEmail = data['userEmail'];
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final members = _groupMemberEmails(
            groupDoc.data() ?? <String, dynamic>{},
          );
          if (members.contains(userEmail.toString().toLowerCase().trim())) {
            await requestRef.update({'status': 'approved'});
            return "SUCCESS"; // Already in group, just clean up request
          }
        }

        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayUnion([userEmail]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await addGroupSystemMessage(
          groupId,
          '${data['userName']} đã tham gia nhóm sau khi được duyệt.',
        );
        await requestRef.update({'status': 'approved'});
        await saveActivity(
          "Duyệt yêu cầu",
          "Đã duyệt ${data['userName']} vào nhóm",
          groupId: groupId,
        );
      } else {
        await requestRef.update({'status': 'rejected'});
      }
      return "SUCCESS";
    } catch (e) {
      return "Lỗi duyệt yêu cầu: $e";
    }
  }

  static Future<void> goOffline() async {
    if (currentUid.isEmpty) return;
    try {
      // Mark as offline but keep the actual lastActive time as now
      await _db.collection('users').doc(currentUid).update({
        'isOnline': false,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Future<void> updateUserActiveStatus() async {
    if (currentUid.isEmpty) return;
    try {
      await _db.collection('users').doc(currentUid).update({
        'isOnline': true,
        'lastActive': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Create if doesn't exist (failsafe)
      try {
        await _db.collection('users').doc(currentUid).set({
          'email': AppState.currentUserEmail.toLowerCase().trim(),
          'name': AppState.currentUserName,
          'isOnline': true,
          'lastActive': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  static Stream<DocumentSnapshot?> getUserByEmailStream(String email) {
    return _db
        .collection('users')
        .where('email', isEqualTo: email.toLowerCase().trim())
        .limit(1)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.isNotEmpty ? snapshot.docs.first : null,
        );
  }

  static List<String> _uniqueNormalizedEmails(List<String> emails) {
    final normalizedEmails = <String>[];
    final seenEmails = <String>{};
    for (final email in emails) {
      final normalized = email.toLowerCase().trim();
      if (normalized.isEmpty || !seenEmails.add(normalized)) continue;
      normalizedEmails.add(normalized);
    }
    return normalizedEmails;
  }

  static bool _sameStringList(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i] != second[i]) return false;
    }
    return true;
  }

  static Stream<List<Map<String, dynamic>>> _groupUsersStream(
    String groupId, {
    bool onlineOnly = false,
  }) {
    late final StreamController<List<Map<String, dynamic>>> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
    groupSubscription;
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    var normalizedEmails = <String>[];
    var latestChunks = <List<Map<String, dynamic>>>[];

    Future<void> cancelUserSubscriptions() async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
    }

    void emitUsers() {
      final usersByEmail = <String, Map<String, dynamic>>{};
      final onlineCutoff = DateTime.now().subtract(const Duration(minutes: 5));

      for (final chunk in latestChunks) {
        for (final user in chunk) {
          if (onlineOnly && !_isRecentlyOnline(user, onlineCutoff)) continue;

          final email = (user['email'] ?? '').toString().toLowerCase().trim();
          if (email.isEmpty) continue;
          usersByEmail[email] = user;
        }
      }

      controller.add([
        for (final email in normalizedEmails)
          if (usersByEmail[email] != null) usersByEmail[email]!,
      ]);
    }

    Future<void> listenToEmails(List<String> emails) async {
      final nextEmails = _uniqueNormalizedEmails(emails);
      if (_sameStringList(normalizedEmails, nextEmails)) return;

      await cancelUserSubscriptions();
      normalizedEmails = nextEmails;

      if (normalizedEmails.isEmpty) {
        latestChunks = const <List<Map<String, dynamic>>>[];
        controller.add(const <Map<String, dynamic>>[]);
        return;
      }

      final chunks = <List<String>>[];
      for (var i = 0; i < normalizedEmails.length; i += 30) {
        final end = min(i + 30, normalizedEmails.length);
        chunks.add(normalizedEmails.sublist(i, end));
      }
      latestChunks = List<List<Map<String, dynamic>>>.filled(
        chunks.length,
        const <Map<String, dynamic>>[],
      );

      for (var index = 0; index < chunks.length; index++) {
        final chunkIndex = index;
        final subscription = _db
            .collection('users')
            .where('email', whereIn: chunks[chunkIndex])
            .snapshots()
            .listen((snapshot) {
              latestChunks[chunkIndex] = snapshot.docs.map((doc) {
                final data = Map<String, dynamic>.from(doc.data());
                data['uid'] = doc.id;
                return data;
              }).toList();
              emitUsers();
            }, onError: controller.addError);
        subscriptions.add(subscription);
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        groupSubscription = _db
            .collection('groups')
            .doc(groupId)
            .snapshots()
            .listen((groupDoc) async {
              try {
                if (!groupDoc.exists) {
                  await listenToEmails(const <String>[]);
                  return;
                }

                await listenToEmails(
                  _groupMemberEmails(groupDoc.data() ?? <String, dynamic>{}),
                );
              } catch (error, stackTrace) {
                controller.addError(error, stackTrace);
              }
            }, onError: controller.addError);
      },
      onCancel: () async {
        await groupSubscription?.cancel();
        await cancelUserSubscriptions();
      },
    );

    return controller.stream;
  }

  static bool _isRecentlyOnline(
    Map<String, dynamic> userData,
    DateTime cutoff,
  ) {
    if (userData['isOnline'] != true) return false;

    final lastActive = userData['lastActive'];
    if (lastActive is Timestamp) {
      return lastActive.toDate().isAfter(cutoff);
    }
    return true;
  }

  static Stream<List<Map<String, dynamic>>> getGroupMembersStream(
    String groupId,
  ) {
    if (groupId.isEmpty) return Stream.value([]);
    return _groupUsersStream(groupId);
  }

  static Stream<List<Map<String, dynamic>>> getOnlineGroupMembersStream(
    String groupId,
  ) {
    if (groupId.isEmpty) return Stream.value([]);
    return _groupUsersStream(groupId, onlineOnly: true);
  }

  static Future<String> toggleGroupApprovalRequirement(
    String groupId,
    bool enabled,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (!await canCurrentUserManageGroupTasks(groupId)) {
      return "Bạn không có quyền thay đổi cài đặt này";
    }
    await _db.collection('groups').doc(groupId).update({
      'requiresApproval': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await saveActivity(
      "Sửa nhóm",
      enabled ? "Đã bật duyệt thành viên" : "Đã tắt duyệt thành viên",
      groupId: groupId,
    );
    return "SUCCESS";
  }

  static Stream<QuerySnapshot> getMyGroupsStream() {
    return _db
        .collection('groups')
        .where(
          'members',
          arrayContains: AppState.currentUserEmail.toLowerCase(),
        )
        .snapshots();
  }

  static Future<String> addMemberToGroup(
    String groupId,
    String memberEmail,
  ) async {
    try {
      if (currentUid.isEmpty) return "Chưa đăng nhập";
      final email = memberEmail.toLowerCase().trim();
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      if (groupId.isEmpty || email.isEmpty) return "Dữ liệu không hợp lệ";
      if (email == myEmail) return "Bạn đã ở trong nhóm này rồi!";

      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";
      final data = groupDoc.data()!;
      if (data['leaderId'] != currentUid) {
        return "Chỉ trưởng nhóm mới được mời thành viên";
      }

      if (email == myEmail) return "Bạn không thể mời chính mình vào nhóm";

      final members = _groupMemberEmails(data);
      if (members.contains(email)) return "Người này đã có trong nhóm";

      final existing = await _db
          .collection('group_invites')
          .where('groupId', isEqualTo: groupId)
          .where('toEmail', isEqualTo: email)
          .where('status', isEqualTo: 'pending')
          .get();
      if (existing.docs.isNotEmpty) return "Đã có lời mời đang chờ phản hồi";

      await _db.collection('group_invites').add({
        'groupId': groupId,
        'groupName': (data['name'] ?? 'Nhóm không tên').toString(),
        'fromEmail': AppState.currentUserEmail,
        'fromName': AppState.currentUserName,
        'toEmail': email,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await saveActivity(
        "Mời vào nhóm",
        "Đã mời $email vào nhóm ${(data['name'] ?? '').toString()}",
        groupId: groupId,
      );
      return "SUCCESS";
    } catch (e) {
      debugPrint("Add Member Error: $e");
      return "Lỗi khi mời thành viên: ${e.toString()}";
    }
  }

  static Future<String> respondToGroupInvite(
    String inviteId,
    bool accept,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final inviteRef = _db.collection('group_invites').doc(inviteId);
      final inviteDoc = await inviteRef.get();
      if (!inviteDoc.exists) return "Lời mời không tồn tại";

      final data = inviteDoc.data()!;
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      if (data['toEmail'] != myEmail) {
        return "Bạn không có quyền thực hiện hành động này";
      }

      if (accept) {
        final groupId = data['groupId'];
        final groupDoc = await _db.collection('groups').doc(groupId).get();
        if (groupDoc.exists) {
          final members = _groupMemberEmails(
            groupDoc.data() ?? <String, dynamic>{},
          );
          if (members.contains(myEmail)) {
            await inviteRef.update({'status': 'accepted'});
            return "SUCCESS"; // Already in group
          }
        }

        await _db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayUnion([myEmail]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await addGroupSystemMessage(
          groupId,
          '${AppState.currentUserName} đã tham gia nhóm sau khi chấp nhận lời mời.',
        );
        await inviteRef.update({'status': 'accepted'});
        await saveActivity(
          "Tham gia nhóm",
          "Đã tham gia nhóm ${data['groupName'] ?? ''}",
          groupId: groupId,
        );
      } else {
        await inviteRef.update({'status': 'rejected'});
      }
      return "SUCCESS";
    } catch (e) {
      return "Lỗi phản hồi lời mời: $e";
    }
  }

  static Future<String> removeMemberFromGroup(
    String groupId,
    String memberEmail,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final email = memberEmail.toLowerCase().trim();
    if (groupId.isEmpty || email.isEmpty) return "Dữ liệu không hợp lệ";

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";
      final data = groupDoc.data() as Map<String, dynamic>;
      final isSelf = email == AppState.currentUserEmail.toLowerCase().trim();
      final isLeader = data['leaderId'] == currentUid;

      if (!isSelf && !isLeader) {
        return "Chỉ trưởng nhóm mới được xóa thành viên khác";
      }
      if (isSelf && isLeader) {
        return "Trưởng nhóm không thể rời nhóm. Hãy giải tán nhóm nếu cần";
      }

      await _db.collection('groups').doc(groupId).update({
        'members': FieldValue.arrayRemove([email]),
        'managerEmails': FieldValue.arrayRemove([email]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await addGroupSystemMessage(
        groupId,
        isSelf
            ? '${AppState.currentUserName} đã rời nhóm.'
            : '${AppState.currentUserName} đã xóa $email khỏi nhóm.',
      );
      await saveActivity(
        isSelf ? "Rời nhóm" : "Xóa thành viên",
        isSelf
            ? "Đã rời nhóm ${data['name'] ?? ''}"
            : "Đã xóa $email khỏi nhóm ${data['name'] ?? ''}",
        groupId: groupId,
      );
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi thay đổi thành viên: $e";
    }
  }

  static Future<String> updateGroupManagerRole(
    String groupId,
    String memberEmail,
    bool shouldPromote,
  ) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    final email = memberEmail.toLowerCase().trim();
    if (groupId.trim().isEmpty || email.isEmpty) return "Dữ liệu không hợp lệ";

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";
      final data = groupDoc.data() ?? {};
      if (data['leaderId'] != currentUid) {
        return "Chỉ trưởng nhóm mới được đổi quyền thành viên";
      }

      final members = _groupMemberEmails(data);
      if (!members.contains(email)) {
        return "Thành viên này không còn trong nhóm";
      }
      if (email == AppState.currentUserEmail.toLowerCase().trim()) {
        return "Trưởng nhóm đã có key vàng mặc định";
      }

      await _db.collection('groups').doc(groupId).update({
        'managerEmails': shouldPromote
            ? FieldValue.arrayUnion([email])
            : FieldValue.arrayRemove([email]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await addGroupSystemMessage(
        groupId,
        shouldPromote
            ? '${AppState.currentUserName} đã cấp key bạc cho $email.'
            : '${AppState.currentUserName} đã thu hồi key bạc của $email.',
      );
      await saveActivity(
        shouldPromote ? "Cấp quyền nhóm" : "Thu hồi quyền nhóm",
        shouldPromote
            ? "Đã cấp key bạc cho $email"
            : "Đã thu hồi key bạc của $email",
        groupId: groupId,
      );
      return "SUCCESS";
    } catch (e) {
      return "Lỗi đổi quyền: $e";
    }
  }

  static Future<String> deleteGroup(String groupId) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    if (groupId.isEmpty) return "Không tìm thấy nhóm";

    try {
      final groupDoc = await _db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";
      final data = groupDoc.data() as Map<String, dynamic>;
      if (data['leaderId'] != currentUid) {
        return "Chỉ trưởng nhóm mới được giải tán nhóm";
      }

      // Cleanup Notes
      final notes = await _db
          .collection('notes')
          .where('groupId', isEqualTo: groupId)
          .get();
      for (final doc in notes.docs) {
        await _deleteNoteRecord(doc.reference, doc.data());
      }

      // Cleanup Comments
      await _deleteCollectionDocs(
        _db.collection('groups').doc(groupId).collection('comments'),
      );

      // Cleanup Invites
      final invites = await _db
          .collection('group_invites')
          .where('groupId', isEqualTo: groupId)
          .get();
      for (final doc in invites.docs) {
        await doc.reference.delete();
      }

      // Cleanup Requests
      final requests = await _db
          .collection('group_requests')
          .where('groupId', isEqualTo: groupId)
          .get();
      for (final doc in requests.docs) {
        await doc.reference.delete();
      }

      // Cleanup Group Code
      final groupCode = (data['groupCode'] ?? '').toString().trim();
      if (groupCode.isNotEmpty) {
        await _db.collection('group_codes').doc(groupCode).delete();
      }

      // Delete Group itself
      await _db.collection('groups').doc(groupId).delete();

      await saveActivity(
        "Xóa nhóm",
        "Đã giải tán nhóm ${data['name'] ?? ''}",
        groupId: groupId,
      );
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi giải tán nhóm: $e";
    }
  }

  static Stream<QuerySnapshot> getGroupNotesStream(String groupId) {
    return _db
        .collection('notes')
        .where('groupId', isEqualTo: groupId)
        .snapshots();
  }

  static Stream<DocumentSnapshot> getGroupStream(String groupId) {
    return _db.collection('groups').doc(groupId).snapshots();
  }

  static Future<bool> isCurrentUserGroupLeader(String groupId) async {
    if (currentUid.isEmpty || groupId.isEmpty) return false;
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return false;
    final data = groupDoc.data() as Map<String, dynamic>;
    return data['leaderId'] == currentUid;
  }

  static Future<List<String>> getGroupMemberEmails(String groupId) async {
    if (groupId.isEmpty) return const [];
    final groupDoc = await _db.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) return const [];
    final data = groupDoc.data() as Map<String, dynamic>;
    return _groupMemberEmails(data);
  }

  static Future<List<Note>> getGroupNotesOnce(String groupId) async {
    if (groupId.isEmpty) return const [];
    final snapshot = await _db
        .collection('notes')
        .where('groupId', isEqualTo: groupId)
        .get();
    return snapshot.docs.map(noteFromDocument).toList();
  }

  static Stream<QuerySnapshot> getGroupRequestsForLeaderStream() {
    return _db
        .collection('group_requests')
        .where('leaderId', isEqualTo: currentUid)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Stream<QuerySnapshot> getGroupInvitesStream() {
    return _db
        .collection('group_invites')
        .where('toEmail', isEqualTo: AppState.currentUserEmail.toLowerCase())
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Stream<int> getNotificationCountStream() {
    final noteInvites = getNoteInvitesStream();
    final groupInvites = getGroupInvitesStream();
    final groupRequests = getGroupRequestsForLeaderStream();

    late StreamController<int> controller;
    controller = StreamController<int>.broadcast(
      onListen: () {
        int count1 = 0;
        int count2 = 0;
        int count3 = 0;

        void emit() {
          if (!controller.isClosed) {
            controller.add(count1 + count2 + count3);
          }
        }

        final sub1 = noteInvites.listen((snap) {
          count1 = snap.docs.length;
          emit();
        });
        final sub2 = groupInvites.listen((snap) {
          count2 = snap.docs.length;
          emit();
        });
        final sub3 = groupRequests.listen((snap) {
          count3 = snap.docs.length;
          emit();
        });

        controller.onCancel = () {
          sub1.cancel();
          sub2.cancel();
          sub3.cancel();
        };
      },
    );
    return controller.stream;
  }

  static Future<bool> isTargetMuted({
    required String type,
    required String targetId,
  }) async {
    if (currentUid.isEmpty || targetId.isEmpty) return false;
    final doc = await _db
        .collection('users')
        .doc(currentUid)
        .collection('mutes')
        .doc(targetId)
        .get();
    return doc.exists;
  }

  static Future<String> muteTarget({
    required String type,
    required String targetId,
    bool shouldMute = true,
    String? label,
    Duration? duration,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final muteRef = _db
          .collection('users')
          .doc(currentUid)
          .collection('mutes')
          .doc(targetId);

      if (shouldMute) {
        await muteRef.set({
          'type': type,
          'targetId': targetId,
          'label': label ?? targetId,
          'muteUntil': duration != null
              ? Timestamp.fromDate(DateTime.now().add(duration))
              : null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await muteRef.delete();
      }
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> unmuteTarget({
    required String type,
    required String targetId,
  }) async {
    return await muteTarget(type: type, targetId: targetId, shouldMute: false);
  }

  static Future<String> blockTarget({
    required String type,
    required String targetId,
    required bool shouldBlock,
  }) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      if (type == 'user' &&
          targetId.toLowerCase().trim() ==
              AppState.currentUserEmail.toLowerCase().trim()) {
        return "Không thể tự chặn chính mình";
      }
      final blockRef = _db
          .collection('users')
          .doc(currentUid)
          .collection('blocks')
          .doc(targetId.toLowerCase().trim());

      if (shouldBlock) {
        await blockRef.set({
          'type': type,
          'targetEmail': targetId,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await blockRef.delete();
      }
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> blockUser(String email) async {
    return await blockTarget(type: 'user', targetId: email, shouldBlock: true);
  }

  static Future<String> unblockUser(String email) async {
    return await blockTarget(type: 'user', targetId: email, shouldBlock: false);
  }

  static Stream<QuerySnapshot> getMyMutesStream() {
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('mutes')
        .snapshots();
  }

  static Stream<QuerySnapshot> getMyBlocksStream() {
    return _db
        .collection('users')
        .doc(currentUid)
        .collection('blocks')
        .snapshots();
  }

  static Future<bool> hasBlockedEmail(String uid, String email) async {
    if (uid.isEmpty || email.isEmpty) return false;
    final targetEmail = email.toLowerCase().trim();
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('blocks')
        .doc(targetEmail)
        .get();
    if (doc.exists) return true;

    final legacyDoc = await _db.collection('users').doc(uid).get();
    if (!legacyDoc.exists) return false;
    final blocked = List<String>.from(legacyDoc.data()?['blockedEmails'] ?? []);
    return blocked.contains(targetEmail);
  }

  // --- Admin Methods ---
  static Stream<QuerySnapshot> getAllUsersStream() {
    return _db.collection('users').snapshots();
  }

  static Future<String> changeUserRole(String targetUid, String newRole) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      await _db.collection('users').doc(targetUid).update({'role': newRole});
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> toggleUserBan(String targetUid, bool shouldBan) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      await _db.collection('users').doc(targetUid).update({
        'isBanned': shouldBan,
      });
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> deleteUserAccountByAdmin(String targetUid) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      // NOTE: This only deletes the Firestore record.
      // Deleting the actual Auth account requires Admin SDK or a Cloud Function.
      await _db.collection('users').doc(targetUid).delete();
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  /// Gộp các luồng yêu cầu đang chờ xử lý thành 1 luồng đếm tổng số lượng.
  /// Giúp tối ưu UI, tránh lồng nhiều StreamBuilder.
  static Future<void> markChatAsRead(String friendEmail) async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, friendEmail);
    await _db.collection('chats').doc(chatId).set({
      'unreadCount': {myEmail: 0},
    }, SetOptions(merge: true));
  }

  static Future<void> markGroupAsRead(String groupId) async {
    if (currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    await _db.collection('groups').doc(groupId).set({
      'unreadCount': {myEmail: 0},
    }, SetOptions(merge: true));
  }

  /// Gộp các luồng yêu cầu đang chờ xử lý + tin nhắn chưa đọc thành 1 luồng đếm tổng.
  /// Luồng đếm các yêu cầu (lời mời ghi chú, nhóm, yêu cầu gia nhập) - Dùng cho biểu tượng CHUÔNG.
  static Stream<int> bellRequestsCountStream() {
    final noteInvites = getNoteInvitesStream();
    final groupInvites = getGroupInvitesStream();
    final groupRequests = getGroupRequestsForLeaderStream();
    final friendRequests = getFriendRequestsStream();

    final controller = StreamController<int>.broadcast();
    int countInvites = 0;
    int countGroups = 0;
    int countGroupReqs = 0;
    int countFriends = 0;

    void emitTotal() {
      if (!controller.isClosed) {
        controller.add(
          countInvites + countGroups + countGroupReqs + countFriends,
        );
      }
    }

    final sub1 = noteInvites.listen((s) {
      countInvites = s.docs.length;
      emitTotal();
    });
    final sub2 = groupInvites.listen((s) {
      countGroups = s.docs.length;
      emitTotal();
    });
    final sub3 = groupRequests.listen((s) {
      countGroupReqs = s.docs.length;
      emitTotal();
    });
    final sub4 = friendRequests.listen((s) {
      countFriends = s.docs.length;
      emitTotal();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      sub3.cancel();
      sub4.cancel();
      controller.close();
    };
    return controller.stream;
  }

  /// Luồng đếm tin nhắn chưa đọc (chat cá nhân & nhóm) - Dùng cho biểu tượng MENU (3 gạch).
  /// Luồng đếm tin nhắn chưa đọc từ chat cá nhân.
  static Stream<int> unreadChatMessagesCountStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatsStream = _db
        .collection('chats')
        .where('participants', arrayContains: myEmail)
        .snapshots();
    final mutesStream = _db
        .collection('users')
        .doc(currentUid)
        .collection('mutes')
        .snapshots();

    final controller = StreamController<int>.broadcast();
    Map<String, dynamic> chatUnreads = {};
    Set<String> mutedIds = {};

    void emitTotal() {
      if (controller.isClosed) return;
      int total = 0;
      chatUnreads.forEach((chatId, countData) {
        final participants = countData['participants'] as List<String>;
        final friendEmail = participants.firstWhere(
          (e) => e != myEmail,
          orElse: () => '',
        );
        if (friendEmail.isNotEmpty && !mutedIds.contains(friendEmail)) {
          total +=
              1; // Count each conversation as 1, regardless of message count
        }
      });
      controller.add(total);
    }

    final sub1 = chatsStream.listen((s) {
      chatUnreads.clear();
      for (var doc in s.docs) {
        final data = doc.data();
        final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
        if (unread > 0) {
          chatUnreads[doc.id] = {
            'unread': unread,
            'participants': List<String>.from(data['participants'] ?? []),
          };
        }
      }
      emitTotal();
    });

    final sub2 = mutesStream.listen((s) {
      mutedIds.clear();
      for (var doc in s.docs) {
        final data = doc.data();
        final until = data['muteUntil'];
        bool isActive = true;
        if (until is Timestamp) {
          isActive = until.toDate().isAfter(DateTime.now());
        }
        if (isActive) {
          mutedIds.add(
            (data['targetId'] ?? '').toString().toLowerCase().trim(),
          );
        }
      }
      emitTotal();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  /// Luồng đếm tin nhắn chưa đọc từ nhóm.
  static Stream<int> unreadGroupMessagesCountStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final groupsStream = _db
        .collection('groups')
        .where('members', arrayContains: myEmail)
        .snapshots();
    final mutesStream = _db
        .collection('users')
        .doc(currentUid)
        .collection('mutes')
        .snapshots();

    final controller = StreamController<int>.broadcast();
    Map<String, int> groupUnreads = {};
    Set<String> mutedIds = {};

    void emitTotal() {
      if (controller.isClosed) return;
      int total = 0;
      groupUnreads.forEach((groupId, val) {
        if (!mutedIds.contains(groupId)) {
          total += val;
        }
      });
      controller.add(total);
    }

    final sub1 = groupsStream.listen((s) {
      groupUnreads.clear();
      for (var doc in s.docs) {
        final data = doc.data();
        final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
        if (unread > 0) groupUnreads[doc.id] = unread;
      }
      emitTotal();
    });

    final sub2 = mutesStream.listen((s) {
      mutedIds.clear();
      for (var doc in s.docs) {
        final data = doc.data();
        final until = data['muteUntil'];
        bool isActive = true;
        if (until is Timestamp) {
          isActive = until.toDate().isAfter(DateTime.now());
        }
        if (isActive) {
          mutedIds.add(
            (data['targetId'] ?? '').toString().toLowerCase().trim(),
          );
        }
      }
      emitTotal();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  /// Luồng đếm tin nhắn chưa đọc (chat cá nhân & nhóm) - Dùng cho biểu tượng MENU (3 gạch).
  static Stream<int> unreadSharedNotesCountStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    final sharedStream = _db
        .collection('notes')
        .where('sharedWith', arrayContains: myEmail)
        .snapshots();

    final assignedStream = _db
        .collection('notes')
        .where('assigneeEmails', arrayContains: myEmail)
        .snapshots();

    final controller = StreamController<int>.broadcast();
    Map<String, bool> sharedUnreads = {};
    Map<String, bool> assignedUnreads = {};

    void emitTotal() {
      if (controller.isClosed) return;
      final allUnreadIds = <String>{};
      sharedUnreads.forEach((id, isUnread) {
        if (isUnread) allUnreadIds.add(id);
      });
      assignedUnreads.forEach((id, isUnread) {
        if (isUnread) allUnreadIds.add(id);
      });
      controller.add(allUnreadIds.length);
    }

    final s1 = sharedStream.listen((snap) {
      sharedUnreads.clear();
      for (var doc in snap.docs) {
        final data = doc.data();
        final viewedBy = List<String>.from(data['viewedBy'] ?? []);
        final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);
        if (!hiddenBy.contains(myEmail)) {
          sharedUnreads[doc.id] = !viewedBy.contains(myEmail);
        }
      }
      emitTotal();
    });

    final s2 = assignedStream.listen((snap) {
      assignedUnreads.clear();
      for (var doc in snap.docs) {
        final data = doc.data();
        final viewedBy = List<String>.from(data['viewedBy'] ?? []);
        final hiddenBy = List<String>.from(data['hiddenBy'] ?? []);
        if (!hiddenBy.contains(myEmail)) {
          assignedUnreads[doc.id] = !viewedBy.contains(myEmail);
        }
      }
      emitTotal();
    });

    controller.onCancel = () {
      s1.cancel();
      s2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  static Stream<int> menuNotificationsCountStream() {
    final chatStream = unreadChatMessagesCountStream();
    final groupStream = unreadGroupMessagesCountStream();
    final sharedNotesStream = unreadSharedNotesCountStream();

    final controller = StreamController<int>.broadcast();
    int chatCount = 0;
    int groupCount = 0;
    int sharedCount = 0;

    void emit() {
      if (!controller.isClosed) {
        controller.add(chatCount + groupCount + sharedCount);
      }
    }

    final s1 = chatStream.listen((c) {
      chatCount = c;
      emit();
    });
    final s2 = groupStream.listen((g) {
      groupCount = g;
      emit();
    });
    final s3 = sharedNotesStream.listen((s) {
      sharedCount = s;
      emit();
    });

    controller.onCancel = () {
      s1.cancel();
      s2.cancel();
      s3.cancel();
      controller.close();
    };
    return controller.stream;
  }


  static Future<Map<String, int>> getReLoginSummary() async {
    if (currentUid.isEmpty) return {};
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      // 1. Fetch Mutes
      final mutesSnap = await _db
          .collection('users')
          .doc(currentUid)
          .collection('mutes')
          .get();
      final mutedIds = mutesSnap.docs
          .where((doc) {
            final data = doc.data();
            final until = data['muteUntil'];
            if (until is Timestamp) return until.toDate().isAfter(now);
            return true;
          })
          .map(
            (doc) =>
                (doc.data()['targetId'] ?? '').toString().toLowerCase().trim(),
          )
          .toSet();

      // 2. Unread Messages (Private)
      final chatsSnap = await _db
          .collection('chats')
          .where('participants', arrayContains: myEmail)
          .get();
      int unreadMessages = 0;
      for (var doc in chatsSnap.docs) {
        final data = doc.data();
        final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
        if (unread > 0) {
          final participants = List<String>.from(data['participants'] ?? []);
          final otherEmail = participants.firstWhere(
            (e) => e != myEmail,
            orElse: () => '',
          );
          if (otherEmail.isNotEmpty && !mutedIds.contains(otherEmail)) {
            unreadMessages += unread;
          }
        }
      }

      // 3. Unread Messages (Groups)
      final groupsSnap = await _db
          .collection('groups')
          .where('members', arrayContains: myEmail)
          .get();
      int unreadGroupMessages = 0;
      for (var doc in groupsSnap.docs) {
        final data = doc.data();
        final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
        if (unread > 0 && !mutedIds.contains(doc.id)) {
          unreadGroupMessages += unread;
        }
      }

      // 4. Friend Requests
      final friendReqs = await _db
          .collection('friend_requests')
          .where('to', isEqualTo: myEmail)
          .get();

      // 5. Note Invites
      final noteInvites = await _db
          .collection('note_invites')
          .where('toEmail', isEqualTo: myEmail)
          .where('status', isEqualTo: 'pending')
          .get();

      // 6. Group Invites
      final groupInvites = await _db
          .collection('group_invites')
          .where('toEmail', isEqualTo: myEmail)
          .where('status', isEqualTo: 'pending')
          .get();

      // 7. Group Join Requests (Leader)
      final groupRequests = await _db
          .collection('group_requests')
          .where('leaderId', isEqualTo: currentUid)
          .where('status', isEqualTo: 'pending')
          .get();

      // 8. Reminders & Today's Tasks
      final myNotes = await _db
          .collection('notes')
          .where('userId', isEqualTo: currentUid)
          .get();
      final sharedNotes = await _db
          .collection('notes')
          .where('sharedWith', arrayContains: myEmail)
          .get();
      final assignedNotes = await _db
          .collection('notes')
          .where('assigneeEmails', arrayContains: myEmail)
          .get();

      int todayReminders = 0;
      final seenNoteIds = <String>{};
      for (var doc in [
        ...myNotes.docs,
        ...sharedNotes.docs,
        ...assignedNotes.docs,
      ]) {
        if (seenNoteIds.contains(doc.id)) continue;
        seenNoteIds.add(doc.id);
        final note = noteFromDocument(doc);

        // Note reminder
        if (note.hasReminder && note.reminderTime != null) {
          if (note.reminderTime!.isAfter(startOfToday) &&
              note.reminderTime!.isBefore(endOfToday)) {
            todayReminders++;
          }
        }

        // Todos deadline
        for (var todo in note.todos) {
          if (!todo.isDone && todo.deadline != null) {
            if (todo.deadline!.isAfter(startOfToday) &&
                todo.deadline!.isBefore(endOfToday)) {
              todayReminders++;
            }
          }
        }
      }

      return {
        'unreadMessages': unreadMessages + unreadGroupMessages,
        'friendRequests': friendReqs.docs.length,
        'noteInvites': noteInvites.docs.length,
        'groupInvites': groupInvites.docs.length,
        'groupRequests': groupRequests.docs.length,
        'todayReminders': todayReminders,
      };
    } catch (e) {
      debugPrint("Error fetching re-login summary: $e");
      return {};
    }
  }
}
