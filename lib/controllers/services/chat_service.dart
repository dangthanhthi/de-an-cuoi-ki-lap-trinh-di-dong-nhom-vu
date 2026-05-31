import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../controllers/app_state.dart';
import '../../utils/media_utils.dart';

class ChatService extends BaseService {
  static Future<String> toggleMessageReaction(
    String friendEmail,
    String messageId,
    String emoji,
  ) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, friendEmail);
    
    final messageRef = BaseService.db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    final doc = await messageRef.get();
    if (!doc.exists) return "Tin nhắn không tồn tại";

    final reactions = Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
    
    if (reactions[myEmail] == emoji) {
      reactions.remove(myEmail);
    } else {
      reactions[myEmail] = emoji;
    }

    await messageRef.update({'reactions': reactions});
    return "SUCCESS";
  }

  static Stream<QuerySnapshot> getMessagesStream(String friendEmail) {
    final chatId = chatIdForEmails(AppState.currentUserEmail, friendEmail);
    return BaseService.db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot> getChatListStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return BaseService.db
        .collection('chats')
        .where('participants', arrayContains: myEmail)
        .snapshots();
  }

  static Stream<DocumentSnapshot> getChatStream(String friendEmail) {
    final chatId = chatIdForEmails(AppState.currentUserEmail, friendEmail);
    return BaseService.db.collection('chats').doc(chatId).snapshots();
  }

  static Future<bool> isChatPinned(String friendEmail) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return false;
    final targetEmail = friendEmail.toLowerCase().trim();
    if (targetEmail.isEmpty) return false;

    final chatId = chatIdForEmails(AppState.currentUserEmail, targetEmail);
    final chatDoc = await BaseService.db.collection('chats').doc(chatId).get();
    if (!chatDoc.exists) return false;
    final data = chatDoc.data() ?? <String, dynamic>{};
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return BaseService.normalizeEmailList(data['pinnedBy']).contains(myEmail);
  }

  static String chatIdForEmails(String a, String b) {
    final emails = [a.toLowerCase().trim(), b.toLowerCase().trim()]..sort();
    return "${BaseService.safeDocId(emails[0])}__${BaseService.safeDocId(emails[1])}";
  }

  static Future<void> markMessageAsSeen(String chatId, String messageId) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) return;

    await BaseService.db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'seenBy': FieldValue.arrayUnion([myEmail])
    });

    await BaseService.db.collection('chats').doc(chatId).update({
      FieldPath(['unreadCount', myEmail]): 0,
    });
  }

  static Future<String> sendMessage(
    String friendEmail,
    String text, {
    List<String>? attachments,
    Map<String, dynamic>? replyToData,
  }) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanText = text.trim();
    final cleanAttachments = _cleanAttachments(attachments);
    final targetEmail = friendEmail.toLowerCase().trim();
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    if (targetEmail == myEmail) {
      return "Không thể nhắn tin cho chính mình";
    }

    if (cleanText.isEmpty && cleanAttachments.isEmpty) {
      return "Tin nhắn không được để trống";
    }

    try {
      final chatId = chatIdForEmails(myEmail, targetEmail);
      final chatRef = BaseService.db.collection('chats').doc(chatId);
      final sortedParticipants = [myEmail, targetEmail]..sort();
      await chatRef.set({
        'participants': sortedParticipants,
        'lastMessage': cleanText.isNotEmpty
            ? cleanText
            : _attachmentPreview(cleanAttachments),
        'lastSender': myEmail,
        'lastAttachmentCount': cleanAttachments.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadCount': {targetEmail: FieldValue.increment(1)},
      }, SetOptions(merge: true));

      await chatRef.collection('messages').add({
        'senderEmail': myEmail,
        'senderName': AppState.currentUserName,
        'text': cleanText,
        'attachments': cleanAttachments,
        'createdAt': FieldValue.serverTimestamp(),
        'replyToId': (replyToData?['id'] ?? '').toString(),
        'replyToText': (replyToData?['text'] ?? '').toString(),
        'replyToSender': (replyToData?['senderName'] ?? '').toString(),
        'seenBy': [myEmail],
      });
      return "SUCCESS";
    } catch (e) {
      debugPrint("Send Message Error: $e");
      return "Lỗi khi gửi tin nhắn: ${e.toString()}";
    }
  }

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
    } else if (imageCount > 0) {
      return 'Đã gửi $imageCount ảnh';
    } else {
      return 'Đã gửi $fileCount tệp';
    }
  }

  static Future<String> editMessage(
    String friendEmail,
    String messageId,
    String newText,
  ) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanText = newText.trim();
    if (messageId.isEmpty) return "Không tìm thấy tin nhắn";
    if (cleanText.isEmpty) return "Nội dung không được để trống";

    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, friendEmail);
    final messageRef = BaseService.db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);

    final messageDoc = await messageRef.get();
    if (!messageDoc.exists) return "Tin nhắn không tồn tại";
    if (messageDoc.data()?['senderEmail'] != myEmail) {
      return "Bạn không có quyền sửa tin nhắn này";
    }

    await messageRef.update({
      'text': cleanText,
      'isEdited': true,
      'editedAt': FieldValue.serverTimestamp(),
    });
    await _refreshChatSummary(chatId);
    return "SUCCESS";
  }

  static Future<void> _refreshChatSummary(String chatId) async {
    final chatRef = BaseService.db.collection('chats').doc(chatId);
    final latestMessage = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (latestMessage.docs.isNotEmpty) {
      final data = latestMessage.docs.first.data();
      final text = (data['text'] ?? '').toString();
      final attachments = List<String>.from(data['attachments'] ?? []);
      
      await chatRef.update({
        'lastMessage': text.isNotEmpty ? text : _attachmentPreview(attachments),
        'lastSender': data['senderEmail'],
        'updatedAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<String> toggleChatPin(
    String friendEmail,
    bool shouldPin,
  ) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final targetEmail = friendEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, targetEmail);
    
    await BaseService.db.collection('chats').doc(chatId).set({
      'pinnedBy': shouldPin
          ? FieldValue.arrayUnion([myEmail])
          : FieldValue.arrayRemove([myEmail]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncChatPinnedFlagForContact(targetEmail, shouldPin);
    return "SUCCESS";
  }

  static Future<void> _syncChatPinnedFlagForContact(
    String targetEmail,
    bool shouldPin,
  ) async {
    final contactDocId = await ContactService.getContactDocIdByEmail(targetEmail);
    if (contactDocId.isNotEmpty) {
      await BaseService.db.collection('contacts').doc(contactDocId).update({
        'chatPinned': shouldPin,
      });
    }
  }

  static Future<String> togglePinChatMessage(
    String friendEmail,
    String messageId,
    bool shouldPin,
  ) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final targetEmail = friendEmail.toLowerCase().trim();
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, targetEmail);

    try {
      if (shouldPin) {
        final pinnedCount = await BaseService.db
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('isPinned', isEqualTo: true)
            .get()
            .then((s) => s.docs.length);

        if (pinnedCount >= 3) {
          return "Chỉ được ghim tối đa 3 tin nhắn";
        }
      }

      await BaseService.db
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
            'isPinned': shouldPin,
            'pinnedAt': shouldPin
                ? FieldValue.serverTimestamp()
                : FieldValue.delete(),
          });
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> deleteChatConversation(String friendEmail) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final targetEmail = friendEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, targetEmail);
    
    final chatRef = BaseService.db.collection('chats').doc(chatId);
    final messages = await chatRef.collection('messages').get();
    for (var doc in messages.docs) {
      await doc.reference.delete();
    }
    await chatRef.delete();
    await _syncChatPinnedFlagForContact(targetEmail, false);
    
    FirebaseService.saveActivity(
      "Xóa chat",
      "Đã xóa toàn bộ đoạn chat với $targetEmail",
    );
    return "SUCCESS";
  }

  static Future<void> markChatAsRead(String friendEmail) async {
    if (BaseService.currentUid.isEmpty) return;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatId = chatIdForEmails(myEmail, friendEmail);
    await BaseService.db.collection('chats').doc(chatId).set({
      'unreadCount': {myEmail: 0},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<int> unreadChatMessagesCountStream() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final chatsStream = BaseService.db
        .collection('chats')
        .where('participants', arrayContains: myEmail)
        .snapshots();

    final controller = StreamController<int>();
    Map<String, dynamic> chatUnreads = {};

    void emitTotal() {
      int total = 0;
      chatUnreads.forEach((chatId, countData) {
        if (countData is int) {
          total += countData;
        } else if (countData is Map) {
          total += (countData[myEmail] ?? 0) as int;
        }
      });
      if (!controller.isClosed) controller.add(total);
    }

    final sub1 = chatsStream.listen((s) {
      chatUnreads.clear();
      for (var doc in s.docs) {
        final data = doc.data();
        final unreadData = data['unreadCount'];
        if (unreadData != null) {
          chatUnreads[doc.id] = unreadData[myEmail] ?? 0;
        }
      }
      emitTotal();
    });

    controller.onCancel = () {
      sub1.cancel();
    };

    return controller.stream;
  }
}
