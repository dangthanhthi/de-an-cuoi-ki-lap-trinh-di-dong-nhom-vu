import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import '../widgets/ui_state_view.dart';
import '../utils/snack_utils.dart';
import 'group_info_screen.dart';
import 'group_notes_screen.dart';

class GroupsListScreen extends StatefulWidget {
  const GroupsListScreen({super.key});

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();
  Stream<QuerySnapshot>? _groupsStream;
  late Stream<QuerySnapshot> _groupRequestsStream;
  final Map<String, Stream<List<Map<String, dynamic>>>> _onlineMembersStreams = {};

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _groupsStream = FirebaseService.getMyGroupsStream();
    _groupRequestsStream = FirebaseService.getGroupRequestsForLeaderStream();
  }

  void _showSnack(String message, {bool success = true}) {
    SnackUtils.show(context, message, success: success);
  }

  DateTime _groupSortDate(Map<String, dynamic> group) {
    final updatedAt = group['updatedAt'];
    final createdAt = group['createdAt'];
    if (updatedAt is Timestamp) return updatedAt.toDate();
    if (createdAt is Timestamp) return createdAt.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _toggleGroupPinAction(String groupId, bool isPinned) async {
    final result = await FirebaseService.toggleGroupPin(groupId, !isPinned);
    if (!mounted) return;
    _showSnack(
      result == "SUCCESS"
          ? (!isPinned ? "Đã ghim nhóm" : "Đã bỏ ghim nhóm")
          : result,
      success: result == "SUCCESS",
    );
  }

  Future<void> _openGroupInfo(String groupId, String groupName) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GroupInfoScreen(groupId: groupId, initialName: groupName),
      ),
    );
  }

  Future<void> _showGroupQuickActions({
    required String groupId,
    required String groupName,
    required bool isLeader,
    required bool isPinned,
  }) async {
    final isMuted = await FirebaseService.isTargetMuted(type: 'group', targetId: groupId);
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Thông tin nhóm'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openGroupInfo(groupId, groupName);
              },
            ),
            ListTile(
              leading: Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              title: Text(isPinned ? 'Bỏ ghim nhóm' : 'Ghim nhóm'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleGroupPinAction(groupId, isPinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_paused_outlined),
              title: const Text('Tắt thông báo 1 giờ'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseService.muteTarget(type: 'group', targetId: groupId, duration: const Duration(hours: 1));
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined),
              title: const Text('Tắt thông báo cho đến khi mở lại'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseService.muteTarget(type: 'group', targetId: groupId, duration: const Duration(days: 36500));
                if (mounted) setState(() {});
              },
            ),
            if (isMuted)
              ListTile(
                leading: const Icon(Icons.volume_up_outlined),
                title: const Text('Mở lại thông báo'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await FirebaseService.unmuteTarget(type: 'group', targetId: groupId);
                  if (mounted) setState(() {});
                },
              ),
            const Divider(),
            if (isLeader) ...[
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Giải tán nhóm'),
                textColor: Colors.red,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteGroup(context, groupId);
                },
              ),
            ] else
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Rời nhóm?'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmLeaveGroup(context, groupId);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateGroupDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo nhóm mới'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(hintText: 'Tên nhóm...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;

              Navigator.pop(ctx);

              final result = await FirebaseService.createGroup(name);
              if (context.mounted) {
                _showSnack(
                  result == "SUCCESS" ? "Đã tạo nhóm mới" : result,
                  success: result == "SUCCESS",
                );
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  Future<void> _showJoinGroupDialog(BuildContext context) async {
    final codeCtrl = TextEditingController();
    bool isJoining = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Tham gia bằng mã'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nhập mã gồm 8 ký tự do trưởng nhóm cung cấp:'),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  maxLength: 8,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Mã nhóm...',
                    prefixIcon: const Icon(Icons.sensor_door_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
              ),
              FilledButton(
                onPressed: isJoining
                    ? null
                    : () async {
                        if (codeCtrl.text.trim().isEmpty) return;
                        setDialogState(() => isJoining = true);

                        String result = await FirebaseService.joinGroupByCode(
                          codeCtrl.text.trim(),
                        );

                        if (context.mounted) {
                          setDialogState(() => isJoining = false);
                          Navigator.pop(ctx);
                          if (result == "SUCCESS") {
                            _showSnack('Vào nhóm thành công!');
                          } else {
                            _showSnack(result, success: false);
                          }
                        }
                      },
                child: isJoining
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Tham gia'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context, String groupId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhóm?'),
        content: const Text(
          'Bạn có chắc chắn muốn giải tán nhóm này? Toàn bộ ghi chú trong nhóm sẽ bị xóa và không thể khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final result = await FirebaseService.deleteGroup(groupId);
              if (!context.mounted) return;
              Navigator.pop(ctx);
              _showSnack(
                result == "SUCCESS" ? "Đã giải tán nhóm" : result,
                success: result == "SUCCESS",
              );
            },
            child: const Text('Xóa ngay'),
          ),
        ],
      ),
    );
  }

  void _confirmLeaveGroup(BuildContext context, String groupId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời nhóm?'),
        content: const Text('Bạn có chắc muốn rời khỏi nhóm này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              final result = await FirebaseService.removeMemberFromGroup(
                groupId,
                AppState.currentUserEmail,
              );
              if (!context.mounted) return;
              Navigator.pop(ctx);
              _showSnack(
                result == "SUCCESS" ? "Đã rời nhóm" : result,
                success: result == "SUCCESS",
              );
            },
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
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
          'Nhóm của tôi',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [SizedBox(width: 8)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.secondaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nhóm của bạn',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Không gian cộng tác: Thảo luận, quản lý ghi chú và theo dõi mọi biến động của nhóm tại một nơi duy nhất.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _showCreateGroupDialog(context),
                        icon: const Icon(Icons.group_add),
                        label: const Text('Tạo nhóm'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showJoinGroupDialog(context),
                        icon: const Icon(Icons.login),
                        label: const Text('Nhập mã'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              focusNode: _searchFocusNode,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm nhóm...',
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
              stream: _groupsStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint("GROUP STREAM ERROR DETAILS: ${snapshot.error}");
                  return const UiStateView(
                    icon: Icons.cloud_off_outlined,
                    title: 'Không tải được danh sách nhóm',
                    message: 'Kiểm tra kết nối hoặc thử đăng nhập lại.',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const UiStateLoading(message: 'Đang tải nhóm...');
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return UiStateView(
                    icon: Icons.group_add_outlined,
                    title: 'Bạn chưa tham gia nhóm nào',
                    message: 'Tạo nhóm mới hoặc nhập mã để bắt đầu cộng tác.',
                    action: Wrap(
                      spacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _showCreateGroupDialog(context),
                          icon: const Icon(Icons.group_add),
                          label: const Text('Tạo nhóm'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _showJoinGroupDialog(context),
                          icon: const Icon(Icons.login),
                          label: const Text('Nhập mã'),
                        ),
                      ],
                    ),
                  );
                }

                final query = _searchQuery.toLowerCase().trim();
                final safeEmail = AppState.currentUserEmail
                    .toLowerCase()
                    .trim();
                final groups =
                    snapshot.data!.docs.where((doc) {
                      final group = doc.data() as Map<String, dynamic>;
                      final name = (group['name'] ?? '')
                          .toString()
                          .toLowerCase();
                      final code = (group['groupCode'] ?? '')
                          .toString()
                          .toLowerCase();
                      return query.isEmpty ||
                          name.contains(query) ||
                          code.contains(query);
                    }).toList()..sort((a, b) {
                      final groupA = a.data() as Map<String, dynamic>;
                      final groupB = b.data() as Map<String, dynamic>;
                      final pinnedA = List<String>.from(
                        groupA['pinnedBy'] ?? const [],
                      ).contains(safeEmail);
                      final pinnedB = List<String>.from(
                        groupB['pinnedBy'] ?? const [],
                      ).contains(safeEmail);
                      if (pinnedA != pinnedB) return pinnedA ? -1 : 1;
                      return _groupSortDate(
                        groupB,
                      ).compareTo(_groupSortDate(groupA));
                    });

                if (groups.isEmpty) {
                  return const UiStateView(
                    icon: Icons.search_off_outlined,
                    title: 'Không tìm thấy nhóm',
                    message: 'Thử đổi từ khóa hoặc tìm bằng mã nhóm.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index].data() as Map<String, dynamic>;
                    final groupId = groups[index].id;
                    final groupName = (group['name'] ?? 'Nhóm').toString();
                    final groupAvatar = (group['avatar'] ?? '').toString();
                    final leaderId = (group['leaderId'] ?? '').toString();

                    final managerEmails = List<String>.from(
                      group['managerEmails'] ?? const [],
                    ).map((item) => item.toLowerCase().trim()).toList();
                    final isManager = managerEmails.contains(safeEmail);
                    final isLeader = leaderId == FirebaseService.currentUid;
                    final members = [
                      ...List<String>.from(group['members'] ?? const []),
                      ...List<String>.from(group['memberEmails'] ?? const []),
                    ].map((item) => item.toLowerCase().trim()).toSet().toList();
                    final groupCode = (group['groupCode'] ?? 'Chưa có mã')
                        .toString();

                    final isPinned = List<String>.from(
                      group['pinnedBy'] ?? const [],
                    ).contains(safeEmail);

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isPinned
                              ? colorScheme.primary.withValues(alpha: 0.34)
                              : colorScheme.outlineVariant,
                        ),
                      ),
                      color: isPinned
                          ? colorScheme.primaryContainer.withValues(alpha: 0.28)
                          : colorScheme.surfaceContainerLow,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),

                        leading: StreamBuilder<QuerySnapshot>(
                          stream: (isLeader || isManager)
                              ? _groupRequestsStream
                              : const Stream.empty(),
                          builder: (context, snap) {
                            final reqs = (snap.data?.docs ?? [])
                                .where(
                                  (d) =>
                                      (d.data()
                                          as Map<String, dynamic>)['groupId'] ==
                                      groupId,
                                )
                                .length;
                            return Badge(
                              isLabelVisible: reqs > 0,
                              label: Text(reqs.toString()),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundImage: avatarImageProvider(
                                  groupAvatar,
                                  name: groupName,
                                ),
                              ),
                            );
                          },
                        ),

                        title: Text(
                          groupName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),

                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _onlineMembersStreams[groupId] ??=
                                  FirebaseService.getOnlineGroupMembersStream(
                                    groupId,
                                  ),
                              builder: (context, presenceSnap) {
                                final onlineCount =
                                    presenceSnap.data?.length ?? 0;
                                final myEmail = AppState.currentUserEmail
                                    .toLowerCase()
                                    .trim();
                                final managerEmails =
                                    List<String>.from(
                                          group['managerEmails'] ?? const [],
                                        )
                                        .map(
                                          (item) => item.toLowerCase().trim(),
                                        )
                                        .toList();
                                final isManager = managerEmails.contains(
                                  myEmail,
                                );

                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (isLeader)
                                      const _MetaBadge(
                                        icon: Icons.key,
                                        label: 'Trưởng nhóm',
                                        color: Color(0xFFC58A00),
                                      )
                                    else if (isManager)
                                      _MetaBadge(
                                        icon: Icons.key_outlined,
                                        label: 'Quản lý',
                                        color: colorScheme.secondary,
                                      )
                                    else
                                      _MetaBadge(
                                        icon: Icons.person_outline,
                                        label: 'Thành viên',
                                        color: colorScheme.outline,
                                      ),
                                    _MetaBadge(
                                      icon: Icons.people_outline,
                                      label:
                                          '$onlineCount/${members.length} online',
                                      color: onlineCount > 0
                                          ? Colors.green
                                          : colorScheme.primary,
                                    ),
                                    if (isPinned)
                                      _MetaBadge(
                                        icon: Icons.push_pin,
                                        label: 'Đã ghim',
                                        color: colorScheme.primary,
                                      ),
                                    FutureBuilder<bool>(
                                      future: FirebaseService.isTargetMuted(type: 'group', targetId: groupId),
                                      builder: (context, muteSnap) {
                                        if (muteSnap.data == true) {
                                          return _MetaBadge(
                                            icon: Icons.notifications_off_outlined,
                                            label: 'Đã tắt thông báo',
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                            if (groupCode != 'Chưa có mã') ...[
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: groupCode),
                                  );
                                  _showSnack('Đã chép mã nhóm vào khay nhớ tạm!');
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Mã: $groupCode',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isPinned) ...[
                              Icon(
                                Icons.push_pin,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                            ],
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _showGroupQuickActions(
                                groupId: groupId,
                                groupName: groupName,
                                isLeader: isLeader,
                                isPinned: isPinned,
                              ),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupNotesScreen(
                                groupId: groupId,
                                groupName: groupName,
                              ),
                            ),
                          );
                          if (!context.mounted) return;
                          if (result == 'deleted') {
                            _showSnack('Đã giải tán nhóm thành công');
                          } else if (result == 'left') {
                            _showSnack('Bạn đã rời khỏi nhóm');
                          }
                        },
                        onLongPress: () => _showGroupQuickActions(
                          groupId: groupId,
                          groupName: groupName,
                          isLeader: isLeader,
                          isPinned: isPinned,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
