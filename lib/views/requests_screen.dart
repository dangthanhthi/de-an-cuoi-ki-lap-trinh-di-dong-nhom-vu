import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/app_state.dart';
import '../controllers/note_provider.dart';
import '../models/app_models.dart';
import '../utils/media_utils.dart';
import '../utils/snack_utils.dart';
import 'chat_screen.dart';
import 'group_notes_screen.dart';
import 'note_detail_screen.dart';

class OverdueItem {
  final Note note;
  final TodoItem todo;
  final int index;
  final String groupName;

  OverdueItem({
    required this.note,
    required this.todo,
    required this.index,
    required this.groupName,
  });

  String get key => '${note.id}:$index:${todo.deadline?.toIso8601String() ?? ''}';
}

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  late Stream<QuerySnapshot> _noteInvitesHeaderStream;
  late Stream<QuerySnapshot> _noteInvitesBodyStream;

  late Stream<QuerySnapshot> _groupInvitesHeaderStream;
  late Stream<QuerySnapshot> _groupInvitesBodyStream;

  late Stream<QuerySnapshot> _groupRequestsForLeaderHeaderStream;
  late Stream<QuerySnapshot> _groupRequestsForLeaderBodyStream;

  late Stream<QuerySnapshot> _friendRequestsHeaderStream;
  late Stream<QuerySnapshot> _friendRequestsBodyStream;

  late Stream<int> _unreadChatCountStream;
  late Stream<int> _unreadGroupCountStream;
  late Stream<QuerySnapshot> _chatListStream;

  late Stream<QuerySnapshot> _myGroupsSubscriptionStream;
  late Stream<QuerySnapshot> _myGroupsBodyStream;

  Set<String> _myLedGroupIds = {};
  StreamSubscription? _myGroupsSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('DEBUG: RequestsScreen initState. Email: "${AppState.currentUserEmail}" Uid: "${FirebaseService.currentUid}"');
    _tabController = TabController(length: 6, vsync: this);

    _noteInvitesHeaderStream = FirebaseService.getNoteInvitesStream().map((snapshot) {
      debugPrint('DEBUG: _noteInvitesHeaderStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _noteInvitesHeaderStream error: $err');
      throw err;
    });
    _noteInvitesBodyStream = FirebaseService.getNoteInvitesStream().map((snapshot) {
      debugPrint('DEBUG: _noteInvitesBodyStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _noteInvitesBodyStream error: $err');
      throw err;
    });

    _groupInvitesHeaderStream = FirebaseService.getGroupInvitesStream().map((snapshot) {
      debugPrint('DEBUG: _groupInvitesHeaderStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _groupInvitesHeaderStream error: $err');
      throw err;
    });
    _groupInvitesBodyStream = FirebaseService.getGroupInvitesStream().map((snapshot) {
      debugPrint('DEBUG: _groupInvitesBodyStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _groupInvitesBodyStream error: $err');
      throw err;
    });

    _groupRequestsForLeaderHeaderStream = FirebaseService.getGroupRequestsForLeaderStream().map((snapshot) {
      debugPrint('DEBUG: _groupRequestsForLeaderHeaderStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _groupRequestsForLeaderHeaderStream error: $err');
      throw err;
    });
    _groupRequestsForLeaderBodyStream = FirebaseService.getGroupRequestsForLeaderStream().map((snapshot) {
      debugPrint('DEBUG: _groupRequestsForLeaderBodyStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _groupRequestsForLeaderBodyStream error: $err');
      throw err;
    });

    _friendRequestsHeaderStream = FirebaseService.getFriendRequestsStream().map((snapshot) {
      debugPrint('DEBUG: _friendRequestsHeaderStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _friendRequestsHeaderStream error: $err');
      throw err;
    });
    _friendRequestsBodyStream = FirebaseService.getFriendRequestsStream().map((snapshot) {
      debugPrint('DEBUG: _friendRequestsBodyStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _friendRequestsBodyStream error: $err');
      throw err;
    });

    _unreadChatCountStream = FirebaseService.unreadChatMessagesCountStream().map((count) {
      debugPrint('DEBUG: _unreadChatCountStream emitted count: $count');
      return count;
    }).handleError((err) {
      debugPrint('DEBUG: _unreadChatCountStream error: $err');
      throw err;
    });

    _unreadGroupCountStream = FirebaseService.unreadGroupMessagesCountStream().map((count) {
      debugPrint('DEBUG: _unreadGroupCountStream emitted count: $count');
      return count;
    }).handleError((err) {
      debugPrint('DEBUG: _unreadGroupCountStream error: $err');
      throw err;
    });

    _chatListStream = FirebaseService.getChatListStream().map((snapshot) {
      debugPrint('DEBUG: _chatListStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _chatListStream error: $err');
      throw err;
    });

    _myGroupsSubscriptionStream = FirebaseService.getMyGroupsStream().map((snapshot) {
      debugPrint('DEBUG: _myGroupsSubscriptionStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _myGroupsSubscriptionStream error: $err');
      throw err;
    });
    _myGroupsBodyStream = FirebaseService.getMyGroupsStream().map((snapshot) {
      debugPrint('DEBUG: _myGroupsBodyStream emitted ${snapshot.docs.length} docs');
      return snapshot;
    }).handleError((err) {
      debugPrint('DEBUG: _myGroupsBodyStream error: $err');
      throw err;
    });

    _myGroupsSubscription = _myGroupsSubscriptionStream.listen(
      (snapshot) {
        final myUid = FirebaseService.currentUid;
        final ledGroups = snapshot.docs
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['leaderId'] == myUid;
            })
            .map((doc) => doc.id)
            .toSet();
        if (mounted) {
          setState(() {
            _myLedGroupIds = ledGroups;
          });
        }
      },
      onError: (err) {
        debugPrint('DEBUG: _myGroupsSubscription error: $err');
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _myGroupsSubscription?.cancel();
    super.dispose();
  }

  void _showSnack(String message, {bool success = true}) {
    SnackUtils.show(context, message, success: success);
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String content,
    String confirmLabel = 'Từ chối',
    Color confirmColor = Colors.red,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: TextStyle(color: confirmColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Widget _buildTab(String label, Stream<QuerySnapshot> stream) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Tab(
          child: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: Text(label),
          ),
        );
      },
    );
  }

  Widget _buildGroupTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _groupInvitesHeaderStream,
      builder: (context, invitesSnap) {
        final invitesCount = invitesSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot>(
          stream: _groupRequestsForLeaderHeaderStream,
          builder: (context, requestsSnap) {
            final requestsCount = requestsSnap.data?.docs.length ?? 0;
            final total = invitesCount + requestsCount;
            return Tab(
              child: Badge(
                label: Text('$total'),
                isLabelVisible: total > 0,
                child: const Text('Nhóm'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnreadChatsTabHeader() {
    return StreamBuilder<int>(
      stream: _unreadChatCountStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Tab(
          child: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: const Text('Tin nhắn'),
          ),
        );
      },
    );
  }

  Widget _buildUnreadGroupChatsTabHeader() {
    return StreamBuilder<int>(
      stream: _unreadGroupCountStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Tab(
          child: Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: const Text('Nhóm Chat'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteProvider>(
      builder: (context, noteProvider, child) {
        final overdueItems = _getOverdueItems(noteProvider.allNotes);
        final overdueCount = overdueItems.length;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Thông báo & Yêu cầu'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
              tabs: [
                _buildTab('Ghi chú', _noteInvitesHeaderStream),
                _buildGroupTab(),
                _buildTab('Bạn bè', _friendRequestsHeaderStream),
                _buildUnreadChatsTabHeader(),
                _buildUnreadGroupChatsTabHeader(),
                _buildOverdueTab(overdueCount),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              KeepAliveWrapper(child: _buildNoteInvitesTab()),
              KeepAliveWrapper(child: _buildGroupInvitesTab()),
              KeepAliveWrapper(child: _buildFriendRequestsTab()),
              KeepAliveWrapper(child: _buildUnreadChatsTabView()),
              KeepAliveWrapper(child: _buildUnreadGroupChatsTabView()),
              KeepAliveWrapper(child: _buildOverdueTabView(noteProvider, overdueItems)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNoteInvitesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _noteInvitesBodyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('DEBUG: _noteInvitesStream error: ${snapshot.error}');
          return const _EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'Không tải được dữ liệu. Kiểm tra kết nối mạng.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.note_add_outlined,
            text: 'Không có lời mời chia sẻ ghi chú nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final colorScheme = Theme.of(context).colorScheme;

            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: colorScheme.primary,
                  ),
                ),
                title: Text(
                  data['noteTitle'] ?? 'Ghi chú',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Từ: ${data['fromName'] ?? data['fromEmail']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.check),
                      onPressed: () async {
                        final res = await FirebaseService.respondToNoteInvite(
                          doc.id,
                          true,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã chấp nhận lời mời chia sẻ ghi chú' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: () async {
                        final confirmed = await _showConfirmDialog(
                          context,
                          title: 'Từ chối lời mời?',
                          content: 'Bạn có chắc chắn muốn từ chối lời mời cộng tác ghi chú này không?',
                          confirmLabel: 'Từ chối',
                        );
                        if (!confirmed) return;

                        final res = await FirebaseService.respondToNoteInvite(
                          doc.id,
                          false,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã từ chối lời mời chia sẻ ghi chú' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGroupInvitesTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _groupInvitesBodyStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('DEBUG: _groupInvitesStream error: ${snapshot.error}');
                return const _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  text: 'Không tải được dữ liệu. Kiểm tra kết nối mạng.',
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final invites = snapshot.data?.docs ?? [];
              return StreamBuilder<QuerySnapshot>(
                stream: _groupRequestsForLeaderBodyStream,
                builder: (context, leaderSnap) {
                  if (leaderSnap.hasError) {
                    debugPrint('DEBUG: _groupRequestsForLeaderStream error: ${leaderSnap.error}');
                    return const _EmptyState(
                      icon: Icons.cloud_off_outlined,
                      text: 'Không tải được dữ liệu. Kiểm tra kết nối mạng.',
                    );
                  }
                  if (leaderSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final joinRequests = leaderSnap.data?.docs ?? [];
                  final all = [...invites, ...joinRequests];

                  if (all.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.group_add_outlined,
                      text: 'Không có lời mời hoặc yêu cầu vào nhóm nào.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final doc = all[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final colorScheme = Theme.of(context).colorScheme;
                      final isJoinRequest = joinRequests.contains(doc);

                      return Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isJoinRequest
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isJoinRequest
                                  ? Icons.person_add_alt_1_outlined
                                  : Icons.groups_outlined,
                              color: isJoinRequest
                                  ? colorScheme.tertiary
                                  : colorScheme.secondary,
                            ),
                          ),
                          title: Text(
                            isJoinRequest
                                ? 'Yêu cầu vào nhóm: ${data['groupName']}'
                                : (data['groupName'] ?? 'Nhóm'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isJoinRequest
                                ? 'Từ: ${data['userName']} (${data['userEmail']})'
                                : 'Mời bởi: ${data['fromName'] ?? data['fromEmail']}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filledTonal(
                                icon: const Icon(Icons.check),
                                onPressed: () async {
                                  if (isJoinRequest) {
                                    final res = await FirebaseService.respondToGroupRequest(
                                      doc.id,
                                      true,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã chấp nhận thành viên' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  } else {
                                    final res = await FirebaseService.respondToGroupInvite(
                                      doc.id,
                                      true,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã chấp nhận lời mời vào nhóm' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                icon: const Icon(Icons.close),
                                style: IconButton.styleFrom(
                                  foregroundColor: colorScheme.error,
                                ),
                                onPressed: () async {
                                  final confirmed = await _showConfirmDialog(
                                    context,
                                    title: isJoinRequest ? 'Từ chối yêu cầu?' : 'Từ chối lời mời?',
                                    content: isJoinRequest
                                        ? 'Bạn có chắc chắn muốn từ chối yêu cầu tham gia nhóm này không?'
                                        : 'Bạn có chắc chắn muốn từ chối lời mời vào nhóm này không?',
                                    confirmLabel: 'Từ chối',
                                  );
                                  if (!confirmed) return;

                                  if (isJoinRequest) {
                                    final res = await FirebaseService.respondToGroupRequest(
                                      doc.id,
                                      false,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã từ chối yêu cầu thành viên' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  } else {
                                    final res = await FirebaseService.respondToGroupInvite(
                                      doc.id,
                                      false,
                                    );
                                    _showSnack(
                                      res == 'SUCCESS' ? 'Đã từ chối lời mời vào nhóm' : res,
                                      success: res == 'SUCCESS',
                                    );
                                  }
                                },
                              ),
                            ],
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
    );
  }

  Widget _buildFriendRequestsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _friendRequestsBodyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('DEBUG: _friendRequestsStream error: ${snapshot.error}');
          return const _EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'Không tải được dữ liệu. Kiểm tra kết nối mạng.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyState(
            icon: Icons.person_add_outlined,
            text: 'Không có lời mời kết bạn nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final colorScheme = Theme.of(context).colorScheme;

            return Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundImage: avatarImageProvider(
                    data['fromAvatar'] ?? '',
                    name: data['fromName'] ?? data['fromEmail'],
                  ),
                ),
                title: Text(
                  data['fromName'] ?? 'Người dùng',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(data['fromEmail'] ?? ''),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.check),
                      onPressed: () async {
                        final res = await FirebaseService.acceptFriendRequest(
                          doc.id,
                          data,
                        );
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã kết bạn thành công' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      onPressed: () async {
                        final confirmed = await _showConfirmDialog(
                          context,
                          title: 'Từ chối kết bạn?',
                          content: 'Bạn có chắc chắn muốn từ chối lời mời kết bạn này không?',
                          confirmLabel: 'Từ chối',
                        );
                        if (!confirmed) return;

                        final res = await FirebaseService.rejectFriendRequest(doc.id);
                        _showSnack(
                          res == 'SUCCESS' ? 'Đã từ chối lời mời kết bạn' : res,
                          success: res == 'SUCCESS',
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnreadChatsTabView() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return StreamBuilder<QuerySnapshot>(
      stream: _chatListStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('DEBUG: _chatListStream error: ${snapshot.error}');
          return const _EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'Không tải được tin nhắn. Kiểm tra kết nối mạng.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final unreadChats = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
          return unread > 0;
        }).toList();

        if (unreadChats.isEmpty) {
          return const _EmptyState(
            icon: Icons.chat_outlined,
            text: 'Không có tin nhắn chưa đọc nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: unreadChats.length,
          itemBuilder: (context, index) {
            final doc = unreadChats[index];
            final data = doc.data() as Map<String, dynamic>;
            final participants = List<String>.from(data['participants'] ?? const []);
            final friendEmail = participants.firstWhere(
              (p) => p.toLowerCase().trim() != myEmail,
              orElse: () => '',
            ).toLowerCase().trim();
            final lastMsg = (data['lastMessage'] ?? '').toString();
            final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
            // Dùng lastSenderName nếu có, fallback về friendEmail — tránh FutureBuilder lồng nhau
            final name = (data['lastSenderName'] ?? data['friendName'] ?? friendEmail).toString();
            final avatar = (data['friendAvatar'] ?? '').toString();

            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Badge(
                  label: Text('$unread'),
                  backgroundColor: Colors.red,
                  child: CircleAvatar(
                    backgroundImage: avatarImageProvider(
                      avatar,
                      name: name,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  lastMsg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          friendName: name,
                          friendEmail: friendEmail,
                          friendAvatar: avatar,
                        ),
                      ),
                    );
                  },
                  child: const Text('Xem'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUnreadGroupChatsTabView() {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return StreamBuilder<QuerySnapshot>(
      stream: _myGroupsBodyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('DEBUG: _myGroupsStream error: ${snapshot.error}');
          return const _EmptyState(
            icon: Icons.cloud_off_outlined,
            text: 'Không tải được tin nhắn nhóm. Kiểm tra kết nối mạng.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        final unreadGroups = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final unread = (data['unreadCount']?[myEmail] ?? 0) as int;
          return unread > 0;
        }).toList();

        if (unreadGroups.isEmpty) {
          return const _EmptyState(
            icon: Icons.group_outlined,
            text: 'Không có tin nhắn nhóm chưa đọc nào.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: unreadGroups.length,
          itemBuilder: (context, index) {
            final doc = unreadGroups[index];
            final data = doc.data() as Map<String, dynamic>;
            final groupId = doc.id;
            final groupName = (data['name'] ?? 'Nhóm').toString();
            final groupAvatar = (data['avatar'] ?? '').toString();
            final lastMsg = (data['lastMessage'] ?? '').toString();
            final unread = (data['unreadCount']?[myEmail] ?? 0) as int;

            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: Badge(
                  label: Text('$unread'),
                  backgroundColor: Colors.red,
                  child: CircleAvatar(
                    backgroundImage: avatarImageProvider(
                      groupAvatar,
                      name: groupName,
                    ),
                  ),
                ),
                title: Text(
                  groupName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  lastMsg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupNotesScreen(
                          groupId: groupId,
                          groupName: groupName,
                        ),
                      ),
                    );
                  },
                  child: const Text('Xem'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOverdueTab(int count) {
    return Tab(
      child: Badge(
        label: Text('$count'),
        isLabelVisible: count > 0,
        child: const Text('Trễ hạn'),
      ),
    );
  }

  List<OverdueItem> _getOverdueItems(List<Note> allNotes) {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    if (myEmail.isEmpty) return [];

    final List<OverdueItem> list = [];
    for (final note in allNotes) {
      if (note.hiddenBy.contains(myEmail)) continue;

      for (var index = 0; index < note.todos.length; index++) {
        final todo = note.todos[index];
        if (!todo.isOverdue || todo.status == TodoStatus.done) continue;

        final assigneeEmail = todo.assigneeEmail.toLowerCase().trim();
        final assignedToMe = assigneeEmail == myEmail;
        final unassignedOwnedByMe =
            assigneeEmail.isEmpty && note.createdByEmail == myEmail;
        final isGroupLeader = note.groupId.isNotEmpty && _myLedGroupIds.contains(note.groupId);

        if (!assignedToMe && !isGroupLeader && !unassignedOwnedByMe) continue;

        final key = '${note.id}:$index:${todo.deadline?.toIso8601String() ?? ''}';
        if (AppState.dismissedOverdueTodos.contains(key)) continue;

        list.add(OverdueItem(
          note: note,
          todo: todo,
          index: index,
          groupName: note.groupName,
        ));
      }
    }
    return list;
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildOverdueTabView(NoteProvider noteProvider, List<OverdueItem> items) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.timer_outlined,
        text: 'Không có công việc trễ hạn nào.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final colorScheme = Theme.of(context).colorScheme;

        return Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.assignment_late_outlined,
                color: colorScheme.error,
              ),
            ),
            title: Text(
              item.todo.task,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Trong ghi chú: ${item.note.title}${item.groupName.isNotEmpty ? ' - Nhóm: ${item.groupName}' : ''}\nHạn chót: ${_formatDateTime(item.todo.deadline)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.open_in_new),
                  tooltip: 'Xem ghi chú',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NoteDetailScreen(note: item.note),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: const Icon(Icons.close),
                  tooltip: 'Tắt thông báo',
                  style: IconButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  onPressed: () async {
                    final confirmed = await _showConfirmDialog(
                      context,
                      title: 'Tắt thông báo trễ hạn?',
                      content: 'Bạn có chắc chắn muốn tắt và xóa thông báo trễ hạn này không?',
                      confirmLabel: 'Tắt thông báo',
                    );
                    if (!confirmed) return;

                    await noteProvider.dismissOverdueTodo(item.key);
                    _showSnack('Đã ẩn thông báo trễ hạn.');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 48,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}








