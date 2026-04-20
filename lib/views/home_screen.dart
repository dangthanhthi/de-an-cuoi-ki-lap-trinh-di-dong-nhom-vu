import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import 'note_detail_screen.dart';
import 'create_edit_note_screen.dart';
import 'groups_list_screen.dart';
import 'contacts_screen.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedLabel = 'Tất cả';
  String _searchQuery = '';
  String _viewMode = 'ALL'; 

  @override
  Widget build(BuildContext context) {
    // STREAM BÁO LỜI MỜI KẾT BẠN
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.getFriendRequestsStream(),
      builder: (context, requestSnap) {
        
        int requestCount = 0;
        if (requestSnap.hasData) {
          requestCount = requestSnap.data!.docs.length;
        }
        bool hasRequests = requestCount > 0;

        return Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (context) => IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.menu),
                    if (hasRequests)
                      Positioned(
                        right: -2, top: -2,
                        child: Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                        ),
                      )
                  ],
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: Text(_viewMode == 'SHARED' ? 'Được chia sẻ với tôi' : 'Ghi chú của tôi', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          drawer: _buildDrawer(requestCount), 
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm ghi chú...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: ['Tất cả', ...AppState.labels].map((label) {
                    bool isSelected = _selectedLabel == label;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedLabel = label);
                        },
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                        checkmarkColor: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  }).toList(),
                ),
              ),

              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _viewMode == 'SHARED' 
                      ? FirebaseService.getSharedNotesStream() 
                      : FirebaseService.getMyNotesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Lỗi tải dữ liệu: ${snapshot.error}'));
                    }

                    final docs = snapshot.data?.docs ?? [];
                    
                    List<Note> allNotes = docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      
                      List<TodoItem> todos = [];
                      if (data['todos'] != null) {
                        todos = (data['todos'] as List).map((t) => TodoItem(task: t['task'], isDone: t['isDone'])).toList();
                      }

                      List<String> sharedWithList = [];
                      if (data['sharedWith'] != null) {
                        sharedWithList = List<String>.from(data['sharedWith']);
                      }
                      
                      return Note(
                        id: doc.id, 
                        title: data['title'] ?? 'Không tiêu đề',
                        content: data['content'] ?? '',
                        label: data['label'] ?? 'Work',
                        date: data['date']?.substring(0, 10) ?? 'Không rõ',
                        isTodo: data['isTodo'] ?? false,
                        todos: todos,
                        sharedWith: sharedWithList, 
                        coverColor: data['color'] != null ? Color(data['color']) : Colors.blue.shade100, 
                      );
                    }).toList();

                    List<Note> filteredNotes = allNotes.where((n) {
                      bool matchLabel = _selectedLabel == 'Tất cả' || n.label == _selectedLabel;
                      bool matchSearch = n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                          n.content.toLowerCase().contains(_searchQuery.toLowerCase());
                      
                      return matchLabel && matchSearch; 
                    }).toList();

                    if (filteredNotes.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(_viewMode == 'SHARED' ? 'Chưa có ai chia sẻ ghi chú cho bạn' : 'Chưa có ghi chú nào', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      itemCount: filteredNotes.length,
                      itemBuilder: (context, index) {
                        final note = filteredNotes[index];
                        double progress = 0;
                        if (note.isTodo && note.todos.isNotEmpty) {
                          progress = note.todos.where((t) => t.isDone).length / note.todos.length;
                        }

                        bool isSharedWithMe = _viewMode == 'SHARED'; 
                        Color cardColor = isSharedWithMe ? Colors.red.shade50 : Colors.white;
                        Color accentColor = isSharedWithMe ? Colors.red : note.coverColor;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: isSharedWithMe ? Colors.red.shade200 : Colors.grey.shade200),
                          ),
                          color: cardColor,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailScreen(note: note)));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 4, height: 50,
                                    decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(child: Text(note.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSharedWithMe ? Colors.red.shade900 : Colors.black))),
                                            if (isSharedWithMe) 
                                              Icon(Icons.group, size: 16, color: Colors.red.shade400)
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        if (note.isTodo) ...[
                                          Row(
                                            children: [
                                              Expanded(child: LinearProgressIndicator(value: progress, backgroundColor: Colors.grey.shade200, color: accentColor, borderRadius: BorderRadius.circular(4))),
                                              const SizedBox(width: 8),
                                              Text('${(progress * 100).toInt()}%', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                            ],
                                          ),
                                        ] else ...[
                                          Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                                        ],
                                        const SizedBox(height: 12),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(color: isSharedWithMe ? Colors.white : Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                              child: Text(note.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                                            ),
                                            Text(note.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        )
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
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEditNoteScreen()));
            },
            icon: const Icon(Icons.add),
            label: const Text('Tạo mới'),
          ),
        );
      }
    );
  }

  // --- MENU TRƯỢT ---
  Widget _buildDrawer(int requestCount) {
    bool hasRequests = requestCount > 0;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            accountName: Text(AppState.currentUserName, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(AppState.currentUserEmail),
            currentAccountPicture: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: NetworkImage(AppState.currentUserAvatar),
                  radius: 36,
                ),
                if (hasRequests)
                  Positioned(
                    right: 0, top: 0,
                    child: Container(
                      width: 14, height: 14,
                      decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                    ),
                  )
              ],
            ),
          ),
          ListTile(
              leading: const Icon(Icons.note),
              title: Text('Ghi chú của tôi', style: TextStyle(fontWeight: _viewMode == 'ALL' ? FontWeight.bold : FontWeight.normal, color: _viewMode == 'ALL' ? Colors.indigo : Colors.black)),
              onTap: () {
                setState(() => _viewMode = 'ALL');
                Navigator.pop(context); 
              }
          ),
          const Divider(),
          
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getSharedNotesStream(),
            builder: (context, snapshot) {
              int sharedCount = 0;
              if (snapshot.hasData) {
                sharedCount = snapshot.data!.docs.length;
              }
              bool hasShared = sharedCount > 0;

              return ListTile(
                  leading: const Icon(Icons.group, color: Colors.red),
                  title: Text('Được chia sẻ với tôi', style: TextStyle(fontWeight: _viewMode == 'SHARED' ? FontWeight.bold : FontWeight.normal, color: _viewMode == 'SHARED' ? Colors.red : Colors.black)),
                  // Hiện Badge đỏ báo số lượng
                  trailing: hasShared 
                    ? Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: Text('$sharedCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    : null,
                  onTap: () {
                    setState(() => _viewMode = 'SHARED'); 
                    Navigator.pop(context); 
                  }
              );
            }
          ),
          
          const Divider(),
          ListTile(
            leading: const Icon(Icons.group_work, color: Colors.teal),
            title: const Text('Nhóm của tôi'),
            onTap: () {
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const GroupsListScreen()));
            },
          ),
          const Divider(),
          
          ListTile(
            leading: const Icon(Icons.contacts, color: Colors.blue),
            title: const Text('Danh bạ của tôi'),
            trailing: hasRequests 
              ? Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                  child: Text('$requestCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                )
              : null,
            onTap: () {
              Navigator.pop(context); 
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ContactsScreen()));
            },
          ),
        ],
      ),
    );
  }
}