import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../utils/media_utils.dart';

class AdminManageUsersScreen extends StatefulWidget {
  const AdminManageUsersScreen({super.key});

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen> {
  String _searchQuery = '';

  void _showMessage(String message, {bool success = true}) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : colorScheme.error,
      ),
    );
  }

  Future<void> _confirmRoleChange({
    required String uid,
    required bool isAdmin,
    required String email,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAdmin ? 'Hạ quyền Admin?' : 'Cấp quyền Admin?'),
        content: Text(
          isAdmin
              ? 'Bạn có chắc muốn hạ quyền $email xuống User không?'
              : 'Bạn có chắc muốn cấp quyền Admin cho $email không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final result = await FirebaseService.changeUserRole(
                uid,
                isAdmin ? 'User' : 'Admin',
              );
              if (!mounted) return;
              navigator.pop();
              if (result == 'SUCCESS') {
                _showMessage(
                  isAdmin
                      ? 'Đã hạ quyền tài khoản xuống User'
                      : 'Đã cấp quyền Admin',
                );
              } else {
                _showMessage(result, success: false);
              }
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBan({required String uid, required bool isBanned}) async {
    final result = await FirebaseService.toggleUserBan(uid, isBanned);
    if (!mounted) return;
    if (result == 'SUCCESS') {
      _showMessage(
        isBanned ? 'Đã mở khóa tài khoản' : 'Đã khóa tài khoản',
      );
    } else {
      _showMessage(result, success: false);
    }
  }

  Future<void> _confirmDeleteUser({
    required String uid,
    required String email,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: Text(
          'Bạn có chắc muốn xóa tài khoản $email khỏi hệ thống không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final result = await FirebaseService.deleteUserAccountByAdmin(uid);
              if (!mounted) return;
              navigator.pop();
              if (result == 'SUCCESS') {
                _showMessage('Đã xóa tài khoản khỏi hệ thống');
              } else {
                _showMessage(result, success: false);
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) return 'Chưa có';
    final date = value.toDate();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showUserDetails({
    required String uid,
    required Map<String, dynamic> userData,
    required bool isAdmin,
    required bool isBanned,
    required bool isDeleted,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2), width: 2),
                ),
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: avatarImageProvider(
                    userData['avatar']?.toString(),
                    name: userData['name']?.toString(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                (userData['name'] ?? 'Không tên').toString(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (userData['email'] ?? 'Không có email').toString(),
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: isAdmin ? Icons.security : Icons.person_outline,
                        label: 'Vai trò',
                        value: isAdmin ? 'Quản trị viên (Admin)' : 'Người dùng (User)',
                        iconColor: isAdmin ? colorScheme.primary : null,
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1)),
                      _DetailRow(
                        icon: isDeleted ? Icons.delete_forever : (isBanned ? Icons.lock_outline : Icons.check_circle_outline),
                        label: 'Trạng thái',
                        value: isDeleted ? 'Đã xóa' : (isBanned ? 'Đã khóa' : 'Đang hoạt động'),
                        iconColor: isDeleted || isBanned ? Colors.red : Colors.green,
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1)),
                      _DetailRow(
                        icon: Icons.fingerprint,
                        label: 'Mã định danh (UID)',
                        value: uid,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.history,
                        label: 'Cập nhật gần nhất',
                        value: _formatTimestamp(userData['updatedAt'] ?? userData['lastUpdated']),
                      ),
                      if (isDeleted) ...[
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1)),
                        _DetailRow(
                          icon: Icons.delete_outline,
                          label: 'Thời gian xóa',
                          value: _formatTimestamp(userData['deletedAt']),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final mutedText = colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý người dùng',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm người dùng...',
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
              stream: FirebaseService.getAllUsersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Chưa có người dùng nào trên hệ thống.'),
                  );
                }

                final query = _searchQuery.toLowerCase().trim();
                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final role = (data['role'] ?? '').toString().toLowerCase();
                  return query.isEmpty ||
                      name.contains(query) ||
                      email.contains(query) ||
                      role.contains(query);
                }).toList();

                // Sắp xếp danh sách theo email để dễ tìm kiếm
                users.sort((a, b) {
                  final emailA = ((a.data() as Map<String, dynamic>)['email'] ?? '').toString().toLowerCase();
                  final emailB = ((b.data() as Map<String, dynamic>)['email'] ?? '').toString().toLowerCase();
                  return emailA.compareTo(emailB);
                });

                if (users.isEmpty) {
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
                          'Không tìm thấy người dùng phù hợp',
                          style: TextStyle(color: mutedText),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final userDoc = users[index];
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final uid = userDoc.id;
                    final isDeleted = userData['isDeleted'] == true;
                    final isBanned = userData['isBanned'] == true;
                    final role = (userData['role'] ?? 'User').toString();
                    final isAdmin = role == 'Admin';
                    final rawEmail = userData['email']?.toString() ?? '';
                    final email = rawEmail.trim().isNotEmpty ? rawEmail : 'ID: ${uid.substring(0, 8)}...';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isDeleted || isBanned
                              ? colorScheme.error.withValues(alpha: 0.4)
                              : colorScheme.outlineVariant,
                          width: 2,
                        ),
                      ),
                      color: isDeleted
                          ? colorScheme.errorContainer.withValues(alpha: 0.42)
                          : isBanned
                          ? colorScheme.errorContainer.withValues(alpha: 0.32)
                          : colorScheme.surfaceContainerLow,
                      child: ListTile(
                        onTap: () => _showUserDetails(
                          uid: uid,
                          userData: userData,
                          isAdmin: isAdmin,
                          isBanned: isBanned,
                          isDeleted: isDeleted,
                        ),
                        leading: CircleAvatar(
                          backgroundImage: avatarImageProvider(
                            userData['avatar']?.toString(),
                            name: userData['name']?.toString(),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (userData['name'] ?? 'Không tên').toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  decoration: isDeleted || isBanned
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Admin',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          email,
                          style: TextStyle(fontSize: 12, color: mutedText),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'role') {
                              _confirmRoleChange(uid: uid, isAdmin: isAdmin, email: email);
                            } else if (value == 'delete') {
                              _confirmDeleteUser(uid: uid, email: email);
                            } else if (value == 'toggle') {
                              _toggleBan(uid: uid, isBanned: isBanned);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'toggle',
                              enabled: !isDeleted && !(isAdmin && uid == FirebaseService.currentUid),
                              child: ListTile(
                                leading: Icon(
                                  isBanned ? Icons.check_circle_outline : Icons.block,
                                  color: isBanned ? Colors.green : Colors.red,
                                ),
                                title: Text(isBanned ? 'Mở khóa' : 'Khóa tài khoản'),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                            if (!isDeleted && isAdmin && uid != FirebaseService.currentUid)
                              PopupMenuItem(
                                value: 'role',
                                child: ListTile(
                                  leading: Icon(
                                    Icons.security_outlined,
                                    color: colorScheme.primary,
                                  ),
                                  title: const Text('Hạ quyền Admin'),
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                ),
                              ),
                            PopupMenuItem(
                              value: 'delete',
                              enabled: !isDeleted,
                              child: const ListTile(
                                leading: Icon(Icons.delete_outline, color: Colors.red),
                                title: Text('Xóa tài khoản'),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          ],
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

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      leading: Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.primary, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      subtitle: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }
}




