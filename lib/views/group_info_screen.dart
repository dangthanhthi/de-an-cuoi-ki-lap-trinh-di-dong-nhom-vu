import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import '../widgets/ui_state_view.dart';

class GroupInfoScreen extends StatefulWidget {
  final String groupId;
  final String initialName;

  const GroupInfoScreen({
    super.key,
    required this.groupId,
    required this.initialName,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  void _showSnack(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? Colors.green
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _changeGroupAvatar() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 60,
      maxWidth: 720,
    );
    if (image == null) return;

    try {
      final file = File(image.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = "group_${widget.groupId}_$timestamp.jpg";

      final uploadedUrl = await FirebaseService.uploadGroupAvatar(
        file,
        fileName,
        widget.groupId,
      );

      if (uploadedUrl.isNotEmpty) {
        final result = await FirebaseService.updateGroupAvatar(
          widget.groupId,
          uploadedUrl,
        );
        _showSnack(
          result == 'SUCCESS' ? 'Đã cập nhật ảnh nhóm thành công' : result,
          success: result == 'SUCCESS',
        );
      }
    } on FirebaseException catch (e) {
      _showSnack('Lỗi Firebase (${e.code}): ${e.message}', success: false);
    } catch (e) {
      _showSnack('Lỗi hệ thống: $e', success: false);
    }
  }

  void _previewGroupAvatar(String avatar, String groupName) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Image(
                image: avatarImageProvider(avatar, name: groupName),
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupAvatarActions({
    required String avatar,
    required String groupName,
    required bool canEdit,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Xem ảnh nhóm hiện tại'),
              onTap: () {
                Navigator.pop(sheetContext);
                _previewGroupAvatar(avatar, groupName);
              },
            ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Thay đổi ảnh nhóm'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _changeGroupAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupNameDialog(String currentName) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _EditGroupNameDialog(
        groupId: widget.groupId,
        initialName: currentName,
        onSuccess: (msg) => _showSnack(msg),
        onError: (msg) => _showSnack(msg, success: false),
      ),
    );
  }

  Future<void> _showAddMemberDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AddMemberDialog(
        groupId: widget.groupId,
        onSuccess: (msg) => _showSnack(msg),
        onError: (msg) => _showSnack(msg, success: false),
      ),
    );
  }

  Future<void> _toggleManagerRole(String email, bool isManager) async {
    final shouldToggle = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isManager ? 'Thu hồi key bạc?' : 'Cấp key bạc?'),
        content: Text(
          isManager
              ? 'Người này sẽ không còn quyền quản lý ghi chú nhóm.'
              : 'Người này sẽ có quyền sửa/xóa các ghi chú trong nhóm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isManager ? 'Thu hồi' : 'Cấp quyền'),
          ),
        ],
      ),
    );
    if (shouldToggle != true || !mounted) return;

    try {
      final result = await FirebaseService.updateGroupManagerRole(
        widget.groupId,
        email,
        !isManager,
      );
      if (!mounted) return;
      _showSnack(
        result == 'SUCCESS'
            ? (!isManager
                  ? 'Đã cấp key bạc cho $email'
                  : 'Đã thu hồi key bạc của $email')
            : result,
        success: result == 'SUCCESS',
      );
    } catch (e) {
      if (mounted) _showSnack('Lỗi: $e', success: false);
    }
  }

  Future<void> _removeMember(String email) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa thành viên?'),
        content: Text('Bạn có chắc muốn xóa $email khỏi nhóm không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldRemove != true) return;

    try {
      final result = await FirebaseService.removeMemberFromGroup(
        widget.groupId,
        email,
      );
      if (!mounted) return;
      _showSnack(
        result == 'SUCCESS' ? 'Đã xóa thành viên $email khỏi nhóm' : result,
        success: result == 'SUCCESS',
      );
    } catch (e) {
      if (mounted) _showSnack('Lỗi: $e', success: false);
    }
  }

  Future<void> _leaveGroup() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rời nhóm?'),
        content: const Text('Bạn muốn rời khỏi nhóm này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
    if (shouldLeave != true) return;

    final result = await FirebaseService.removeMemberFromGroup(
      widget.groupId,
      AppState.currentUserEmail,
    );
    if (result == 'SUCCESS') {
      if (!mounted) return;
      Navigator.pop(context, 'left');
      return;
    }
    _showSnack(result, success: false);
  }

  Future<void> _deleteGroup() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Giải tán nhóm?'),
        content: const Text(
          'Toàn bộ ghi chú và thảo luận trong nhóm sẽ bị xóa và không thể khôi phục.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Giải tán'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    final result = await FirebaseService.deleteGroup(widget.groupId);
    if (result == 'SUCCESS') {
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
      return;
    }
    _showSnack(result, success: false);
  }

  void _showMembersSheet(List<_MemberViewData> members) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.42,
          builder: (context, scrollController) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'Danh sách thành viên',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final member in members)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundImage: avatarImageProvider(
                      member.avatar,
                      name: member.name,
                    ),
                  ),
                  title: Text(member.name),
                  subtitle: Text(member.email),
                  trailing: _RoleBadge(
                    isLeader: member.isLeader,
                    isManager: member.isManager,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<_MemberViewData> _buildMemberViews({
    required List<String> memberEmails,
    required Map<String, _UserViewData> usersByEmail,
    required String leaderId,
    required Set<String> managerEmails,
  }) {
    String leaderEmail = '';
    for (final entry in usersByEmail.entries) {
      if (entry.value.uid == leaderId) {
        leaderEmail = entry.key;
        break;
      }
    }

    final items = memberEmails.map((email) {
      final user = usersByEmail[email];
      final isLeader = email == leaderEmail;
      final isManager = !isLeader && managerEmails.contains(email);
      return _MemberViewData(
        email: email,
        name: user?.name ?? email,
        avatar: user?.avatar ?? '',
        uid: user?.uid ?? '',
        isLeader: isLeader,
        isManager: isManager,
        lastActive: user?.lastActive,
        isOnline: user?.isOnline ?? false,
      );
    }).toList();

    items.sort((a, b) {
      final roleA = a.isLeader ? 0 : (a.isManager ? 1 : 2);
      final roleB = b.isLeader ? 0 : (b.isManager ? 1 : 2);
      if (roleA != roleB) return roleA.compareTo(roleB);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.getGroupStream(widget.groupId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Thông tin nhóm')),
            body: const UiStateView(
              icon: Icons.cloud_off_outlined,
              title: 'Không tải được thông tin nhóm',
              message: 'Kiểm tra kết nối hoặc thử mở lại màn hình nhóm.',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: UiStateLoading(message: 'Đang tải thông tin nhóm...'),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Thông tin nhóm')),
            body: const UiStateView(
              icon: Icons.group_off_outlined,
              title: 'Không tìm thấy nhóm',
              message:
                  'Nhóm có thể đã bị giải tán hoặc bạn đã mất quyền truy cập.',
            ),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final groupName = (data['name'] ?? widget.initialName).toString();
        final groupAvatar = (data['avatar'] ?? '').toString();
        final leaderId = (data['leaderId'] ?? '').toString();
        final groupCode = (data['groupCode'] ?? '').toString();
        final memberEmails =
            [
                  ...List<String>.from(data['members'] ?? const []),
                  ...List<String>.from(data['memberEmails'] ?? const []),
                ]
                .map((item) => item.toLowerCase().trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList();
        final managerEmails = List<String>.from(
          data['managerEmails'] ?? const [],
        ).map((item) => item.toLowerCase().trim()).toSet();

        final isLeader = leaderId == FirebaseService.currentUid;
        final isManager = !isLeader && managerEmails.contains(myEmail);
        final canManage = isLeader || isManager;
        final roleLabel = isLeader
            ? 'Key vàng • Trưởng nhóm'
            : isManager
            ? 'Key bạc • Điều phối'
            : 'Thành viên';

        return Scaffold(
          appBar: AppBar(title: const Text('Thông tin nhóm')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => _showGroupAvatarActions(
                          avatar: groupAvatar,
                          groupName: groupName,
                          canEdit: isLeader,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundImage: avatarImageProvider(
                                groupAvatar,
                                name: groupName,
                              ),
                            ),
                            if (isLeader)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: colorScheme.primary,
                                  child: Icon(
                                    Icons.camera_alt_outlined,
                                    size: 16,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        groupName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        roleLabel,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          _InfoChip(
                            icon: Icons.people_outline,
                            label: '${memberEmails.length} thành viên',
                          ),
                          if (groupCode.isNotEmpty)
                            _InfoChip(
                              icon: Icons.key_outlined,
                              label: 'Mã $groupCode',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Tác vụ nhanh',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickActionTile(
                    icon: Icons.copy_all_outlined,
                    title: 'Sao chép mã',
                    subtitle: groupCode.isEmpty
                        ? '\u0043\u0068\u01B0\u0061\u0020\u0063\u00F3\u0020\u006D\u00E3\u0020\u006E\u0068\u00F3\u006D'
                        : groupCode,
                    onTap: groupCode.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: groupCode),
                            );
                            _showSnack(
                              '\u0110\u00E3\u0020\u0073\u0061\u006F\u0020\u0063\u0068\u00E9\u0070\u0020\u006D\u00E3\u0020\u006E\u0068\u00F3\u006D',
                            );
                          },
                  ),
                  _QuickActionTile(
                    icon: Icons.edit_outlined,
                    title: 'Đổi tên nhóm',
                    subtitle: isLeader
                        ? 'Cập nhật tên hiển thị'
                        : 'Chỉ trưởng nhóm được đổi tên',
                    onTap: isLeader
                        ? () => _showGroupNameDialog(groupName)
                        : null,
                  ),
                  _QuickActionTile(
                    icon: Icons.person_add_alt_1_outlined,
                    title: 'Thêm thành viên',
                    subtitle: isLeader
                        ? 'Mời thêm người vào nhóm'
                        : 'Chỉ trưởng nhóm được thêm người',
                    onTap: isLeader ? _showAddMemberDialog : null,
                  ),
                  _QuickActionTile(
                    icon: canManage
                        ? Icons.task_alt_outlined
                        : Icons.info_outline,
                    title: canManage ? 'Quyền điều phối' : 'Vai trò hiện tại',
                    subtitle: canManage
                        ? 'Có thể giao việc và điều phối todo'
                        : 'Theo dõi, trao đổi và nhận việc',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildOnlineMembersSection(),
              const SizedBox(height: 18),
              if (isLeader) ...[
                _buildGroupSettings(data),
                const SizedBox(height: 18),
              ],
              Text(
                'Thành viên',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isLeader
                    ? 'Bạn có thể cấp key bạc, thu hồi quyền hoặc xóa thành viên ngay trong danh sách bên dưới.'
                    : 'Danh sách bên dưới cho biết vai trò hiện tại của từng thành viên trong nhóm.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),
                builder: (context, usersSnapshot) {
                  if (usersSnapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: UiStateView(
                        icon: Icons.people_outline,
                        title: 'Không tải được thành viên',
                        message: 'Thử mở lại màn hình sau vài giây.',
                      ),
                    );
                  }
                  if (!usersSnapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: UiStateLoading(message: 'Đang tải thành viên...'),
                    );
                  }

                  final usersByEmail = <String, _UserViewData>{};
                  for (final doc in usersSnapshot.data!.docs) {
                    final user = doc.data() as Map<String, dynamic>;
                    final email = (user['email'] ?? '')
                        .toString()
                        .toLowerCase()
                        .trim();
                    if (email.isEmpty) continue;
                    usersByEmail[email] = _UserViewData(
                      uid: doc.id,
                      name: (user['name'] ?? 'Không tên').toString(),
                      avatar: (user['avatar'] ?? '').toString(),
                      lastActive: user['lastActive'] as Timestamp?,
                      isOnline: user['isOnline'] == true,
                    );
                  }

                  final members = _buildMemberViews(
                    memberEmails: memberEmails,
                    usersByEmail: usersByEmail,
                    leaderId: leaderId,
                    managerEmails: managerEmails,
                  );
                  final previewMembers = members.take(4).toList();

                  return Column(
                    children: [
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        child: Column(
                          children: [
                            for (var member in previewMembers)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: avatarImageProvider(
                                    member.avatar,
                                    name: member.name,
                                  ),
                                ),
                                title: Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.email,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    _buildOnlineStatusText(
                                      member.lastActive,
                                      isOnline: member.isOnline,
                                    ),
                                  ],
                                ),
                                onTap: () => _showMemberDetailSheet(member),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _RoleBadge(
                                      isLeader: member.isLeader,
                                      isManager: member.isManager,
                                    ),
                                    if (isLeader && !member.isLeader) ...[
                                      const SizedBox(width: 6),
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'role') {
                                            _toggleManagerRole(
                                              member.email,
                                              member.isManager,
                                            );
                                          } else if (value == 'remove') {
                                            _removeMember(member.email);
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            value: 'role',
                                            child: Text(
                                              member.isManager
                                                  ? 'Thu hồi key bạc'
                                                  : 'Cấp key bạc',
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Xóa khỏi nhóm'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            if (members.length > previewMembers.length)
                              ListTile(
                                onTap: () => _showMembersSheet(members),
                                leading: const Icon(Icons.more_horiz),
                                title: Text(
                                  'Còn ${members.length - previewMembers.length} thành viên khác',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              if (isLeader && data['requiresApproval'] == true) ...[
                _buildJoinRequestsSection(),
                const SizedBox(height: 18),
              ],
              _buildGroupActivitySection(),
              const SizedBox(height: 18),
              Card(
                elevation: 0,
                child: Column(
                  children: [
                    if (!isLeader)
                      ListTile(
                        leading: const Icon(Icons.logout),
                        title: const Text('Rời nhóm'),
                        onTap: _leaveGroup,
                      ),
                    if (isLeader)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        title: const Text('Giải tán nhóm'),
                        textColor: Colors.red,
                        onTap: _deleteGroup,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOnlineMembersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Thành viên đang online',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('presence')
              .where('groupId', isEqualTo: widget.groupId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const SizedBox();
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Text(
                'Hiện tại không có ai online trong nhóm.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              );
            }

            return SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Tooltip(
                      message: data['userName'] ?? 'Người dùng',
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: avatarImageProvider(
                              data['userAvatar']?.toString(),
                              name: data['userName']?.toString(),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGroupSettings(Map<String, dynamic> data) {
    final requiresApproval = data['requiresApproval'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cài đặt nhóm',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SwitchListTile(
            title: const Text('Phê duyệt thành viên mới'),
            subtitle: const Text(
              'Yêu cầu trưởng nhóm duyệt khi có người dùng mã gia nhập.',
            ),
            value: requiresApproval,
            onChanged: (val) async {
              final result =
                  await FirebaseService.toggleGroupApprovalRequirement(
                    widget.groupId,
                    val,
                  );
              _showSnack(
                result == 'SUCCESS' ? 'Đã cập nhật cài đặt nhóm' : result,
                success: result == 'SUCCESS',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJoinRequestsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Yêu cầu đang chờ duyệt',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getGroupRequestsForLeaderStream(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const SizedBox();
            final docs = (snapshot.data?.docs ?? []).where((d) {
              final data = d.data();
              return data is Map && data['groupId'] == widget.groupId;
            }).toList();
            if (docs.isEmpty) {
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: const ListTile(
                  title: Text('Không có yêu cầu nào.'),
                  subtitle: Text('Các yêu cầu xin vào nhóm sẽ hiện ở đây.'),
                ),
              );
            }

            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: avatarImageProvider(
                        data['userAvatar'],
                        name: data['userName'],
                      ),
                    ),
                    title: Text(data['userName'] ?? 'Người dùng'),
                    subtitle: Text(data['userEmail'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () =>
                              FirebaseService.respondToGroupRequest(
                                doc.id,
                                true,
                              ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () =>
                              FirebaseService.respondToGroupRequest(
                                doc.id,
                                false,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildGroupActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Lịch sử hoạt động nhóm',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getGroupActivitiesStream(widget.groupId),
          builder: (context, snapshot) {
            if (snapshot.hasError) return const SizedBox();
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: const ListTile(title: Text('Chưa có hoạt động nào.')),
              );
            }

            return Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length > 5 ? 5 : docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final String action = data['action'] ?? '';
                  final String detail = data['detail'] ?? '';
                  final dynamic ts = data['timestamp'];

                  String timeStr = '';
                  if (ts is Timestamp) {
                    final dt = ts.toDate();
                    timeStr =
                        '${dt.hour}:${dt.minute.toString().padLeft(2, '0')} - ${dt.day}/${dt.month}';
                  }

                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(
                      action,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(detail),
                    trailing: Text(
                      timeStr,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  void _showMemberDetailSheet(_MemberViewData member) {
    final colorScheme = Theme.of(context).colorScheme;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final isMe = member.email.toLowerCase().trim() == myEmail;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(32),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                CircleAvatar(
                  radius: 50,
                  backgroundImage: avatarImageProvider(
                    member.avatar,
                    name: member.name,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  member.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  member.email,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                _buildOnlineStatusText(
                  member.lastActive,
                  isDetail: true,
                  isOnline: member.isOnline,
                ),
                const SizedBox(height: 12),
                _RoleBadge(
                  isLeader: member.isLeader,
                  isManager: member.isManager,
                ),
                const SizedBox(height: 32),
                if (!isMe)
                  FutureBuilder<String>(
                    future: FirebaseService.checkFriendshipStatus(member.email),
                    builder: (context, snapshot) {
                      final status = snapshot.data ?? 'LOADING';

                      if (status == 'LOADING') {
                        return const Center(child: CircularProgressIndicator());
                      }

                      String btnText = 'Gửi lời mời kết bạn';
                      IconData btnIcon = Icons.person_add_outlined;
                      bool canClick = true;

                      if (status == 'FRIEND') {
                        btnText = 'Đã là bạn bè';
                        btnIcon = Icons.check_circle_outline;
                        canClick = false;
                      } else if (status == 'PENDING_SENT') {
                        btnText = 'Đã gửi lời mời';
                        btnIcon = Icons.hourglass_empty;
                        canClick = false;
                      } else if (status == 'PENDING_RECEIVED') {
                        btnText = 'Chờ bạn phản hồi';
                        btnIcon = Icons.mail_outline;
                        canClick = false;
                      }

                      return SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: canClick
                              ? () async {
                                  final result =
                                      await FirebaseService.sendFriendRequest(
                                        member.email,
                                      );
                                  if (result == "SUCCESS") {
                                    _showSnack('Đã gửi lời mời kết bạn!');
                                    setSheetState(() {});
                                  } else {
                                    _showSnack(result);
                                  }
                                }
                              : null,
                          icon: Icon(btnIcon),
                          label: Text(btnText),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Đóng'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOnlineStatusText(
    Timestamp? lastActive, {
    bool isDetail = false,
    bool isOnline = false,
  }) {
    if (lastActive == null) return const SizedBox();

    final now = DateTime.now();
    final activeDate = lastActive.toDate();
    final diff = now.difference(activeDate);
    final colorScheme = Theme.of(context).colorScheme;

    if (isOnline && diff.inMinutes < 5) {
      return Text(
        'Đang hoạt động',
        style: TextStyle(
          color: Colors.green,
          fontSize: isDetail ? 14 : 11,
          fontWeight: isDetail ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }

    if (diff.inMinutes < 1) {
      return Text(
        'Vừa mới truy cập',
        style: TextStyle(
          color: Colors.green,
          fontSize: isDetail ? 14 : 11,
          fontWeight: isDetail ? FontWeight.bold : FontWeight.normal,
        ),
      );
    }

    String timeStr;
    if (diff.inMinutes < 60) {
      timeStr = 'Truy cập ${diff.inMinutes} phút trước';
    } else if (diff.inHours < 24) {
      if (activeDate.day == now.day) {
        timeStr = 'Truy cập ${diff.inHours} giờ trước';
      } else {
        timeStr = 'Truy cập hôm qua';
      }
    } else if (diff.inDays == 1) {
      timeStr = 'Truy cập hôm qua';
    } else if (diff.inDays < 7) {
      timeStr = 'Truy cập ${diff.inDays} ngày trước';
    } else {
      timeStr =
          'Truy cập ngày ${activeDate.day}/${activeDate.month}/${activeDate.year}';
    }

    return Text(
      timeStr,
      style: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: isDetail ? 14 : 11,
      ),
    );
  }
}

class _UserViewData {
  final String uid;
  final String name;
  final String avatar;
  final Timestamp? lastActive;
  final bool isOnline;

  const _UserViewData({
    required this.uid,
    required this.name,
    required this.avatar,
    this.lastActive,
    this.isOnline = false,
  });
}

class _MemberViewData {
  final String uid;
  final String email;
  final String name;
  final String avatar;
  final bool isLeader;
  final bool isManager;
  final Timestamp? lastActive;
  final bool isOnline;

  const _MemberViewData({
    required this.uid,
    required this.email,
    required this.name,
    required this.avatar,
    required this.isLeader,
    required this.isManager,
    this.lastActive,
    this.isOnline = false,
  });
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 42) / 2,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: colorScheme.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: onTap == null
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final bool isLeader;
  final bool isManager;

  const _RoleBadge({required this.isLeader, required this.isManager});

  @override
  Widget build(BuildContext context) {
    final color = isLeader
        ? const Color(0xFFC58A00)
        : isManager
        ? const Color(0xFF64748B)
        : Theme.of(context).colorScheme.outline;
    final label = isLeader
        ? 'Key vàng'
        : isManager
        ? 'Key bạc'
        : 'Thành viên';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLeader || isManager ? Icons.key : Icons.person_outline,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditGroupNameDialog extends StatefulWidget {
  final String groupId;
  final String initialName;
  final Function(String) onSuccess;
  final Function(String) onError;

  const _EditGroupNameDialog({
    required this.groupId,
    required this.initialName,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_EditGroupNameDialog> createState() => _EditGroupNameDialogState();
}

class _EditGroupNameDialogState extends State<_EditGroupNameDialog> {
  late TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;
    setState(() => _isSaving = true);

    try {
      final newName = _controller.text.trim();
      final result = await FirebaseService.updateGroupName(
        widget.groupId,
        newName,
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      if (result == "SUCCESS") {
        Navigator.pop(context);
        widget.onSuccess("Đã đổi tên nhóm thành công");
      } else {
        widget.onError(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        widget.onError("Lỗi: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đổi tên nhóm',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                autofocus: true,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Tên nhóm mới',
                  prefixIcon: Icon(Icons.groups_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Tên nhóm không được để trống'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _submit,
                  child: Text(_isSaving ? 'Đang lưu...' : 'Lưu thay đổi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMemberDialog extends StatefulWidget {
  final String groupId;
  final Function(String) onSuccess;
  final Function(String) onError;

  const _AddMemberDialog({
    required this.groupId,
    required this.onSuccess,
    required this.onError,
  });

  @override
  State<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<_AddMemberDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || _formKey.currentState?.validate() != true) return;

    final email = _controller.text.trim();
    setState(() => _isSaving = true);

    try {
      final result = await FirebaseService.addMemberToGroup(
        widget.groupId,
        email,
      );

      if (!mounted) return;
      if (result == "SUCCESS") {
        Navigator.pop(context);
        widget.onSuccess("Đã gửi lời mời vào nhóm cho $email");
      } else {
        setState(() => _isSaving = false);
        widget.onError(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        widget.onError("Lỗi: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Thêm thành viên'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          enabled: !_isSaving,
          decoration: const InputDecoration(
            hintText: 'Nhập email thành viên',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Vui lòng nhập email';
            }
            final email = value.trim();
            if (!email.contains('@') || !email.contains('.')) {
              return 'Email không đúng định dạng';
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Thêm'),
        ),
      ],
    );
  }
}
