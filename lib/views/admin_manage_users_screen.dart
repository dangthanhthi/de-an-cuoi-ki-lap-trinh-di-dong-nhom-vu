import 'package:flutter/material.dart';

class AdminManageUsersScreen extends StatelessWidget {
  const AdminManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> mockUsers = [
      {'name': 'Nguyễn Văn A', 'email': 'nva@gmail.com', 'role': 'User', 'status': 'Active'},
      {'name': 'Trần Thị B', 'email': 'ttb@gmail.com', 'role': 'User', 'status': 'Active'},
      {'name': 'Lê Văn C', 'email': 'lvc@gmail.com', 'role': 'User', 'status': 'Banned'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Quản lý người dùng')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mockUsers.length,
        itemBuilder: (context, index) {
          final user = mockUsers[index];
          bool isBanned = user['status'] == 'Banned';
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isBanned ? Colors.grey : Colors.indigo.shade100,
                child: Icon(Icons.person, color: isBanned ? Colors.white : Colors.indigo),
              ),
              title: Text(user['name']!, style: TextStyle(fontWeight: FontWeight.bold, decoration: isBanned ? TextDecoration.lineThrough : null)),
              subtitle: Text(user['email']!),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã chọn: $value cho ${user['name']}')));
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Sửa quyền')),
                  PopupMenuItem(value: 'ban', child: Text(isBanned ? 'Mở khóa' : 'Khóa tài khoản', style: TextStyle(color: isBanned ? Colors.green : Colors.red))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}