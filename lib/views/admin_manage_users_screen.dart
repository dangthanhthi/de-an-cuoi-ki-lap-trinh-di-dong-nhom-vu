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
        title: const Text('Quan ly nguoi dung', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo.shade100,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getAllUsersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Chua co nguoi dung nao tren he thong.'));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final userData = userDoc.data() as Map<String, dynamic>;
              final String uid = userDoc.id;

              if (uid == FirebaseService.currentUid) return const SizedBox();

              final bool isBanned = userData['isBanned'] ?? false;
              final String role = userData['role'] ?? 'User';
              final bool isAdmin = role == 'Admin';

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
                      Expanded(
                        child: Text(
                          userData['name'] ?? 'Khong ten',
                          style: TextStyle(fontWeight: FontWeight.bold, decoration: isBanned ? TextDecoration.lineThrough : null),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isAdmin)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.indigo, borderRadius: BorderRadius.circular(4)),
                          child: const Text('Admin', style: TextStyle(color: Colors.white, fontSize: 10)),
                        )
                    ],
                  ),
                  subtitle: Text(
                    userData['email'] ?? 'Khong co email',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isAdmin ? Icons.security : Icons.security_outlined,
                          color: isAdmin ? Colors.indigo : Colors.grey,
                        ),
                        tooltip: isAdmin ? 'Huy quyen Admin' : 'Cap quyen Admin',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(isAdmin ? 'Huy quyen Admin?' : 'Cap quyen Admin?'),
                              content: Text(isAdmin
                                  ? 'Ban co chac muon ha cap tai khoan nay xuong User?'
                                  : 'Ban co chac muon nang cap tai khoan nay thanh Admin?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huy')),
                                FilledButton(
                                  onPressed: () {
                                    FirebaseService.changeUserRole(uid, isAdmin ? 'User' : 'Admin');
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(isAdmin ? 'Da ha cap xuong User' : 'Da nang cap thanh Admin'))
                                    );
                                  },
                                  child: const Text('Xac nhan'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Text(
                          isAdmin ? 'ADMIN' : (isBanned ? 'BI KHOA' : 'HOAT DONG'),
                          style: TextStyle(color: isAdmin ? Colors.indigo : (isBanned ? Colors.red : Colors.green), fontSize: 10, fontWeight: FontWeight.bold)
                      ),
                      Switch(
                        value: !isBanned,
                        activeColor: Colors.green,
                        inactiveThumbColor: Colors.red,
                        inactiveTrackColor: Colors.red.shade200,
                        onChanged: isAdmin ? null : (val) {
                          FirebaseService.toggleUserBan(uid, isBanned);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(val ? "Da mo khoa tai khoan!" : "Da khoa tai khoan nay!"),
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