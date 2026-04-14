import 'package:flutter/material.dart';
import 'dart:math';
import '../controllers/app_state.dart';
import 'login_screen.dart';
import 'admin_manage_users_screen.dart';
import 'contacts_screen.dart';
import 'activity_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  void _changeAvatar() {
    setState(() {
      int randomId = Random().nextInt(70);
      AppState.currentUserAvatar = 'https://i.pravatar.cc/150?img=$randomId';
    });
    AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi ảnh đại diện');
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật ảnh đại diện!')));
  }

  void _editProfile() {
    TextEditingController nameCtrl = TextEditingController(text: AppState.currentUserName);
    TextEditingController emailCtrl = TextEditingController(text: AppState.currentUserEmail);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: const Text('Chỉnh sửa thông tin'),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ tên', prefixIcon: Icon(Icons.person_outline))
                  ),
                  const SizedBox(height: 16),
                  TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))
                  ),
                ]
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                  onPressed: () {
                    setState(() {
                      AppState.currentUserName = nameCtrl.text;
                      AppState.currentUserEmail = emailCtrl.text;
                    });
                    AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi thông tin cá nhân');
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật thông tin!')));
                  },
                  child: const Text('Lưu thay đổi')
              ),
            ]
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = AppState.currentUserRole == 'Admin';
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ cá nhân', style: TextStyle(fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: _changeAvatar,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: AppState.currentUserAvatar != null
                          ? NetworkImage(AppState.currentUserAvatar!)
                          : null,
                      child: AppState.currentUserAvatar == null
                          ? Text(AppState.currentUserName[0], style: TextStyle(fontSize: 40, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))
                          : null,
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]
                      ),
                      child: const Icon(Icons.camera_alt, size: 20, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(AppState.currentUserName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(AppState.currentUserEmail, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                  color: isAdmin ? Colors.red.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isAdmin ? Colors.red.shade200 : Colors.blue.shade200)
              ),
              child: Text(
                  'Vai trò: ${AppState.currentUserRole}',
                  style: TextStyle(color: isAdmin ? Colors.red.shade700 : Colors.blue.shade700, fontWeight: FontWeight.bold)
              ),
            ),
            const SizedBox(height: 30),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    if (isAdmin) ...[
                      ListTile(
                        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.admin_panel_settings, color: Colors.red)),
                        title: const Text('Quản lý người dùng', style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminManageUsersScreen()));
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.contacts, color: Colors.green)),
                      title: const Text('Danh bạ của tôi'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ContactsScreen()));
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.person_outline, color: Colors.indigo)),
                      title: const Text('Chỉnh sửa thông tin'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _editProfile,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.history, color: Colors.orange)),
                      title: const Text('Lịch sử hoạt động'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const ActivityHistoryScreen()));
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.settings_outlined, color: Colors.grey)),
                      title: const Text('Cài đặt ứng dụng'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.logout, color: Colors.red)),
                  title: const Text('Đăng xuất', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                  },
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}