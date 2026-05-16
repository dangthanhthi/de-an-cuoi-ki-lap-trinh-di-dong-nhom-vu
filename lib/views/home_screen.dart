import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../controllers/app_state.dart';
import '../controllers/note_provider.dart';
import '../models/app_models.dart';
import '../widgets/notes/note_card.dart';
import '../widgets/notes/filter_section.dart';
import '../widgets/main/sidebar_menu.dart';
import '../widgets/common/empty_state.dart';
import '../widgets/notes/skeleton_note_list.dart';
import '../widgets/notes/filter_sheet.dart';
import '../utils/note_utils.dart';
import 'requests_screen.dart';
import 'create_edit_note_screen.dart';
import '../widgets/notes/kanban_view.dart';
import 'package:animate_do/animate_do.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_updateConnectionStatus);
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final online = await FirebaseService.isOnline();
    if (mounted) {
      setState(() => _isOffline = !online);
      if (online) FirebaseService.syncOfflineChanges();
    }
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isOffline = results.contains(ConnectivityResult.none);
    if (isOffline != _isOffline && mounted) {
      setState(() => _isOffline = isOffline);
      if (!isOffline) FirebaseService.syncOfflineChanges();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final noteProvider = Provider.of<NoteProvider>(context);

    return Scaffold(
      drawer: const SidebarMenu(),
      appBar: AppBar(
        title: Text(
          noteProvider.viewMode == 'ALL' 
              ? 'Tất cả ghi chú' 
              : (noteProvider.viewMode == 'SHARED' 
                  ? 'Được chia sẻ' 
                  : (noteProvider.viewMode == 'ASSIGNED' ? 'Nhiệm vụ được giao' : 'Ghi chú của tôi')),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          StreamBuilder<int>(
            stream: FirebaseService.bellRequestsCountStream(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Badge(
                label: Text('$count'),
                isLabelVisible: count > 0,
                child: IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const RequestsScreen()),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(noteProvider.homeViewType == HomeViewType.list 
                ? Icons.view_kanban_outlined 
                : Icons.view_list_outlined),
            tooltip: noteProvider.homeViewType == HomeViewType.list 
                ? 'Xem dạng bảng' 
                : 'Xem dạng danh sách',
            onPressed: () {
              noteProvider.setViewType(
                noteProvider.homeViewType == HomeViewType.list 
                    ? HomeViewType.kanban 
                    : HomeViewType.list
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          FilterSection(
            onShowAdvancedFilters: () => _showAdvancedFilters(context, noteProvider),
            onShowSort: () => _showSortOptions(context, noteProvider),
          ),
          Expanded(
            child: noteProvider.isLoading
                ? const SkeletonNoteList()
                : (noteProvider.homeViewType == HomeViewType.list
                    ? _buildNoteList(noteProvider)
                    : KanbanView(
                        notes: noteProvider.notes,
                        viewMode: noteProvider.viewMode,
                      )),
          ),
        ],
      ),
      floatingActionButton: FadeInRight(
        child: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateEditNoteScreen()),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Ghi chú mới'),
        ),
      ),
    );
  }

  Widget _buildNoteList(NoteProvider provider) {
    final notes = provider.notes;

    if (notes.isEmpty) {
      return EmptyState(
        icon: Icons.note_alt_outlined,
        text: 'Chưa có ghi chú nào',
        subtext: provider.searchQuery.isNotEmpty 
            ? 'Không tìm thấy kết quả cho "${provider.searchQuery}"'
            : 'Hãy bắt đầu bằng cách nhấn vào nút "Ghi chú mới" phía dưới.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        return FadeInUp(
          delay: Duration(milliseconds: index * 50),
          child: NoteCard(
            note: notes[index],
            viewMode: provider.viewMode,
            onLongPress: (note) => _showNoteQuickActions(context, note),
          ),
        );
      },
    );
  }

  void _showSortOptions(BuildContext context, NoteProvider provider) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SortTile(
              label: 'Mới nhất trước',
              icon: Icons.calendar_today,
              selected: provider.sortBy == 'date_desc',
              onTap: () {
                provider.setSortBy('date_desc');
                Navigator.pop(ctx);
              },
            ),
            _SortTile(
              label: 'Cũ nhất trước',
              icon: Icons.history,
              selected: provider.sortBy == 'date_asc',
              onTap: () {
                provider.setSortBy('date_asc');
                Navigator.pop(ctx);
              },
            ),
            _SortTile(
              label: 'Ưu tiên',
              icon: Icons.flag_outlined,
              selected: provider.sortBy == 'priority_desc',
              onTap: () {
                provider.setSortBy('priority_desc');
                Navigator.pop(ctx);
              },
            ),
            _SortTile(
              label: 'Tiêu đề (A-Z)',
              icon: Icons.sort_by_alpha,
              selected: provider.sortBy == 'title_asc',
              onTap: () {
                provider.setSortBy('title_asc');
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAdvancedFilters(BuildContext context, NoteProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (ctx) => FilterSheet(provider: provider),
    );
  }

  void _showNoteQuickActions(BuildContext context, Note note) {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final creatorEmail = note.createdByEmail.toLowerCase().trim();
    final isOwner = creatorEmail == myEmail || (creatorEmail.isEmpty && note.groupId.isEmpty);
    
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                note.isPinnedByUser ? Icons.push_pin : Icons.push_pin_outlined,
                color: note.isPinnedByUser ? Colors.amber : null,
              ),
              title: Text(note.isPinnedByUser ? 'Bỏ ghim' : 'Ghim vào màn hình chính'),
              onTap: () async {
                Navigator.pop(sheetContext);
                
                final noteProvider = context.read<NoteProvider>();
                if (!note.isPinnedByUser) {
                  final myEmail = AppState.currentUserEmail.toLowerCase().trim();
                  final myUid = FirebaseService.currentUid;
                  
                  // Phân loại ghi chú hiện tại
                  final isCreatedByMe = note.userId == myUid || note.createdByEmail.toLowerCase() == myEmail;
                  final isAssignedToMe = note.todos.any((t) => t.assigneeEmail.toLowerCase() == myEmail);
                  final isSharedWithMe = !isCreatedByMe && note.groupId.isEmpty;

                  int currentTypeCount = 0;
                  String typeName = "";

                  if (isAssignedToMe) {
                    currentTypeCount = noteProvider.allNotes.where((n) => 
                      n.isPinnedByUser && n.todos.any((t) => t.assigneeEmail.toLowerCase() == myEmail)).length;
                    typeName = "nhiệm vụ được giao";
                  } else if (isSharedWithMe) {
                    currentTypeCount = noteProvider.allNotes.where((n) => 
                      n.isPinnedByUser && n.groupId.isEmpty && n.userId != myUid && n.createdByEmail.toLowerCase() != myEmail).length;
                    typeName = "ghi chú được chia sẻ";
                  } else if (isCreatedByMe && note.groupId.isEmpty) {
                    currentTypeCount = noteProvider.allNotes.where((n) => 
                      n.isPinnedByUser && n.groupId.isEmpty && (n.userId == myUid || n.createdByEmail.toLowerCase() == myEmail)).length;
                    typeName = "ghi chú cá nhân";
                  }

                  if (typeName.isNotEmpty && currentTypeCount >= 3) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Bạn đã ghim tối đa 3 $typeName'),
                          backgroundColor: Colors.orange.shade800,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    return;
                  }
                }
                
                await FirebaseService.toggleNotePin(note.id, !note.isPinnedByUser);
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Xóa khỏi màn hình chính'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseService.hideNoteForMe(note.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Sửa ghi chú'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => CreateEditNoteScreen(note: note)));
              },
            ),
            if (isOwner && note.groupId.isEmpty)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Chia sẻ ghi chú'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  NoteUtils.showShareSheet(context, note, onShareSuccess: () {});
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: const Text('Xóa vĩnh viễn'),
              textColor: Theme.of(context).colorScheme.error,
              onTap: () async {
                Navigator.pop(sheetContext);
                _confirmDelete(context, note);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text('Bạn có chắc muốn xóa "${note.title}" không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseService.deleteNote(note.id, note.title);
    }
  }
}

class _SortTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? colorScheme.primary : null),
      title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : null)),
      trailing: selected ? Icon(Icons.check, color: colorScheme.primary) : null,
      onTap: onTap,
    );
  }
}
