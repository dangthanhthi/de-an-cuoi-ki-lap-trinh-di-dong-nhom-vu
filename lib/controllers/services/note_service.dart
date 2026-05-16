import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../controllers/app_state.dart';
import '../../models/app_models.dart';
import '../../controllers/notification_service.dart';

class NoteService extends BaseService {
  static Future<String> addNote(Note note) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final groupId = note.groupId.trim();
    
    final todosForWrite = groupId.isEmpty
        ? _personalTodos(note.todos)
        : note.todos;

    final docRef = BaseService.db.collection('notes').doc();
    final payload = BaseService.notePayload(note.copyWith(todos: todosForWrite), groupId: groupId);
    payload['userId'] = BaseService.currentUid;
    payload['createdAt'] = FieldValue.serverTimestamp();
    payload['updatedAt'] = FieldValue.serverTimestamp();
    
    await docRef.set(payload);
    FirebaseService.saveActivity(
      "Tạo ghi chú", 
      "Đã tạo ghi chú: ${note.title}", 
      groupId: groupId
    );
    
    if (note.hasReminder && note.reminderTime != null) {
      await NotificationService.scheduleNoteReminder(docRef.id, note);
    }
    
    return "SUCCESS";
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

  static Future<String> updateNote(Note note) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    if (note.id.isEmpty) return "Không tìm thấy ghi chú";

    final docRef = BaseService.db.collection('notes').doc(note.id);
    final oldDoc = await docRef.get();
    if (!oldDoc.exists) return "Ghi chú không tồn tại";

    final oldData = oldDoc.data()!;
    final groupId = note.groupId.trim();
    
    final payload = BaseService.notePayload(note, groupId: groupId);
    payload['updatedAt'] = FieldValue.serverTimestamp();

    await docRef.update(payload);
    
    // Clean up attachments if needed
    final oldAttachments = List<String>.from(oldData['attachments'] ?? []);
    final newAttachments = note.attachments;
    await BaseService.deleteRemovedAttachments(
      previous: oldAttachments, 
      next: newAttachments
    );

    FirebaseService.saveActivity(
      "Sửa ghi chú", 
      "Đã cập nhật ghi chú: ${note.title}", 
      groupId: groupId
    );

    if (note.hasReminder && note.reminderTime != null) {
      await NotificationService.scheduleNoteReminder(note.id, note);
    } else {
      await NotificationService.cancelNoteReminder(note.id);
    }

    return "SUCCESS";
  }

  static Future<void> deleteNote(String noteId) async {
    if (BaseService.currentUid.isEmpty || noteId.isEmpty) return;
    final docRef = BaseService.db.collection('notes').doc(noteId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;
    final title = (data['title'] ?? 'Ghi chú').toString();
    final groupId = (data['groupId'] ?? '').toString();

    await BaseService.deleteNoteRecord(docRef, data);
    FirebaseService.saveActivity(
      "Xóa ghi chú", 
      "Đã xóa ghi chú: $title", 
      groupId: groupId
    );
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
      titleIsStrikethrough: data['titleIsStrikethrough'] == true,
      contentTextColor: (data['contentTextColor'] ?? '').toString(),
      contentIsBold: data['contentIsBold'] == true,
      contentIsItalic: data['contentIsItalic'] == true,
      contentIsUnderlined: data['contentIsUnderlined'] == true,
      contentIsStrikethrough: data['contentIsStrikethrough'] == true,
      label: (data['label'] ?? AppState.labels.first).toString(),
      date: dateText,
      isPinned: data['isPinned'] == true,
      isArchived: data['isArchived'] == true,
      isLocked: data['isLocked'] == true,
      isShared: data['isShared'] == true,
      isHidden: data['isHidden'] == true,
      isFavorite: data['isFavorite'] == true,
      isChecklist: data['isChecklist'] == true,
      backgroundColor: data['backgroundColor'] as int?,
      coverColor: data['color'] != null
          ? Color(data['color'] as int)
          : (data['backgroundColor'] != null
              ? Color(data['backgroundColor'] as int)
              : Colors.blue.shade100),
      todos: _readTodos(data['todos']),
      attachments: List<String>.from(data['attachments'] ?? []),
      userId: (data['userId'] ?? '').toString(),
      groupId: (data['groupId'] ?? '').toString(),
      sharedWith: List<String>.from(data['sharedWith'] ?? []),
      assignedTo: List<String>.from(data['assignedTo'] ?? []),
      hasReminder: data['hasReminder'] == true,
      reminderTime: (data['reminderTime'] as Timestamp?)?.toDate(),
      lastViewedAt: (data['lastViewedAt'] as Timestamp?)?.toDate(),
      viewCount: (data['viewCount'] ?? 0) as int,
      status: TodoStatus.normalize((data['status'] ?? '').toString()),
    );
  }

  static List<TodoItem> _readTodos(dynamic value) {
    if (value is! List) return <TodoItem>[];
    return value
        .whereType<dynamic>()
        .map((item) => TodoItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Stream<QuerySnapshot> getNoteInvitesStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return BaseService.db
        .collection('note_invites')
        .where('targetEmail', isEqualTo: myEmail)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  static Future<String> shareNote(String noteId, String targetEmail) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanEmail = targetEmail.toLowerCase().trim();
    if (cleanEmail == AppState.currentUserEmail.toLowerCase().trim()) {
      return "Không thể chia sẻ cho chính mình";
    }

    try {
      final noteDoc = await BaseService.db.collection('notes').doc(noteId).get();
      if (!noteDoc.exists) return "Ghi chú không tồn tại";

      final data = noteDoc.data()!;
      final existing = await BaseService.db
          .collection('note_invites')
          .where('noteId', isEqualTo: noteId)
          .where('targetEmail', isEqualTo: cleanEmail)
          .where('status', isEqualTo: 'pending')
          .get();

      if (existing.docs.isNotEmpty) return "Đã gửi lời mời cho người này rồi";

      await BaseService.db.collection('note_invites').add({
        'noteId': noteId,
        'noteTitle': data['title'] ?? 'Ghi chú không tiêu đề',
        'senderEmail': AppState.currentUserEmail,
        'senderName': AppState.currentUserName,
        'targetEmail': cleanEmail,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi chia sẻ: $e";
    }
  }

  static Future<String> respondToNoteInvite(String inviteId, bool accept) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    try {
      final inviteRef = BaseService.db.collection('note_invites').doc(inviteId);
      final inviteDoc = await inviteRef.get();
      if (!inviteDoc.exists) return "Lời mời không tồn tại";

      final data = inviteDoc.data()!;
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();

      if (accept) {
        final noteId = data['noteId'];
        await BaseService.db.collection('notes').doc(noteId).update({
          'sharedWith': FieldValue.arrayUnion([myEmail]),
          'isShared': true,
        });
        await inviteRef.update({'status': 'accepted'});
        return "SUCCESS";
      } else {
        await inviteRef.update({'status': 'rejected'});
        return "SUCCESS";
      }
    } catch (e) {
      return "Lỗi phản hồi: $e";
    }
  }

  static Future<void> toggleNotePin(String noteId, bool shouldPin) async {
    await BaseService.db.collection('notes').doc(noteId).update({
      'isPinned': shouldPin,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> markNoteAsViewed(String noteId) async {
    if (BaseService.currentUid.isEmpty) return;
    await BaseService.db.collection('notes').doc(noteId).update({
      'lastViewedAt': FieldValue.serverTimestamp(),
      'viewCount': FieldValue.increment(1),
    });
  }

  static Stream<int> unreadSharedNotesCountStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    
    final sharedStream = BaseService.db
        .collection('notes')
        .where('sharedWith', arrayContains: myEmail)
        .snapshots();

    final controller = StreamController<int>.broadcast();
    
    final sub = sharedStream.listen((snapshot) {
      int count = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final viewedBy = List<String>.from(data['viewedBy'] ?? []);
        if (!viewedBy.contains(myEmail)) {
          count++;
        }
      }
      controller.add(count);
    });

    controller.onCancel = () {
      sub.cancel();
    };

    return controller.stream;
  }

  static Future<String> updateNoteStatus(String noteId, String newStatus) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    if (noteId.isEmpty) return "Không tìm thấy ghi chú";

    try {
      final status = TodoStatus.normalize(newStatus);
      await BaseService.db.collection('notes').doc(noteId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi cập nhật trạng thái: $e";
    }
  }
}
