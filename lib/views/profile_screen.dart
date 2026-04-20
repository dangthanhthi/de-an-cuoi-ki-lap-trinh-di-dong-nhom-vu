import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../controllers/app_state.dart';
import 'login_screen.dart';
import 'admin_manage_users_screen.dart';
import 'activity_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  // Nâng cấp: Đổi ảnh và lưu thẳng lên Firebase
  void _changeAvatar() async {
    final scaffoldMsg = ScaffoldMessenger.of(context); 

    int randomId = Random().nextInt(70);
    String newAvatar = 'https://i.pravatar.cc/150?img=$randomId';
    
    await FirebaseService.updateUserProfile(avatar: newAvatar);
    AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi ảnh đại diện');
    
    scaffoldMsg.showSnackBar(const SnackBar(content: Text('Đã cập nhật ảnh đại diện!')));
  }

  // Nâng cấp: Chỉnh sửa thông tin và lưu lên Firebase
  void _editProfile(String currentName, String currentEmail) {
    TextEditingController nameCtrl = TextEditingController(text: currentName);
    TextEditingController emailCtrl = TextEditingController(text: currentEmail);
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
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                      enabled: false, 
                  ),
                ]
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(ctx); 
                    final scaffoldMsg = ScaffoldMessenger.of(context);

                    await FirebaseService.updateUserProfile(name: nameCtrl.text);
                    AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi thông tin cá nhân');
                    
                    navigator.pop();
                    scaffoldMsg.showSnackBar(const SnackBar(content: Text('Đã cập nhật thông tin!')));
                  },
                  child: const Text('Lưu thay đổi')
              ),
            ]
        )
    );
  }

  // Hàm xử lý Đăng xuất
  void _handleLogout(BuildContext context) async {
    final navigator = Navigator.of(context);

    AppState.clearAllData(); 
    await FirebaseAuth.instance.signOut(); 
    
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.getUserProfileStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        var userData = snapshot.data?.data() as Map<String, dynamic>?;
        
        String name = userData?['name'] ?? AppState.currentUserName;
        String avatar = userData?['avatar'] ?? AppState.currentUserAvatar;
        String role = userData?['role'] ?? AppState.currentUserRole;
        String email = AppState.currentUserEmail;

        AppState.currentUserName = name;
        AppState.currentUserAvatar = avatar;
        AppState.currentUserRole = role;

        bool isAdmin = role == 'Admin';

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
                          backgroundImage: NetworkImage(avatar), 
                          child: null,
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
                Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), 
                Text(email, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                      color: isAdmin ? Colors.red.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isAdmin ? Colors.red.shade200 : Colors.blue.shade200)
                  ),
                  child: Text(
                      'Vai trò: $role',
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
                        // Đã tháo Danh bạ ở đây!
                        ListTile(
                          leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.person_outline, color: Colors.indigo)),
                          title: const Text('Chỉnh sửa thông tin'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _editProfile(name, email), 
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
                      onTap: () => _handleLogout(context), 
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        );
      }
    );
  }
}