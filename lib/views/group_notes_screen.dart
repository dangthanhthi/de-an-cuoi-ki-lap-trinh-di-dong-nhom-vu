import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import 'note_detail_screen.dart';
import 'create_edit_note_screen.dart';

class GroupNotesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupNotesScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupNotesScreen> createState() => _GroupNotesScreenState();
}

class _GroupNotesScreenState extends State<GroupNotesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal.shade100,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getGroupNotesStream(widget.groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.speaker_notes_off, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('Nhóm chưa có ghi chú nào', style: TextStyle(color: Colors.grey)),
                  const Text('Bấm Tạo Note Nhóm để bắt đầu làm việc!', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          
          List<Note> groupNotes = docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            List<TodoItem> todos = [];
            if (data['todos'] != null) {
              todos = (data['todos'] as List).map((t) => TodoItem(task: t['task'], isDone: t['isDone'])).toList();
            }
            return Note(
              id: doc.id, 
              title: data['title'] ?? 'Không tiêu đề',
              content: data['content'] ?? '',
              label: data['label'] ?? 'Work',
              date: data['date']?.substring(0, 10) ?? '',
              isTodo: data['isTodo'] ?? false,
              todos: todos,
              sharedWith: [], 
              coverColor: data['color'] != null ? Color(data['color']) : Colors.teal.shade100, 
            );
          }).toList();

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupNotes.length,
            itemBuilder: (context, index) {
              final note = groupNotes[index];
              double progress = 0;
              if (note.isTodo && note.todos.isNotEmpty) {
                progress = note.todos.where((t) => t.isDone).length / note.todos.length;
              }

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  // Bấm vào thì mở xem chi tiết và sửa Note
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NoteDetailScreen(note: note))),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 4, height: 50, decoration: BoxDecoration(color: note.coverColor, borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(note.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 6),
                              if (note.isTodo) ...[
                                Row(
                                  children: [
                                    Expanded(child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, color: note.coverColor)),
                                    const SizedBox(width: 8),
                                    Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ] else ...[
                                Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        onPressed: () async {
          // 1. Cắm cờ báo hiệu "Đang ở trong nhóm"
          FirebaseService.currentGroupId = widget.groupId;
          
          // 2. Mở màn hình tạo note (Lúc này hàm addNote sẽ tự bắt được cờ Nhóm)
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEditNoteScreen()));
          
          // 3. Tắt cờ khi tạo xong quay về
          FirebaseService.currentGroupId = "";
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tạo Note Nhóm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}