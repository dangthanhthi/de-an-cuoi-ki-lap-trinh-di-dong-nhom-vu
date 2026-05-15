import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _searchQuery = '';

  void _showMessage(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  bool _isMuteActive(Map<String, dynamic> data) {
    final muteUntil = data['muteUntil'];
    if (muteUntil is! Timestamp) return true;
    return muteUntil.toDate().isAfter(DateTime.now());
  }

  Set<String> _activeMutedUsers(List<QueryDocumentSnapshot> docs) {
    return docs
        .where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['type'] == 'user' && _isMuteActive(data);
        })
        .map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['targetId'] ?? '').toString().toLowerCase().trim();
        })
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> _showAddFriendDialog() async {
    final emailCtrl = TextEditingController();
    
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          bool isAdding = false;
          return StatefulBuilder(
            builder: (builderContext, setDialogState) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Text('Gửi lời mời kết bạn'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Nhập email của người bạn muốn thêm:'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'ví dụ: abc@gmail.com',
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isAdding ? null : () => Navigator.pop(ctx),
                    child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                  ),
                  FilledButton(
                    onPressed: isAdding
                        ? null
                        : () async {
                            final targetEmail = emailCtrl.text.trim().toLowerCase();
                            if (targetEmail.isEmpty) return;

                            final myEmail = AppState.currentUserEmail.toLowerCase().trim();
                            if (targetEmail == myEmail) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Không thể tự kết bạn với chính mình!"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            
                            setDialogState(() => isAdding = true);

                            try {
                              final result = await FirebaseService.sendFriendRequest(targetEmail);

                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                              }
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result == "SUCCESS"
                                          ? "Đã gửi lời mời thành công! Chờ người kia đồng ý nhé."
                                          : result,
                                    ),
                                    backgroundColor: result == "SUCCESS"
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                setDialogState(() => isAdding = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Lỗi hệ thống: $e"),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                    child: isAdding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Gửi lời mời'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailCtrl.dispose();
    }
  }

  Future<void> _showEditContactDialog(
    String contactId,
    String currentName,
  ) async {
    final nameCtrl = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSaving || formKey.currentState?.validate() != true) return;
              setSheetState(() => isSaving = true);

              final newName = nameCtrl.text.trim();
              final result = await FirebaseService.updateContactName(
                contactId,
                newName,
              );

              if (!sheetContext.mounted) return;
              setSheetState(() => isSaving = false);

              if (result == "SUCCESS") {
                if (Navigator.of(sheetContext).canPop()) {
                  Navigator.of(sheetContext).pop();
                }
                _showMessage("Đã cập nhật tên gợi nhớ cho bạn bè");
              } else {
                _showMessage(result, success: false);
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Đổi tên gợi nhớ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tên này sẽ chỉ hiển thị với bạn để dễ dàng nhận diện.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nameCtrl,
                        autofocus: true,
                        enabled: !isSaving,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Tên liên hệ',
                          prefixIcon: Icon(Icons.edit_note_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Tên không được để trống';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSaving ? null : submit,
                          child: Text(
                            isSaving ? 'Đang lưu...' : 'Lưu thay đổi',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
    });
  }

  Future<void> _confirmRemoveContact(String contactId, String email) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy kết bạn?'),
        content: Text('Bạn có chắc muốn xóa $email khỏi danh bạ không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !mounted) return;

    final scaffoldMsg = ScaffoldMessenger.of(context);
    final result = await FirebaseService.removeContact(contactId, email);
    if (!mounted) return;

    scaffoldMsg.showSnackBar(
      SnackBar(
        content: Text(result == "SUCCESS" ? "Đã hủy kết bạn" : result),
        backgroundColor: result == "SUCCESS" ? Colors.green : Colors.red,
      ),
    );
  }
  Future<void> _showContactQuickActions(
    String contactId,
    String name,
    String email,
    String avatar,
    bool isPinned,
    bool isMuted,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: avatarImageProvider(avatar, name: name),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(email, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: isPinned ? Colors.blue : null,
              ),
              title: Text(isPinned ? 'Bỏ ghim trò chuyện' : 'Ghim trò chuyện'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseService.toggleChatPin(email, !isPinned);
                _showMessage(isPinned ? 'Đã bỏ ghim' : 'Đã ghim trò chuyện');
              },
            ),
            ListTile(
              leading: Icon(
                isMuted ? Icons.volume_up_outlined : Icons.notifications_off_outlined,
                color: Colors.orange,
              ),
              title: Text(isMuted ? 'Mở lại thông báo' : 'Tắt thông báo'),
              onTap: () async {
                Navigator.pop(sheetContext);
                if (isMuted) {
                  await FirebaseService.unmuteTarget(type: 'user', targetId: email);
                  _showMessage('Đã mở lại thông báo');
                } else {
                  await FirebaseService.muteTarget(
                    type: 'user',
                    targetId: email,
                    label: name,
                  );
                  _showMessage('Đã tắt thông báo');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Sửa tên hiển thị'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditContactDialog(contactId, name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined, color: Colors.red),
              title: const Text('Hủy kết bạn'),
              textColor: Colors.red,
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hủy kết bạn?'),
                    content: Text('Bạn có chắc muốn hủy kết bạn với "$name" không?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đồng ý', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  final res = await FirebaseService.removeContact(contactId, email);
                  _showMessage(res == 'SUCCESS' ? 'Thành công' : res);
                }
              },
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Danh bạ của tôi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Lời mời kết bạn.
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getFriendRequestsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const SizedBox();
              }

              final requests = snapshot.data!.docs;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'Lời mời kết bạn (${requests.length})',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      var reqData =
                          requests[index].data() as Map<String, dynamic>;
                      String reqId = requests[index].id;

                      return ListTile(
                        tileColor: Colors.orange.shade50.withValues(alpha: 0.5),
                        leading: CircleAvatar(
                          backgroundImage: avatarImageProvider(
                            reqData['fromAvatar']?.toString(),
                            name: reqData['fromName']?.toString(),
                          ),
                        ),
                        title: Text(
                          reqData['fromName'] ?? 'Người lạ',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(reqData['from']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 30,
                              ),
                              onPressed: () =>
                                  FirebaseService.acceptFriendRequest(
                                    reqId,
                                    reqData,
                                  ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.cancel,
                                color: Colors.redAccent,
                                size: 30,
                              ),
                              onPressed: () =>
                                  FirebaseService.rejectFriendRequest(reqId),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, thickness: 1),
                ],
              );
            },
          ),

          // Danh bạ chính.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm bạn bè...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getContactsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 80,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Danh bạ trống',
                          style: TextStyle(
                            fontSize: 18,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          'Nhấn dấu + để tìm bạn bè nhé!',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                final query = _searchQuery.toLowerCase().trim();
                final contacts = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return query.isEmpty ||
                      name.contains(query) ||
                      email.contains(query);
                }).toList();

                if (contacts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Không tìm thấy bạn bè phù hợp',
                          style: TextStyle(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseService.getMyMutesStream(),
                  builder: (context, muteSnapshot) {
                    final mutedUsers = _activeMutedUsers(
                      muteSnapshot.data?.docs ?? [],
                    );

                    return ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact =
                            contacts[index].data() as Map<String, dynamic>;
                        final docId = contacts[index].id;
                        final name = contact['name'] ?? 'Không tên';
                        final email = (contact['email'] ?? '').toString();
                        final isMuted = mutedUsers.contains(
                          email.toLowerCase().trim(),
                        );

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundImage: avatarImageProvider(
                                  contact['avatar']?.toString(),
                                  name: name.toString(),
                                ),
                              ),
                              StreamBuilder<DocumentSnapshot?>(
                                stream: FirebaseService.getUserByEmailStream(email),
                                builder: (context, userSnap) {
                                  if (!userSnap.hasData || userSnap.data == null) return const SizedBox();
                                  final userData = userSnap.data!.data() as Map<String, dynamic>?;
                                  final lastActive = userData?['lastActive'] as Timestamp?;
                                  final isOnline = (userData?['isOnline'] == true) &&
                                      lastActive != null &&
                                      DateTime.now().difference(lastActive.toDate()).inMinutes < 5;
                                  if (!isOnline) return const SizedBox();
                                  return Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: colorScheme.surface, width: 2),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              StreamBuilder<DocumentSnapshot?>(
                                stream: FirebaseService.getUserByEmailStream(email),
                                builder: (context, userSnap) {
                                  if (!userSnap.hasData || userSnap.data == null) return const SizedBox();
                                  final userData = userSnap.data!.data() as Map<String, dynamic>?;
                                  final lastActive = userData?['lastActive'] as Timestamp?;
                                  final isOnline = (userData?['isOnline'] == true) &&
                                      lastActive != null &&
                                      DateTime.now().difference(lastActive.toDate()).inMinutes < 5;
                                  if (lastActive == null) return const SizedBox();
                                  return Text(
                                    _buildOnlineStatusText(lastActive, isOnline: isOnline),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isOnline ? Colors.green : colorScheme.onSurfaceVariant,
                                      fontWeight: isOnline ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(email),
                              if (isMuted)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'Đang tắt thông báo',
                                      style: TextStyle(
                                        color: colorScheme.onPrimaryContainer,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Nhắn tin',
                                icon: const Icon(
                                  Icons.chat_bubble_outline,
                                  color: Colors.green,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChatScreen(
                                      friendName: name.toString(),
                                      friendEmail: email,
                                      friendAvatar:
                                          contact['avatar']?.toString() ?? '',
                                    ),
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') {
                                    _showEditContactDialog(docId, name);
                                    return;
                                  }
                                  if (value == 'remove') {
                                    _confirmRemoveContact(docId, email);
                                    return;
                                  }
                                  if (value == 'mute_1h') {
                                    await FirebaseService.muteTarget(
                                      type: 'user',
                                      targetId: email,
                                      label: name.toString(),
                                      duration: const Duration(hours: 1),
                                    );
                                    _showMessage('Đã tắt thông báo 1 giờ');
                                    return;
                                  }
                                  if (value == 'mute_forever') {
                                    await FirebaseService.muteTarget(
                                      type: 'user',
                                      targetId: email,
                                      label: name.toString(),
                                    );
                                    _showMessage(
                                      'Đã tắt thông báo cho đến khi mở lại',
                                    );
                                    return;
                                  }
                                  if (value == 'unmute') {
                                    await FirebaseService.unmuteTarget(
                                      type: 'user',
                                      targetId: email,
                                    );
                                    _showMessage('Đã mở lại thông báo');
                                    return;
                                  }
                                  if (value == 'block') {
                                    final result =
                                        await FirebaseService.blockUser(email);
                                    _showMessage(
                                      result == 'SUCCESS'
                                          ? 'Đã chặn $email'
                                          : result,
                                      success: result == 'SUCCESS',
                                    );
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Sửa tên hiển thị'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Hủy kết bạn'),
                                  ),
                                  const PopupMenuDivider(),
                                  if (!isMuted)
                                    const PopupMenuItem(
                                      value: 'mute_1h',
                                      child: Text('Tắt báo 1 giờ'),
                                    ),
                                  if (!isMuted)
                                    const PopupMenuItem(
                                      value: 'mute_forever',
                                      child: Text('Tắt báo đến khi mở lại'),
                                    ),
                                  if (isMuted)
                                    const PopupMenuItem(
                                      value: 'unmute',
                                      child: Text('Mở lại thông báo'),
                                    ),
                                  const PopupMenuDivider(),
                                  const PopupMenuItem(
                                    value: 'block',
                                    child: Text('Chặn người này'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            _showContactQuickActions(
                              docId,
                              name.toString(),
                              email,
                              contact['avatar']?.toString() ?? '',
                              contact['chatPinned'] == true,
                              isMuted,
                            );
                          },
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                friendName: name.toString(),
                                friendEmail: email,
                                friendAvatar:
                                    contact['avatar']?.toString() ?? '',
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFriendDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Thêm bạn'),
      ),
    );
  }

  String _buildOnlineStatusText(Timestamp? lastActive, {bool isOnline = false}) {
    if (lastActive == null) return '';
    final lastSeen = lastActive.toDate();
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (isOnline && diff.inMinutes < 5) return 'Đang hoạt động';
    if (diff.inMinutes < 1) return 'Vừa mới truy cập';
    if (diff.inMinutes < 60) return 'Truy cập ${diff.inMinutes} phút trước';
    if (diff.inHours < 24) {
      if (lastSeen.day == now.day) {
        return 'Truy cập ${diff.inHours} giờ trước';
      }
      return 'Truy cập hôm qua';
    }
    if (diff.inDays == 1) return 'Truy cập hôm qua';
    if (diff.inDays < 7) return 'Truy cập ${diff.inDays} ngày trước';
    return 'Truy cập ngày ${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }
}




