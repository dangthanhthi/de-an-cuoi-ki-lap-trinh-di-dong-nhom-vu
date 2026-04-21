import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import 'create_edit_note_screen.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  const NoteDetailScreen({super.key, required this.note});
  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {

  void _deleteNote() async {
    final navigator = Navigator.of(context);
    final scaffoldMsg = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance.collection('notes').doc(widget.note.id).delete();
      AppState.logActivity('Xóa ghi chú', 'Đã xóa ghi chú: "${widget.note.title}"');

      navigator.pop();
      scaffoldMsg.showSnackBar(const SnackBar(content: Text('Đã xóa ghi chú thành công')));
    } catch (e) {
      scaffoldMsg.showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
    }
  }

  void _shareNote() async {
    final contactsSnapshot = await FirebaseFirestore.instance
        .collection('contacts')
        .where('userId', isEqualTo: FirebaseService.currentUid)
        .get();
    List<Map<String, dynamic>> myFriends = contactsSnapshot.docs.map((doc) => doc.data()).toList();

    if (!mounted) return;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          String email = '';
          List<String> selectedContacts = [];

          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                      left: 24, right: 24, top: 24
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Chia sẻ ghi chú', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),

                        TextField(
                          onChanged: (val) => email = val.trim(),
                          decoration: InputDecoration(
                            hintText: 'Nhập tay email người nhận...',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        const Text('Hoặc chọn từ danh bạ:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                        const SizedBox(height: 8),
                        myFriends.isEmpty
                            ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('Bạn chưa có ai trong danh bạ. Hãy vào mục Danh bạ để kết bạn nhé!', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                        )
                            : Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: myFriends.length,
                            itemBuilder: (context, index) {
                              final friend = myFriends[index];
                              final friendEmail = friend['email'];
                              final isSelected = selectedContacts.contains(friendEmail);
                              final alreadyShared = widget.note.sharedWith.contains(friendEmail);

<<<<<<< Updated upstream
                                    return CheckboxListTile(
                                      value: alreadyShared ? true : isSelected, // Đã share rồi thì tự động tick cứng
                                      enabled: !alreadyShared, // Đã share rồi thì không cho bấm bỏ tick ở đây
                                      title: Text(friend['name'] ?? 'Bạn bè', style: TextStyle(color: alreadyShared ? Colors.grey : Colors.black)),
                                      subtitle: Text(friendEmail, style: TextStyle(fontSize: 12, color: alreadyShared ? Colors.grey : Colors.black54)),
                                      secondary: CircleAvatar(backgroundImage: NetworkImage(friend['avatar'] ?? 'https://ui-avatars.com/api/?background=random')),
                                      onChanged: (bool? val) {
                                        setModalState(() {
                                          if (val == true) {
                                            selectedContacts.add(friendEmail);
                                          } else {
                                            selectedContacts.remove(friendEmail);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
=======
                              return CheckboxListTile(
                                value: alreadyShared ? true : isSelected,
                                enabled: !alreadyShared,
                                title: Text(friend['name'] ?? 'Bạn bè', style: TextStyle(color: alreadyShared ? Colors.grey : Colors.black)),
                                subtitle: Text(friendEmail, style: TextStyle(fontSize: 12, color: alreadyShared ? Colors.grey : Colors.black54)),
                                secondary: CircleAvatar(backgroundImage: NetworkImage(friend['avatar'] ?? 'https://ui-avatars.com/api/?background=random')),
                                onChanged: (bool? val) {
                                  setModalState(() {
                                    if (val == true) selectedContacts.add(friendEmail);
                                    else selectedContacts.remove(friendEmail);
                                  });
                                },
                              );
                            },
                          ),
                        ),
>>>>>>> Stashed changes
                        const SizedBox(height: 16),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () async {
                              List<String> finalEmails = [...selectedContacts];
                              String typedEmail = email.toLowerCase();

                              if (typedEmail.isNotEmpty && !finalEmails.contains(typedEmail)) {
                                final checkUser = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: typedEmail).get();
                                if (checkUser.docs.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: Tài khoản "$typedEmail" không tồn tại!'), backgroundColor: Colors.red));
                                  return;
                                }
                                finalEmails.add(typedEmail);
                              }

                              finalEmails.removeWhere((e) => widget.note.sharedWith.contains(e));

                              if (finalEmails.isNotEmpty) {
                                final navigator = Navigator.of(context);
                                final scaffoldMsg = ScaffoldMessenger.of(context);

                                for (String targetEmail in finalEmails) {
                                  await FirebaseService.shareNote(widget.note.id, targetEmail);
                                }

                                setState(() {
                                  widget.note.sharedWith = [...widget.note.sharedWith, ...finalEmails].toSet().toList();
                                });
                                navigator.pop();
                                scaffoldMsg.showSnackBar(SnackBar(content: Text('Đã chia sẻ thành công với ${finalEmails.length} người')));
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                            child: const Text('Chia sẻ ngay'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                );
              }
          );
        }
    );
  }

  void _summarizeAI() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("AI đang đọc ghi chú..."),
            ],
          ),
        )
    );
    await Future.delayed(const Duration(seconds: 2));
    if(mounted) Navigator.pop(context);

    String summary = "";
    if (widget.note.isTodo) {
      int done = widget.note.todos.where((t) => t.isDone).length;
      int total = widget.note.todos.length;
      summary = 'Bạn có một danh sách công việc gồm $total mục. Hiện tại đã hoàn thành $done mục. Cố lên nhé!';
    } else {
      summary = 'Ghi chú "${widget.note.title}" đề cập đến các thông tin thuộc nhóm [${widget.note.label}]. Nội dung chính tập trung vào việc ghi chép và lên kế hoạch.';
    }

    if(mounted) {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(children: [Icon(Icons.auto_awesome, color: Colors.orange), SizedBox(width: 8), Text('AI Tóm tắt')]),
            content: Text(summary),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))],
          )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String myEmail = AppState.currentUserEmail.toLowerCase().trim();
    bool isSharedWithMe = widget.note.sharedWith.any((e) => e.toLowerCase().trim() == myEmail);
    Color activeColor = isSharedWithMe ? Colors.red : widget.note.coverColor;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: activeColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Center(child: Icon(widget.note.isTodo ? Icons.check_box : Icons.edit_document, size: 80, color: Colors.white.withOpacity(0.5))),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.auto_awesome, color: Colors.white), tooltip: 'Tóm tắt AI', onPressed: _summarizeAI),
              IconButton(icon: const Icon(Icons.share, color: Colors.white), tooltip: 'Chia sẻ', onPressed: _shareNote),
              IconButton(icon: const Icon(Icons.edit, color: Colors.white), tooltip: 'Sửa', onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => CreateEditNoteScreen(note: widget.note)));
                setState(() {});
              }),
              IconButton(icon: const Icon(Icons.delete, color: Colors.white), tooltip: 'Xóa', onPressed: _deleteNote),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              transform: Matrix4.translationValues(0.0, -24.0, 0.0),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: activeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(widget.note.label, style: TextStyle(color: activeColor, fontWeight: FontWeight.bold)),
                      ),
                      Text(widget.note.date, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(widget.note.title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: isSharedWithMe ? Colors.red.shade700 : Colors.black)),
                      ),
                      if (isSharedWithMe)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                          child: Text('Được chia sẻ', style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                        )
                    ],
                  ),
                  if (widget.note.sharedWith.isNotEmpty && !isSharedWithMe) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2.0),
                          child: Icon(Icons.group, size: 16, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Đã chia sẻ với: ${widget.note.sharedWith.join(", ")}',
                              style: const TextStyle(color: Colors.grey)
                          ),
                        ),
                      ],
                    )
                  ],
                  const Divider(height: 40),

                  // --- HIỂN THỊ NHẮC NHỞ NẾU CÓ ---
                  if (widget.note.hasReminder && widget.note.reminderTime != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text('Đã hẹn giờ: ${widget.note.reminderTime!.hour.toString().padLeft(2, '0')}:${widget.note.reminderTime!.minute.toString().padLeft(2, '0')} - ${widget.note.reminderTime!.day}/${widget.note.reminderTime!.month}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),

                  // --- HIỂN THỊ FILE ĐÍNH KÈM NẾU CÓ ---
                  if (widget.note.attachments.isNotEmpty) ...[
                    const Text('Tệp đính kèm:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.note.attachments.map((url) => Chip(
                        avatar: const Icon(Icons.attach_file, size: 16),
                        label: const Text('Tệp đính kèm', style: TextStyle(fontSize: 12)),
                        backgroundColor: Colors.grey.shade100,
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.note.isTodo)
                    ...widget.note.todos.map((todo) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(todo.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: todo.isDone ? activeColor : Colors.grey),
                      title: Text(todo.task, style: TextStyle(fontSize: 16, decoration: todo.isDone ? TextDecoration.lineThrough : null, color: todo.isDone ? Colors.grey : Colors.black)),
                      onTap: () => setState(() => todo.isDone = !todo.isDone),
                    ))
                  else
                    Text(widget.note.content, style: const TextStyle(fontSize: 16, height: 1.6)),

                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}