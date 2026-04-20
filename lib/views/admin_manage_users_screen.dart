import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/app_state.dart';

class AdminManageUsersScreen extends StatefulWidget {
  const AdminManageUsersScreen({super.key});

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý người dùng', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getAllUsersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Chưa có người dùng nào trên hệ thống.'));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final userData = userDoc.data() as Map<String, dynamic>;
              final String uid = userDoc.id;
              
              // Nếu là chính Admin đang đăng nhập thì ẩn đi, không cho tự khóa mình
              if (uid == FirebaseService.currentUid) return const SizedBox();

              final bool isBanned = userData['isBanned'] ?? false;
              final String role = userData['role'] ?? 'User';

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isBanned ? Colors.red.shade300 : Colors.transparent, width: 2)
                ),
                color: isBanned ? Colors.red.shade50 : Colors.white,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(userData['avatar'] ?? 'https://ui-avatars.com/api/?background=random'),
                  ),
                  title: Row(
                    children: [
                      Text(userData['name'] ?? 'Không tên', style: TextStyle(fontWeight: FontWeight.bold, decoration: isBanned ? TextDecoration.lineThrough : null)),
                      const SizedBox(width: 8),
                      if (role == 'Admin')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(4)),
                          child: const Text('Admin', style: TextStyle(color: Colors.white, fontSize: 10)),
                        )
                    ],
                  ),
                  subtitle: Text(userData['email'] ?? 'Không có email', style: const TextStyle(fontSize: 12)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(isBanned ? 'BỊ KHÓA' : 'HOẠT ĐỘNG', style: TextStyle(color: isBanned ? Colors.red : Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                      Switch(
                        value: !isBanned, // Nếu bật (True) tức là đang hoạt động bình thường
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                        inactiveTrackColor: Colors.red.shade200,
                        onChanged: (val) {
                          FirebaseService.toggleUserBan(uid, isBanned);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(val ? "Đã mở khóa tài khoản!" : "Đã khóa tài khoản này!"),
                              backgroundColor: val ? Colors.green : Colors.red,
                            )
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
      ),
    );
  }
}