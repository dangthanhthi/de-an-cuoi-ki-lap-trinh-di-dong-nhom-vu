import 'package:cloud_firestore/cloud_firestore.dart';
import '../../controllers/app_state.dart';

class GroupService extends BaseService {
  static Future<String> toggleGroupCommentReaction(
    String groupId,
    String commentId,
    String emoji,
  ) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    
    final commentRef = BaseService.db
        .collection('groups')
        .doc(groupId)
        .collection('comments')
        .doc(commentId);

    final doc = await commentRef.get();
    if (!doc.exists) return "Thảo luận không tồn tại";

    final reactions = Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
    
    if (reactions[myEmail] == emoji) {
      reactions.remove(myEmail);
    } else {
      reactions[myEmail] = emoji;
    }

    await commentRef.update({'reactions': reactions});
    return "SUCCESS";
  }

  static Future<String> addGroupSystemMessage(String groupId, String text) async {
    try {
      await BaseService.db
          .collection('groups')
          .doc(groupId)
          .collection('comments')
          .add({
        'userEmail': 'system',
        'userName': 'Hệ thống',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'isSystem': true,
      });
      return "SUCCESS";
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String> joinGroupByCode(String code) async {
    if (BaseService.currentUid.isEmpty) return "Chưa đăng nhập";
    final cleanCode = code.trim().toUpperCase();
    if (cleanCode.isEmpty) return "Vui lòng nhập mã nhóm";

    try {
      final codeDoc = await BaseService.db.collection('group_codes').doc(cleanCode).get();
      if (!codeDoc.exists) return "Mã nhóm không tồn tại!";

      final groupId = (codeDoc.data()?['groupId'] ?? '').toString().trim();
      final groupDoc = await BaseService.db.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return "Nhóm không tồn tại";

      final data = groupDoc.data() ?? {};
      final myEmail = AppState.currentUserEmail.toLowerCase().trim();
      
      // Need member email extraction logic
      final members = _groupMemberEmails(data);
      if (members.contains(myEmail)) return "Bạn đã ở trong nhóm này rồi!";

      final requiresApproval = data['requiresApproval'] == true;

      if (!requiresApproval) {
        await BaseService.db.collection('groups').doc(groupId).update({
          'members': FieldValue.arrayUnion([myEmail]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await addGroupSystemMessage(groupId, '${AppState.currentUserName} đã tham gia nhóm.');
        return "SUCCESS";
      }

      // Handle approval request...
      return "WAIT_APPROVAL";
    } catch (e) {
      return "Lỗi hệ thống: $e";
    }
  }

  static List<String> _groupMemberEmails(Map<String, dynamic> data) {
    return {
      ...BaseService.normalizeEmailList(data['members']),
      ...BaseService.normalizeEmailList(data['memberEmails']),
    }.toList();
  }
}
