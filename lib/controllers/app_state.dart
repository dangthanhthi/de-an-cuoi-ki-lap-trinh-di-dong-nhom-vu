import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math'; // THÊM THƯ VIỆN NÀY ĐỂ TẠO MÃ NGẪU NHIÊN
import '../models/app_models.dart';

class AppState {
  static String currentUserEmail = "";
  static String currentUserName = "";
  static String currentUserAvatar = "https://ui-avatars.com/api/?background=random";
  static String currentUserRole = "user";

  static List<Note> notes = [];
  static List<Note> allNotes = []; 
  static List<Note> filteredNotes = []; 
  static String searchQuery = ""; 
  static String selectedLabel = "All"; 
  static List<dynamic> activities = [];
  static List<dynamic> contacts = [];
  static List<String> labels = ['Work', 'Personal', 'Study', 'Family'];

  static void clearAllData() {
    currentUserEmail = "";
    currentUserName = "";
    currentUserAvatar = "https://ui-avatars.com/api/?background=random";
    currentUserRole = "user";
    notes.clear();
    allNotes.clear();
    filteredNotes.clear();
    activities.clear();
    contacts.clear();
  }

  static void logActivity(dynamic arg1, [dynamic arg2]) {
    String action = arg1.toString();
    String detail = arg2 != null ? arg2.toString() : "";
    FirebaseService.saveActivity(action, detail);
  }

  static void addActivity(String action) {
    FirebaseService.saveActivity("Hoạt động", action);
  }
}

class FirebaseService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static String get currentUid => _auth.currentUser?.uid ?? "";

  static String currentGroupId = ""; 

  // --- 1. PHẦN HỒ SƠ NGƯỜI DÙNG ---
  static Future<void> updateUserProfile({String? name, String? avatar, String? role}) async {
    if (currentUid.isEmpty) return;
    await _db.collection('users').doc(currentUid).set({
      'name': name ?? AppState.currentUserName,
      'email': AppState.currentUserEmail,
      'avatar': avatar ?? AppState.currentUserAvatar,
      'role': role ?? AppState.currentUserRole,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<DocumentSnapshot> getUserProfileStream() {
    return _db.collection('users').doc(currentUid).snapshots();
  }

  // --- 2. PHẦN LỊCH SỬ HOẠT ĐỘNG ---
  static Future<void> saveActivity(String action, String detail) async {
    if (currentUid.isEmpty) return;
    try {
      await _db.collection('activities').add({
        'userId': currentUid,
        'action': action,
        'detail': detail,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Lỗi lưu lịch sử: $e");
    }
  }

  static Stream<QuerySnapshot> getActivitiesStream() {
    return _db.collection('activities')
        .where('userId', isEqualTo: currentUid)
        .snapshots();
  }

  // --- 3. PHẦN DANH BẠ (HỆ THỐNG LỜI MỜI) ---
  static Future<String> sendFriendRequest(String email) async {
    if (currentUid.isEmpty) return "Lỗi: Chưa đăng nhập";
    
    String targetEmail = email.toLowerCase().trim();
    String myEmail = AppState.currentUserEmail.toLowerCase().trim();

    if (targetEmail == myEmail) return "Không thể tự kết bạn với chính mình!";

    try {
      final userQuery = await _db.collection('users').where('email', isEqualTo: targetEmail).get();
      if (userQuery.docs.isEmpty) return "Tài khoản không tồn tại trên hệ thống!";

      final checkExist = await _db.collection('contacts')
          .where('userId', isEqualTo: currentUid)
          .where('email', isEqualTo: targetEmail)
          .get();
      if (checkExist.docs.isNotEmpty) return "Người này đã có trong danh bạ của bạn rồi!";

      final checkRequest = await _db.collection('friend_requests')
          .where('from', isEqualTo: myEmail)
          .where('to', isEqualTo: targetEmail)
          .get();
      if (checkRequest.docs.isNotEmpty) return "Bạn đã gửi lời mời cho người này rồi, hãy chờ họ phản hồi!";

      final checkReverse = await _db.collection('friend_requests')
          .where('from', isEqualTo: targetEmail)
          .where('to', isEqualTo: myEmail)
          .get();
      if (checkReverse.docs.isNotEmpty) return "Người này đã gửi lời mời cho bạn, hãy kiểm tra danh sách bên trên!";

      await _db.collection('friend_requests').add({
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
    return _db.collection('friend_requests')
        .where('to', isEqualTo: myEmail)
        .snapshots();
  }

  static Future<void> acceptFriendRequest(String requestId, Map<String, dynamic> requestData) async {
    await _db.collection('contacts').add({
      'userId': currentUid,
      'email': requestData['from'],
      'name': requestData['fromName'],
      'avatar': requestData['fromAvatar'],
      'addedAt': FieldValue.serverTimestamp(),
    });

    final otherUserQuery = await _db.collection('users').where('email', isEqualTo: requestData['from']).get();
    if (otherUserQuery.docs.isNotEmpty) {
      String otherUid = otherUserQuery.docs.first.id;
      await _db.collection('contacts').add({
        'userId': otherUid,
        'email': AppState.currentUserEmail,
        'name': AppState.currentUserName,
        'avatar': AppState.currentUserAvatar,
        'addedAt': FieldValue.serverTimestamp(),
      });
    }
    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Future<void> rejectFriendRequest(String requestId) async {
    await _db.collection('friend_requests').doc(requestId).delete();
  }

  static Stream<QuerySnapshot> getContactsStream() {
    return _db.collection('contacts')
        .where('userId', isEqualTo: currentUid)
        .snapshots();
  }

  // --- 4. PHẦN GHI CHÚ ---
  static Future<void> addNote(Note note) async {
    if (currentUid.isEmpty) return;
    await _db.collection('notes').add({
      'title': note.title,
      'content': note.content,
      'label': note.label,
      'userId': currentUid,
      'date': DateTime.now().toIso8601String(),
      'isTodo': note.isTodo,
      'todos': note.todos.map((t) => {'task': t.task, 'isDone': t.isDone}).toList(),
      'sharedWith': [], 
      'color': note.coverColor.value,
      'groupId': currentGroupId, 
    });
    await saveActivity("Thêm ghi chú", "Đã thêm: ${note.title}");
  }

  static Future<void> updateNote(String noteId, Note note) async {
    if (currentUid.isEmpty || noteId.isEmpty) return;
    try {
      await _db.collection('notes').doc(noteId).update({
        'title': note.title,
        'content': note.content,
        'label': note.label,
        'isTodo': note.isTodo,
        'todos': note.todos.map((t) => {'task': t.task, 'isDone': t.isDone}).toList(),
        'color': note.coverColor.value,
      });
    } catch (e) {
      print("Lỗi cập nhật màu: $e");
    }
  }

  static Future<void> shareNote(String noteId, String targetEmail) async {
    if (noteId.isEmpty || targetEmail.isEmpty) return;
    await _db.collection('notes').doc(noteId).update({
      'sharedWith': FieldValue.arrayUnion([targetEmail.toLowerCase()])
    });
    await saveActivity("Chia sẻ ghi chú", "Đã chia sẻ cho $targetEmail");
  }

  static Stream<QuerySnapshot> getMyNotesStream() {
    return _db.collection('notes')
        .where('userId', isEqualTo: currentUid)
        .snapshots();
  }

  static Stream<QuerySnapshot> getSharedNotesStream() {
    String safeEmail = AppState.currentUserEmail.toLowerCase().trim();
    return _db.collection('notes')
        .where('sharedWith', arrayContains: safeEmail)
        .snapshots();
  }

  // --- 5. PHẦN ADMIN: QUẢN LÝ TÀI KHOẢN ---
  static Stream<QuerySnapshot> getAllUsersStream() {
    return _db.collection('users').snapshots();
  }

  static Future<void> toggleUserBan(String targetUid, bool currentBanStatus) async {
    if (currentUid.isEmpty) return;
    try {
      await _db.collection('users').doc(targetUid).update({
        'isBanned': !currentBanStatus, 
      });
    } catch (e) {
      print("Lỗi khi khóa/mở khóa tài khoản: $e");
    }
  }

  // --- 6. PHẦN NHÓM (GROUPS) ĐÃ ĐƯỢC NÂNG CẤP MÃ NHÓM ---
  
  // Hàm tạo mã nhóm ngẫu nhiên 8 ký tự in hoa và số
  static String generateGroupCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    return String.fromCharCodes(Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  // Tạo nhóm mới (Có sinh thêm mã code)
  static Future<void> createGroup(String groupName) async {
    if (currentUid.isEmpty) return;
    String code = generateGroupCode();
    await _db.collection('groups').add({
      'name': groupName,
      'leaderId': currentUid,
      'members': [AppState.currentUserEmail.toLowerCase()], 
      'groupCode': code, // LƯU MÃ NHÓM VÀO ĐÂY
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Tham gia nhóm bằng Mã (Tự động chuyển mã thành chữ in hoa để so sánh)
  static Future<String> joinGroupByCode(String code) async {
    if (currentUid.isEmpty) return "Chưa đăng nhập";
    
    try {
      // Tìm nhóm có mã này
      var query = await _db.collection('groups').where('groupCode', isEqualTo: code.toUpperCase().trim()).get();
      
      if (query.docs.isEmpty) {
        return "Mã nhóm không tồn tại! Vui lòng kiểm tra lại.";
      }
      
      var groupDoc = query.docs.first;
      List<dynamic> members = groupDoc['members'] ?? [];
      String myEmail = AppState.currentUserEmail.toLowerCase();

      if (members.contains(myEmail)) {
        return "Bạn đã ở trong nhóm này rồi!";
      }

      // Thêm email mình vào nhóm
      await _db.collection('groups').doc(groupDoc.id).update({
        'members': FieldValue.arrayUnion([myEmail])
      });
      
      return "SUCCESS";
    } catch (e) {
      return "Lỗi hệ thống: $e";
    }
  }

  static Stream<QuerySnapshot> getMyGroupsStream() {
    return _db.collection('groups')
        .where('members', arrayContains: AppState.currentUserEmail.toLowerCase())
        .snapshots();
  }

  static Future<void> addMemberToGroup(String groupId, String memberEmail) async {
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayUnion([memberEmail.toLowerCase()])
    });
  }

  static Future<void> removeMemberFromGroup(String groupId, String memberEmail) async {
    await _db.collection('groups').doc(groupId).update({
      'members': FieldValue.arrayRemove([memberEmail.toLowerCase()])
    });
  }

  static Future<void> deleteGroup(String groupId) async {
    await _db.collection('groups').doc(groupId).delete();
    var notes = await _db.collection('notes').where('groupId', isEqualTo: groupId).get();
    for (var doc in notes.docs) {
      await doc.reference.delete();
    }
  }

  static Stream<QuerySnapshot> getGroupNotesStream(String groupId) {
    return _db.collection('notes')
        .where('groupId', isEqualTo: groupId)
        .snapshots();
  }
}