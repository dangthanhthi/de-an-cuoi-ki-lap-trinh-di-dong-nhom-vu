import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../controllers/app_state.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {

  void _showAddFriendDialog() {
    TextEditingController emailCtrl = TextEditingController();
    bool isAdding = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Gửi lời mời kết bạn'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nhập email của người bạn muốn thêm:'),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: InputDecoration(
                    hintText: 'ví dụ: abc@gmail.com',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
              FilledButton(
                onPressed: isAdding ? null : () async {
                  if (emailCtrl.text.isEmpty) return;
                  setDialogState(() => isAdding = true);
                  
                  // Gọi hàm gửi lời mời mới thay vì add trực tiếp
                  String result = await FirebaseService.sendFriendRequest(emailCtrl.text);
                  
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result == "SUCCESS" ? "Đã gửi lời mời thành công! Chờ người kia đồng ý nhé." : result),
                        backgroundColor: result == "SUCCESS" ? Colors.green : Colors.red,
                      )
                    );
                  }
                },
                child: isAdding 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Gửi lời mời'),
              ),
            ],
          );
        }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh bạ của tôi', style: TextStyle(fontWeight: FontWeight.bold))),
      body: Column(
        children: [
          // KHU VỰC 1: LỜI MỜI KẾT BẠN (Chỉ hiện ra nếu có người gửi lời mời)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getFriendRequestsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox(); 
              
              final requests = snapshot.data!.docs;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Lời mời kết bạn (${requests.length})', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold)),
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(), // Để cuộn chung với màn hình chính
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      var reqData = requests[index].data() as Map<String, dynamic>;
                      String reqId = requests[index].id;

                      return ListTile(
                        tileColor: Colors.orange.shade50.withOpacity(0.5),
                        leading: CircleAvatar(backgroundImage: NetworkImage(reqData['fromAvatar'] ?? 'https://ui-avatars.com/api/?background=random')),
                        title: Text(reqData['fromName'] ?? 'Người lạ', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(reqData['from']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green, size: 30),
                              onPressed: () => FirebaseService.acceptFriendRequest(reqId, reqData),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 30),
                              onPressed: () => FirebaseService.rejectFriendRequest(reqId),
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

          // KHU VỰC 2: DANH BẠ CHÍNH CỦA MÌNH
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getContactsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        const Text('Danh bạ trống', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        const Text('Nhấn dấu + để tìm bạn bè nhé!', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                final contacts = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    var contact = contacts[index].data() as Map<String, dynamic>;
                    String docId = contacts[index].id;

                    return ListTile(
                      leading: CircleAvatar(backgroundImage: NetworkImage(contact['avatar'] ?? 'https://ui-avatars.com/api/?background=random')),
                      title: Text(contact['name'] ?? 'Không tên', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(contact['email'] ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.person_remove, color: Colors.redAccent),
                        onPressed: () {
                          FirebaseFirestore.instance.collection('contacts').doc(docId).delete();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã hủy kết bạn')));
                        },
                      ),
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
}