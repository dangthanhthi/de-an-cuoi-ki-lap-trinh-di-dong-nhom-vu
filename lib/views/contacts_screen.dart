import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_image_viewer/easy_image_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import '../utils/snack_utils.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  late Stream<QuerySnapshot> _friendRequestsStream;
  late Stream<QuerySnapshot> _chatListStream;
  late Stream<QuerySnapshot> _contactsStream;
  late Stream<QuerySnapshot> _myMutesStream;

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _friendRequestsStream = FirebaseService.getFriendRequestsStream();
    _chatListStream = FirebaseService.getChatListStream();
    _contactsStream = FirebaseService.getContactsStream();
    _myMutesStream = FirebaseService.getMyMutesStream();
  }

  void _showMessage(String message, {bool success = true}) {
    if (!mounted) return;
    SnackUtils.show(context, message, success: success);
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
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _AddFriendDialog(),
    );

    if (result == null || !mounted) return;

    SnackUtils.show(
      context,
      result == "SUCCESS"
          ? "Đã gửi lời mời thành công! Chờ người kia đồng ý nhé."
          : result,
      success: result == "SUCCESS",
    );
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

    final result = await FirebaseService.removeContact(contactId, email);
    if (!mounted) return;

    SnackUtils.show(
      context,
      result == "SUCCESS" ? "Đã hủy kết bạn" : result,
      success: result == "SUCCESS",
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


  String _formatChatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate();
    final now = DateTime.now();
    
    final diff = now.difference(date);
    if (diff.inDays == 0 && date.day == now.day) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && date.day != now.day)) {
      return 'Hôm qua';
    } else if (diff.inDays < 7) {
      switch (date.weekday) {
        case 1: return 'Thứ 2';
        case 2: return 'Thứ 3';
        case 3: return 'Thứ 4';
        case 4: return 'Thứ 5';
        case 5: return 'Thứ 6';
        case 6: return 'Thứ 7';
        case 7: return 'Chủ Nhật';
        default: return '';
      }
    } else {
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day/$month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      });
    }
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
            stream: _friendRequestsStream,
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
                    color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'Lời mời kết bạn (${requests.length})',
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
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
                        tileColor: colorScheme.secondaryContainer.withValues(alpha: 0.3),
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
              focusNode: _searchFocusNode,
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
              stream: _chatListStream,
              builder: (context, chatSnapshot) {
                final myEmail = AppState.currentUserEmail.toLowerCase().trim();
                final chatsMap = <String, Map<String, dynamic>>{};
                if (chatSnapshot.hasData) {
                  for (final doc in chatSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    final participants = List<String>.from(data['participants'] ?? const []);
                    final friendEmail = participants.firstWhere(
                      (p) => p.toLowerCase().trim() != myEmail,
                      orElse: () => '',
                    ).toLowerCase().trim();
                    if (friendEmail.isNotEmpty) {
                      chatsMap[friendEmail] = data;
                    }
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: _contactsStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError || chatSnapshot.hasError) {
                      final err = snapshot.error ?? chatSnapshot.error;
                      debugPrint('Error in contacts or chat list stream: $err');
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_off_outlined, size: 64, color: colorScheme.outlineVariant),
                            const SizedBox(height: 16),
                            Text('Không tải được danh bạ', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() {
                                _contactsStream = FirebaseService.getContactsStream();
                                _chatListStream = FirebaseService.getChatListStream();
                              }),
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting ||
                        chatSnapshot.connectionState == ConnectionState.waiting) {
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
 
                    // Sắp xếp contacts theo kiểu Zalo: Ghim -> updatedAt gần nhất -> Tên bảng chữ cái
                    contacts.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;

                      final emailA = (dataA['email'] ?? '').toString().toLowerCase().trim();
                      final emailB = (dataB['email'] ?? '').toString().toLowerCase().trim();

                      final isPinnedA = dataA['chatPinned'] == true;
                      final isPinnedB = dataB['chatPinned'] == true;

                      if (isPinnedA != isPinnedB) {
                        return isPinnedA ? -1 : 1;
                      }

                      final chatA = chatsMap[emailA];
                      final chatB = chatsMap[emailB];

                      final timeA = chatA?['updatedAt'] as Timestamp?;
                      final timeB = chatB?['updatedAt'] as Timestamp?;

                      if (timeA != null && timeB != null) {
                        return timeB.compareTo(timeA); // tin nhắn mới nhất trước
                      } else if (timeA != null) {
                        return -1;
                      } else if (timeB != null) {
                        return 1;
                      }

                      final nameA = (dataA['name'] ?? '').toString().toLowerCase();
                      final nameB = (dataB['name'] ?? '').toString().toLowerCase();
                      return nameA.compareTo(nameB);
                    });

                    return StreamBuilder<QuerySnapshot>(
                      stream: _myMutesStream,
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
 
                            final cleanEmail = email.toLowerCase().trim();
                            final hasChat = chatsMap.containsKey(cleanEmail);
                            final chatData = chatsMap[cleanEmail];
                            final unreadCount = hasChat ? (chatData!['unreadCount']?[myEmail] ?? 0) as int : 0;
                            final lastMsg = hasChat ? (chatData!['lastMessage'] ?? '').toString() : '';
                            final lastSender = hasChat ? (chatData!['lastSender'] ?? '').toString() : '';
                            final isMe = lastSender == myEmail;
                            final lastMsgTime = hasChat ? chatData!['updatedAt'] as Timestamp? : null;

                            Widget avatarWidget = Stack(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  backgroundImage: avatarImageProvider(
                                    contact['avatar']?.toString(),
                                    name: name.toString(),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onTap: () {
                                        final avatar = contact['avatar']?.toString() ?? '';
                                        if (avatar.isNotEmpty) {
                                          _showFullScreenImage(avatar, name.toString());
                                        }
                                      },
                                    ),
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
                            );

                            if (unreadCount > 0) {
                              avatarWidget = Badge(
                                label: Text(unreadCount.toString()),
                                backgroundColor: Colors.red,
                                child: avatarWidget,
                              );
                            }

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: avatarWidget,
                              title: Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasChat && lastMsg.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        isMe ? "Bạn: $lastMsg" : lastMsg,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                          color: unreadCount > 0 ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(email),
                                  const SizedBox(height: 2),
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
                                          color: isOnline ? Colors.green : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          fontWeight: isOnline ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      );
                                    },
                                  ),
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
                                  if (lastMsgTime != null) ...[
                                    Text(
                                      _formatChatTime(lastMsgTime),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: unreadCount > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                        fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
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

  void _showFullScreenImage(String imageUrl, String name) {
    final imageProvider = CachedNetworkImageProvider(imageUrl);
    showImageViewer(
      context,
      imageProvider,
      swipeDismissible: true,
      doubleTapZoomable: true,
    );
  }
}

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _emailCtrl = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            controller: _emailCtrl,
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
          onPressed: _isAdding ? null : () => Navigator.pop(context),
          child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          onPressed: _isAdding
              ? null
              : () async {
                  final targetEmail = _emailCtrl.text.trim().toLowerCase();
                  if (targetEmail.isEmpty) return;

                  final myEmail = AppState.currentUserEmail.toLowerCase().trim();
                  if (targetEmail == myEmail) {
                    Navigator.pop(context, "Không thể tự kết bạn với chính mình!");
                    return;
                  }

                  setState(() => _isAdding = true);

                  try {
                    final result = await FirebaseService.sendFriendRequest(targetEmail);
                    if (context.mounted) {
                      Navigator.pop(context, result);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => _isAdding = false);
                      Navigator.pop(context, "Lỗi hệ thống: $e");
                    }
                  }
                },
          child: _isAdding
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
  }
}








