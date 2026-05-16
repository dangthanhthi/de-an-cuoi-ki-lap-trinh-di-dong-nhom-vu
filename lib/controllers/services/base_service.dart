import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/app_models.dart';
import '../firebase_service.dart';
import '../notification_service.dart';

abstract class BaseService {
  static final FirebaseFirestore db = FirebaseFirestore.instance;
  static final FirebaseStorage storage = FirebaseStorage.instanceFor(
    bucket: 'snote-e8384.firebasestorage.app',
  );
  static final FirebaseAuth auth = FirebaseAuth.instance;

  static String get currentUid => auth.currentUser?.uid ?? "";

  static String safeDocId(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9._-]'), '_');
  }

  static DateTime? readDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static List<String> normalizeEmailList(dynamic rawValue) {
    if (rawValue is! List) return <String>[];
    return rawValue
        .map((item) => item.toString().toLowerCase().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<String> normalizeStringList(dynamic rawValue) {
    if (rawValue is! List) return <String>[];
    return rawValue
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic> notePayload(Note note, {String? groupId}) {
    final assigneeEmails = note.todos
        .map((t) => t.assigneeEmail.toLowerCase().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    return {
      'title': note.title,
      'content': note.content,
      'titleTextColor': note.titleTextColor,
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
      'sharedWith': normalizeEmailList(note.sharedWith),
      'color': note.coverColor.toARGB32(),
      'groupId': groupId ?? note.groupId,
      'groupName': note.groupName,
      'createdByEmail': note.createdByEmail,
      'createdByName': note.createdByName,
      'isPinned': note.isPinned,
      'priority': NotePriority.normalize(note.priority),
      'hasReminder': note.hasReminder,
      'reminderTime': note.reminderTime?.toIso8601String(),
      'attachments': normalizeStringList(note.attachments),
      'isRichText': note.isRichText,
    };
  }

  static Future<void> deleteStoredAttachments(Iterable<String> attachments) async {
    for (final attachment in attachments) {
      await FirebaseService.deleteAttachment(attachment);
    }
  }

  static Future<void> deleteRemovedAttachments({
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
    await deleteStoredAttachments(removed);
  }

  static Future<void> deleteCollectionDocs(CollectionReference collection) async {
    final snapshot = await collection.get();
    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  static Future<void> deleteNoteRecord(
    DocumentReference<Map<String, dynamic>> noteRef,
    Map<String, dynamic> noteData,
  ) async {
    final attachments = List<String>.from(noteData['attachments'] ?? const []);
    await NotificationService.cancelNoteReminder(noteRef.id);
    await deleteStoredAttachments(attachments);
    await deleteCollectionDocs(noteRef.collection('comments'));
    await deleteCollectionDocs(noteRef.collection('history'));
    await noteRef.delete();
  }
}
