import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  void _addEditContact([Contact? contact]) {
    TextEditingController nameCtrl = TextEditingController(text: contact?.name ?? '');
    TextEditingController emailCtrl = TextEditingController(text: contact?.email ?? '');

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
            title: Text(contact == null ? 'Thêm liên hệ' : 'Sửa liên hệ'),
            content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')),
                  TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
                ]
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              FilledButton(
                  onPressed: () {
                    if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty) return;
                    setState(() {
                      if (contact == null) {
                        AppState.contacts.add(Contact(id: DateTime.now().toString(), name: nameCtrl.text, email: emailCtrl.text));
                        AppState.logActivity('Thêm danh bạ', 'Đã thêm ${nameCtrl.text}');
                      } else {
                        contact.name = nameCtrl.text;
                        contact.email = emailCtrl.text;
                        AppState.logActivity('Sửa danh bạ', 'Đã sửa thông tin của ${nameCtrl.text}');
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Lưu')
              )
            ]
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Danh bạ của tôi')),
      body: AppState.contacts.isEmpty
          ? const Center(child: Text('Danh bạ trống', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: AppState.contacts.length,
        itemBuilder: (context, index) {
          final c = AppState.contacts[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Text(c.name[0], style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold))),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(c.email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _addEditContact(c)),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() => AppState.contacts.removeAt(index));
                      AppState.logActivity('Xóa danh bạ', 'Đã xóa ${c.name}');
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addEditContact(),
        icon: const Icon(Icons.add),
        label: const Text('Thêm liên hệ'),
      ),
    );
  }
}