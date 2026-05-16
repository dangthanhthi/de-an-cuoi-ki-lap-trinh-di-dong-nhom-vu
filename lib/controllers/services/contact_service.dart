import 'package:cloud_firestore/cloud_firestore.dart';
import '../../controllers/app_state.dart';

class ContactService extends BaseService {
  static Future<String> sendFriendRequest(String email) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return "Lỗi: Chưa đăng nhập";

    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) {
      return "Lỗi: Không tìm thấy email của bạn. Hãy thử đăng nhập lại.";
    }

    String targetEmail = email.toLowerCase().trim();
    if (targetEmail == myEmail) return "Không thể tự kết bạn với chính mình!";

    try {
      final userQuery = await BaseService.db
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .get();
      if (userQuery.docs.isEmpty) {
        return "Tài khoản không tồn tại trên hệ thống!";
      }

      final checkExist = await BaseService.db
          .collection('contacts')
          .where('userId', isEqualTo: uid)
          .where('email', isEqualTo: targetEmail)
          .get();
      if (checkExist.docs.isNotEmpty) {
        return "Người này đã có trong danh bạ của bạn rồi!";
      }

      final checkRequest = await BaseService.db
          .collection('friend_requests')
          .where('from', isEqualTo: myEmail)
          .where('to', isEqualTo: targetEmail)
          .get();
      if (checkRequest.docs.isNotEmpty) {
        return "Bạn đã gửi lời mời cho người này rồi, hãy chờ họ phản hồi!";
      }

      await BaseService.db.collection('friend_requests').add({
        'from': myEmail,
        'to': targetEmail,
        'fromName': AppState.currentUserName,
        'fromAvatar': AppState.currentUserAvatar,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi hệ thống: $e";
    }
  }

  static Stream<QuerySnapshot> getFriendRequestsStream() {
    String myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return BaseService.db
        .collection('friend_requests')
        .where('to', isEqualTo: myEmail)
        .snapshots();
  }

  static Future<String> rejectFriendRequest(String requestId) async {
    await BaseService.db.collection('friend_requests').doc(requestId).delete();
    return "SUCCESS";
  }

  static Stream<QuerySnapshot> getContactsStream() {
    return BaseService.db
        .collection('contacts')
        .where('userId', isEqualTo: BaseService.currentUid)
        .snapshots();
  }

  static Future<String> acceptFriendRequest(
    String requestId,
    Map<String, dynamic> requestData,
  ) async {
    try {
      final uid = BaseService.currentUid;
      final fromEmail = (requestData['from'] ?? '').toString().toLowerCase().trim();
      if (uid.isEmpty || fromEmail.isEmpty) return "Lỗi dữ liệu";

      await ensureContactExists(
        userId: uid,
        email: fromEmail,
        name: (requestData['fromName'] ?? 'Bạn bè').toString(),
        avatar: (requestData['fromAvatar'] ?? '').toString(),
      );

      final otherUserQuery = await BaseService.db
          .collection('users')
          .where('email', isEqualTo: fromEmail)
          .get();
      if (otherUserQuery.docs.isNotEmpty) {
        final otherUid = otherUserQuery.docs.first.id;
        await ensureContactExists(
          userId: otherUid,
          email: AppState.currentUserEmail,
          name: AppState.currentUserName,
          avatar: AppState.currentUserAvatar,
        );
      }

      await BaseService.db.collection('friend_requests').doc(requestId).delete();
      return "SUCCESS";
    } catch (e) {
      return "Lỗi khi chấp nhận kết bạn: $e";
    }
  }

  static Future<void> ensureContactExists({
    required String userId,
    required String email,
    required String name,
    required String avatar,
  }) async {
    final existing = await BaseService.db
        .collection('contacts')
        .where('userId', isEqualTo: userId)
        .where('email', isEqualTo: email.toLowerCase().trim())
        .get();
    if (existing.docs.isEmpty) {
      await BaseService.db.collection('contacts').add({
        'userId': userId,
        'email': email.toLowerCase().trim(),
        'name': name,
        'avatar': avatar,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<String> removeContact(String contactDocId, String contactEmail) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return "Lỗi: Chưa đăng nhập";

    try {
      if (contactDocId.isNotEmpty) {
        await BaseService.db.collection('contacts').doc(contactDocId).delete();
      }
      await ActivityService.saveActivity("Xóa bạn bè", "Đã hủy kết bạn với $contactEmail");
      return "SUCCESS";
    } catch (e) {
      return "Lỗi hệ thống: $e";
    }
  }

  static Future<String> updateContactName(String contactId, String newName) async {
    try {
      await BaseService.db.collection('contacts').doc(contactId).update({
        'name': newName,
      });
      return "SUCCESS";
    } catch (e) {
      return "Lỗi: $e";
    }
  }

  static Future<String> getContactDocIdByEmail(String email) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return "";
    final query = await BaseService.db
        .collection('contacts')
        .where('userId', isEqualTo: uid)
        .where('email', isEqualTo: email.toLowerCase().trim())
        .limit(1)
        .get();
    if (query.docs.isEmpty) return "";
    return query.docs.first.id;
  }

  static Future<String> checkFriendshipStatus(String email) async {
    final uid = BaseService.currentUid;
    if (uid.isEmpty) return "NONE";
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final targetEmail = email.toLowerCase().trim();

    final contactCheck = await BaseService.db
        .collection('contacts')
        .where('userId', isEqualTo: uid)
        .where('email', isEqualTo: targetEmail)
        .get();
    if (contactCheck.docs.isNotEmpty) return "FRIEND";

    final sentRequest = await BaseService.db
        .collection('friend_requests')
        .where('from', isEqualTo: myEmail)
        .where('to', isEqualTo: targetEmail)
        .get();
    if (sentRequest.docs.isNotEmpty) return "SENT";

    final receivedRequest = await BaseService.db
        .collection('friend_requests')
        .where('from', isEqualTo: targetEmail)
        .where('to', isEqualTo: myEmail)
        .get();
    if (receivedRequest.docs.isNotEmpty) return "RECEIVED";

    return "NONE";
  }
}
