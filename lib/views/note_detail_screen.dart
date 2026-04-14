import 'package:flutter/material.dart';
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
  void _deleteNote() {
    AppState.notes.removeWhere((n) => n.id == widget.note.id);
    AppState.logActivity('Xóa ghi chú', 'Đã xóa ghi chú: "${widget.note.title}"');
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa ghi chú')));
  }

  void _shareNote() {
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
                          onChanged: (val) => email = val,
                          decoration: InputDecoration(
                            hintText: 'Nhập email người nhận',
                            prefixIcon: const Icon(Icons.email_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Hoặc chọn từ danh bạ:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: AppState.contacts.length,
                            itemBuilder: (context, index) {
                              final contact = AppState.contacts[index];
                              final isSelected = selectedContacts.contains(contact.email);
                              return CheckboxListTile(
                                value: isSelected,
                                title: Text(contact.name),
                                subtitle: Text(contact.email, style: const TextStyle(fontSize: 12)),
                                onChanged: (bool? val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedContacts.add(contact.email);
                                    } else {
                                      selectedContacts.remove(contact.email);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              List<String> finalEmails = [...selectedContacts];
                              if (email.isNotEmpty && !finalEmails.contains(email)) {
                                finalEmails.add(email);
                              }

                              if(finalEmails.isNotEmpty) {
                                setState(() {
                                  widget.note.sharedWith.addAll(finalEmails);
                                  widget.note.sharedWith = widget.note.sharedWith.toSet().toList(); // Xóa trùng lặp
                                });
                                AppState.logActivity('Chia sẻ ghi chú', 'Đã chia sẻ "${widget.note.title}" với ${finalEmails.join(", ")}');
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã chia sẻ với ${finalEmails.join(", ")}')));
                              }
                            },
                            child: const Text('Gửi lời mời'),
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
    bool isSharedWithMe = widget.note.sharedWith.contains(AppState.currentUserEmail);
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
                      children: [
                        const Icon(Icons.group, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text('Đã chia sẻ với: ${widget.note.sharedWith.join(", ")}', style: const TextStyle(color: Colors.grey)),
                      ],
                    )
                  ],
                  const Divider(height: 40),
                  if (widget.note.isTodo)
                    ...widget.note.todos.map((todo) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(todo.isDone ? Icons.check_circle : Icons.radio_button_unchecked, color: todo.isDone ? activeColor : Colors.grey),
                      title: Text(todo.task, style: TextStyle(fontSize: 16, decoration: todo.isDone ? TextDecoration.lineThrough : null, color: todo.isDone ? Colors.grey : Colors.black)),
                      onTap: () => setState(() => todo.isDone = !todo.isDone),
                    )).toList()
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