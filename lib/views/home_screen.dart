import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../controllers/app_state.dart';
import 'note_detail_screen.dart';
import 'create_edit_note_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedLabel = 'Tất cả';
  String _searchQuery = '';
  String _viewMode = 'ALL';

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    List<Note> filteredNotes = AppState.notes.where((n) {
      bool matchLabel = _selectedLabel == 'Tất cả' || n.label == _selectedLabel;
      bool matchSearch = n.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          n.content.toLowerCase().contains(_searchQuery.toLowerCase());

      if (_viewMode == 'SHARED') {
        return matchLabel && matchSearch && n.sharedWith.contains(AppState.currentUserEmail);
      }
      return matchLabel && matchSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_viewMode == 'SHARED' ? 'Được chia sẻ với tôi' : 'Ghi chú của tôi', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      drawer: _buildDrawer(),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
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
            child: filteredNotes.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text('Không tìm thấy ghi chú nào', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: filteredNotes.length,
              itemBuilder: (context, index) {
                final note = filteredNotes[index];
                double progress = 0;
                if (note.isTodo && note.todos.isNotEmpty) {
                  progress = note.todos.where((t) => t.isDone).length / note.todos.length;
                }

                bool isSharedWithMe = note.sharedWith.contains(AppState.currentUserEmail);
                Color activeColor = isSharedWithMe ? Colors.red : note.coverColor;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: isSharedWithMe ? 2 : 0,
                  shadowColor: isSharedWithMe ? Colors.red.withOpacity(0.3) : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isSharedWithMe ? Colors.red.shade300 : Colors.grey.shade200),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailScreen(note: note)));
                      _refresh();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: 50,
                            decoration: BoxDecoration(
                              color: activeColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                        child: Text(
                                            note.title,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSharedWithMe ? Colors.red.shade700 : Colors.black)
                                        )
                                    ),
                                    if (isSharedWithMe)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                                        child: Text('Được chia sẻ', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                                      )
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (note.isTodo) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.grey.shade200,
                                          color: activeColor,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
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
                                      decoration: BoxDecoration(
                                          color: isSharedWithMe ? Colors.red.shade50 : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(8)
                                      ),
                                      child: Text(note.label, style: TextStyle(fontSize: 12, color: isSharedWithMe ? Colors.red.shade700 : Colors.grey.shade800)),
                                    ),
                                    Row(
                                      children: [
                                        if (note.sharedWith.isNotEmpty && !isSharedWithMe)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 8.0),
                                            child: Icon(Icons.group, size: 16, color: Colors.indigo),
                                          ),
                                        Text(note.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
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
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateEditNoteScreen()));
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Tạo mới'),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            accountName: Text(AppState.currentUserName, style: const TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(AppState.currentUserEmail),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: AppState.currentUserAvatar != null ? NetworkImage(AppState.currentUserAvatar!) : null,
              child: AppState.currentUserAvatar == null ? const Icon(Icons.person, size: 40, color: Colors.indigo) : null,
            ),
          ),
          ListTile(
              leading: const Icon(Icons.search),
              title: Text('Tất cả ghi chú', style: TextStyle(fontWeight: _viewMode == 'ALL' ? FontWeight.bold : FontWeight.normal, color: _viewMode == 'ALL' ? Colors.indigo : Colors.black)),
              onTap: () {
                setState(() => _viewMode = 'ALL');
                Navigator.pop(context);
              }
          ),
          const Divider(),
          ListTile(
              leading: const Icon(Icons.group),
              title: Text('Được chia sẻ với tôi', style: TextStyle(fontWeight: _viewMode == 'SHARED' ? FontWeight.bold : FontWeight.normal, color: _viewMode == 'SHARED' ? Colors.indigo : Colors.black)),
              onTap: () {
                setState(() => _viewMode = 'SHARED');
                Navigator.pop(context);
              }
          ),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Thùng rác'), onTap: () {}),
        ],
      ),
    );
  }
}