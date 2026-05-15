import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../controllers/app_state.dart';
import '../models/app_models.dart';
import '../utils/media_utils.dart';
import 'create_edit_note_screen.dart';
import 'note_detail_screen.dart';
import 'group_info_screen.dart';
import '../utils/note_utils.dart';

class GroupNotesScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupNotesScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupNotesScreen> createState() => _GroupNotesScreenState();
}

class _GroupNotesScreenState extends State<GroupNotesScreen> {
  final TextEditingController _commentController = TextEditingController();
  String _searchQuery = '';
  int _tabIndex = 0;
  final ScrollController _discussionScrollController = ScrollController();
  final ScrollController _notesScrollController = ScrollController();
  Map<String, dynamic>? _replyingTo;
  final List<String> _attachments = [];
  bool _isUploading = false;
  String? _editingCommentId;

  List<Map<String, dynamic>> _allMembers = [];
  List<Map<String, dynamic>> _mentionSuggestions = [];
  bool _showMentions = false;
  String _mentionQuery = '';

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _liveSpeechText = '';
  String _lastInsertedSpeech = '';
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    FirebaseService.markGroupAsRead(widget.groupId);
    _loadMembers();
    _commentController.addListener(_onCommentChanged);
  }

  void _loadMembers() {
    FirebaseService.getGroupMembersStream(widget.groupId).listen((members) {
      if (mounted) {
        setState(() {
          _allMembers = members;
        });
      }
    });
  }

  void _onCommentChanged() {
    final text = _commentController.text;
    final selection = _commentController.selection;
    if (selection.baseOffset <= 0) {
      if (_showMentions) setState(() => _showMentions = false);
      return;
    }

    final beforeCursor = text.substring(0, selection.baseOffset);
    final lastAt = beforeCursor.lastIndexOf('@');

    if (lastAt != -1) {
      final query = beforeCursor.substring(lastAt + 1);
      if (!query.contains(' ')) {
        setState(() {
          _showMentions = true;
          _mentionQuery = query.toLowerCase();
          final myEmail = AppState.currentUserEmail.toLowerCase().trim();
          final members = _allMembers.where((m) {
            final name = (m['name'] ?? '').toString().toLowerCase();
            final email = (m['email'] ?? '').toString().toLowerCase();
            if (email == myEmail) return false;
            return name.contains(_mentionQuery) ||
                email.contains(_mentionQuery);
          }).toList();

          if (_mentionQuery.isEmpty ||
              'all'.contains(_mentionQuery) ||
              'tất cả'.contains(_mentionQuery)) {
            members.insert(0, {
              'name': 'Tất cả',
              'email': 'all',
              'isAll': true,
            });
          }
          _mentionSuggestions = members;
        });
        return;
      }
    }

    if (_showMentions) setState(() => _showMentions = false);
  }

  void _selectMention(Map<String, dynamic> member) {
    final text = _commentController.text;
    final selection = _commentController.selection;
    final beforeCursor = text.substring(0, selection.baseOffset);
    final afterCursor = text.substring(selection.baseOffset);
    final lastAt = beforeCursor.lastIndexOf('@');

    final name = member['name'] ?? member['email'];
    final newBefore = '${beforeCursor.substring(0, lastAt)}@[$name] ';

    _commentController.text = newBefore + afterCursor;
    _commentController.selection = TextSelection.collapsed(
      offset: newBefore.length,
    );
    setState(() => _showMentions = false);
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    _discussionScrollController.dispose();
    _notesScrollController.dispose();
    super.dispose();
  }

  String _getReplyDisplayText(
    Map<String, dynamic> data,
    List<QueryDocumentSnapshot> docs,
  ) {
    final replyTo = data['replyTo'] as Map<String, dynamic>?;
    if (replyTo == null) return '';
    final replyToId = replyTo['id']?.toString();
    final storedText = (replyTo['text'] ?? '').toString();
    if (replyToId == null || replyToId.isEmpty) return storedText;

    try {
      final parentDoc = docs.firstWhere((d) => d.id == replyToId);
      final parentData = parentDoc.data() as Map<String, dynamic>;
      if (parentData['isRecalled'] == true) {
        return 'Tin nhắn đã bị thu hồi';
      }
    } catch (_) {}
    return storedText;
  }

  void _scrollToMessage(String? messageId, List<QueryDocumentSnapshot> docs) {
    if (messageId == null || messageId.isEmpty) return;
    final index = docs.indexWhere((doc) => doc.id == messageId);
    if (index != -1 && _discussionScrollController.hasClients) {
      _discussionScrollController.animateTo(
        index * 100.0, // rough estimate matching ChatScreen
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    setState(() => _isUploading = true);
    String result;

    if (_editingCommentId != null) {
      result = await FirebaseService.editGroupComment(
        widget.groupId,
        _editingCommentId!,
        text,
      );
    } else {
      result = await FirebaseService.addGroupComment(
        widget.groupId,
        text,
        attachments: _attachments,
        replyTo: _replyingTo,
      );
    }

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (result == 'SUCCESS') {
      _commentController.clear();
      setState(() {
        _replyingTo = null;
        _editingCommentId = null;
        _attachments.clear();
      });
      _discussionScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result), backgroundColor: Colors.red),
      );
    }
  }

  void _showCommentActions({
    required String commentId,
    required Map<String, dynamic> data,
    required bool isMe,
  }) {
    final text = (data['text'] ?? '').toString().trim();
    final hasText = text.isNotEmpty;
    final isRecalled = data['isRecalled'] == true;
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isRecalled) ...[
              ListTile(
                leading: const Icon(Icons.reply_outlined),
                title: const Text('Trả lời'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() {
                    _replyingTo = {
                      'id': commentId,
                      'text': text.isEmpty ? 'Hình ảnh/Tệp' : text,
                      'senderName': (data['userName'] ?? 'Người dùng')
                          .toString(),
                    };
                    _editingCommentId = null;
                  });
                },
              ),
              if (hasText)
                ListTile(
                  leading: const Icon(Icons.copy_all_outlined),
                  title: const Text('Sao chép tin nhắn'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép tin nhắn')),
                    );
                  },
                ),
              if (isMe && hasText)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Sửa tin nhắn'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    setState(() {
                      _editingCommentId = commentId;
                      _commentController.text = text;
                      _replyingTo = null;
                    });
                  },
                ),
              ListTile(
                leading: Icon(
                  data['isPinned'] == true
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                ),
                title: Text(
                  data['isPinned'] == true ? 'Bỏ ghim' : 'Ghim tin nhắn',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await FirebaseService.toggleGroupCommentPin(
                    widget.groupId,
                    commentId,
                    data['isPinned'] != true,
                  );
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Xem chi tiết tin nhắn'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showCommentDetails(data);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa ở phía tôi'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FirebaseService.deleteGroupComment(
                  widget.groupId,
                  commentId,
                  deleteForEveryone: false,
                );
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã ẩn thảo luận này')),
                  );
              },
            ),
            if (!isRecalled && (isMe || AppState.currentUserRole == 'Admin'))
              ListTile(
                leading: const Icon(Icons.undo_outlined, color: Colors.red),
                title: const Text('Thu hồi thảo luận'),
                textColor: Colors.red,
                onTap: () async {
                  final shouldRecall = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Thu hồi thảo luận?'),
                      content: const Text(
                        'Thảo luận này sẽ bị xóa đối với tất cả mọi người.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Hủy'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Thu hồi'),
                        ),
                      ],
                    ),
                  );
                  if (shouldRecall != true) return;
                  if (!mounted) return;

                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  final res = await FirebaseService.deleteGroupComment(
                    widget.groupId,
                    commentId,
                    deleteForEveryone: true,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          res == 'SUCCESS' ? 'Đã thu hồi thảo luận' : res,
                        ),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setGroupMute(Duration? duration) async {
    await FirebaseService.muteTarget(
      type: 'group',
      targetId: widget.groupId,
      duration: duration,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã cập nhật thông báo nhóm')));
  }

  Note _noteFromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return Note.fromJson(data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupInfoScreen(
                groupId: widget.groupId,
                initialName: widget.groupName,
              ),
            ),
          ),
          child: Text(widget.groupName),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupInfoScreen(
                  groupId: widget.groupId,
                  initialName: widget.groupName,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'unmute') _setGroupMute(null);
              if (value == 'mute_1h') _setGroupMute(const Duration(hours: 1));
              if (value == 'mute_forever')
                _setGroupMute(const Duration(days: 36500));
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mute_1h',
                child: Text('Tắt thông báo 1 giờ'),
              ),
              const PopupMenuItem(
                value: 'mute_forever',
                child: Text('Tắt thông báo đến khi mở lại'),
              ),
              const PopupMenuItem(
                value: 'unmute',
                child: Text('Mở lại thông báo'),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [_buildNotesTab(), _buildKanbanTab(), _buildDiscussionTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speaker_notes_outlined),
            selectedIcon: Icon(Icons.speaker_notes),
            label: 'Ghi chú',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_kanban_outlined),
            selectedIcon: Icon(Icons.view_kanban),
            label: 'Kanban',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum),
            label: 'Thảo luận',
          ),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: Colors.teal,
              onPressed: () async {
                FirebaseService.currentGroupId = widget.groupId;
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateEditNoteScreen(),
                  ),
                );
                FirebaseService.currentGroupId = '';
              },
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Tạo Note Nhóm',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildNotesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm ghi chú nhóm...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getGroupNotesStream(widget.groupId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('Nhóm chưa có ghi chú nào'));
              }

              final notes = docs.map(_noteFromDoc).where((note) {
                final query = NoteUtils.removeDiacritics(_searchQuery).trim();
                if (query.isEmpty) return true;

                final title = NoteUtils.removeDiacritics(note.title);
                final content = NoteUtils.removeDiacritics(note.content);
                final label = NoteUtils.removeDiacritics(note.label);

                return title.contains(query) ||
                    content.contains(query) ||
                    label.contains(query) ||
                    note.todos.any(
                      (todo) =>
                          NoteUtils.removeDiacritics(todo.task).contains(query),
                    );
              }).toList();

              // Sắp xếp: Ghim lên đầu, sau đó theo ngày (giả định date là chuỗi ISO hoặc tương đương)
              notes.sort((a, b) {
                if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
                return b.date.compareTo(a.date);
              });

              if (notes.isEmpty) {
                return const Center(
                  child: Text('Không tìm thấy ghi chú phù hợp'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  return _buildGroupNoteCard(notes[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKanbanTab() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface.withValues(
        alpha: 0.5,
      ), // Subtle background for the board
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getGroupNotesStream(widget.groupId),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          final tasks = <Map<String, dynamic>>[];
          for (final doc in docs) {
            final note = _noteFromDoc(doc);
            for (var i = 0; i < note.todos.length; i++) {
              tasks.add({'note': note, 'todo': note.todos[i], 'index': i});
            }
          }

          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.view_kanban_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có công việc để hiển thị',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          final columns = [
            (TodoStatus.todo, 'Cần làm', Icons.list_alt_rounded, Colors.grey),
            (
              TodoStatus.doing,
              'Đang làm',
              Icons.pending_actions_rounded,
              Colors.blue,
            ),
            (
              TodoStatus.done,
              'Hoàn thành',
              Icons.check_circle_outline_rounded,
              Colors.green,
            ),
          ];

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns.map((col) {
                final colStatus = col.$1;
                final colTasks = tasks.where((t) {
                  final status = (t['todo'] as TodoItem).status;
                  return status == colStatus;
                }).toList();

                return Container(
                  width: 300,
                  margin: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(col.$3, size: 20, color: col.$4),
                            const SizedBox(width: 8),
                            Text(
                              col.$2,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: col.$4.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                colTasks.length.toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: col.$4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.65,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: colTasks.length,
                          itemBuilder: (context, idx) =>
                              _buildKanbanCard(colTasks[idx]),
                        ),
                      ),
                      if (colTasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'Trống',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildKanbanCard(Map<String, dynamic> t) {
    final note = t['note'] as Note;
    final todo = t['todo'] as TodoItem;
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = todo.status == TodoStatus.done;
    final hasPriority = todo.priority.isNotEmpty && todo.priority != 'none';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDone
              ? Colors.green.withValues(alpha: 0.2)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreateEditNoteScreen(note: note),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        todo.task,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          height: 1.4,
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
                          color: isDone
                              ? colorScheme.outline
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (hasPriority)
                      _InfoChip(
                        label: _getPriorityLabel(todo.priority),
                        icon: Icons.priority_high_rounded,
                        color: _getPriorityColor(todo.priority),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 12,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (note.label.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _InfoChip(
                        label: note.label,
                        icon: Icons.label_outline_rounded,
                        color: colorScheme.secondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            backgroundImage: todo.assigneeEmail.isNotEmpty
                                ? avatarImageProvider(
                                    _allMembers.firstWhere(
                                      (m) => m['email'] == todo.assigneeEmail,
                                      orElse: () => {},
                                    )['avatar'],
                                    name: todo.assigneeName,
                                  )
                                : null,
                            child: todo.assigneeEmail.isEmpty
                                ? Icon(
                                    Icons.person_add_alt_1_outlined,
                                    size: 12,
                                    color: colorScheme.outline,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          todo.assigneeName.isNotEmpty
                              ? todo.assigneeName
                              : 'Chờ giao',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: todo.assigneeName.isNotEmpty
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: todo.assigneeName.isNotEmpty
                                ? colorScheme.onSurface
                                : colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (todo.attachments.isNotEmpty) ...[
                          Icon(
                            Icons.attach_file_rounded,
                            size: 14,
                            color: colorScheme.outline,
                          ),
                          Text(
                            todo.attachments.length.toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.outline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (todo.deadline != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: todo.isOverdue
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 12,
                                  color: todo.isOverdue
                                      ? Colors.red
                                      : colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${todo.deadline!.day}/${todo.deadline!.month}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: todo.isOverdue
                                        ? Colors.red
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getPriorityLabel(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return 'Khẩn cấp';
      case 'high':
      case 'cao':
        return 'Cao';
      case 'medium':
      case 'trung bình':
        return 'Thường';
      case 'low':
      case 'thấp':
        return 'Thấp';
      default:
        return '';
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'urgent':
        return Colors.purple;
      case 'cao':
      case 'high':
        return Colors.red;
      case 'trung bình':
      case 'medium':
        return Colors.orange;
      case 'thấp':
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDiscussionTab() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getGroupCommentsStream(widget.groupId),
                builder: (context, snapshot) {
                  final allComments = snapshot.data?.docs ?? [];
                  final myEmail = AppState.currentUserEmail
                      .toLowerCase()
                      .trim();
                  final comments = allComments.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final hiddenBy = List<String>.from(
                      data['hiddenBy'] ?? const [],
                    ).map((e) => e.toLowerCase().trim()).toList();
                    return !hiddenBy.contains(myEmail);
                  }).toList();

                  if (comments.isEmpty) {
                    return const Center(child: Text('Chưa có thảo luận nào'));
                  }

                  return Stack(
                    children: [
                      ListView.builder(
                        controller: _discussionScrollController,
                        reverse: true,
                        padding: const EdgeInsets.only(
                          top: 80,
                          left: 16,
                          right: 16,
                          bottom: 16,
                        ),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final doc = comments[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isMe =
                              data['userEmail'] == AppState.currentUserEmail;
                          final isRecalled = data['isRecalled'] == true;
                          final text = isRecalled
                              ? 'Tin nhắn đã bị thu hồi'
                              : (data['text'] ?? '').toString();
                          final seenBy = List<String>.from(
                            data['seenBy'] ?? [],
                          );
                          // Safe mark as seen
                          if (!isRecalled && !seenBy.contains(myEmail)) {
                            Future.delayed(Duration.zero, () {
                              FirebaseService.markGroupCommentAsSeen(
                                widget.groupId,
                                doc.id,
                              );
                            });
                          }

                          if (data['isSystem'] == true) {
                            return Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 32,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  data['text'] ?? '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }

                          return GestureDetector(
                            onLongPress: () => _showCommentActions(
                              commentId: doc.id,
                              data: data,
                              isMe: isMe,
                            ),
                            child: Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.78,
                                    ),
                                    margin: const EdgeInsets.only(bottom: 4),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer
                                          : Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (!isRecalled &&
                                            data['replyTo'] != null)
                                          InkWell(
                                            onTap: () => _scrollToMessage(
                                              data['replyTo']['id'],
                                              comments,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    data['replyTo']['sender'] ??
                                                        'Người dùng',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                  Text(
                                                    _getReplyDisplayText(
                                                      data,
                                                      comments,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        GestureDetector(
                                          onTap: () => _showUserProfile(
                                            data['userEmail'] ?? '',
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                backgroundImage:
                                                    avatarImageProvider(
                                                      data['userAvatar']
                                                          ?.toString(),
                                                      name: data['userName']
                                                          ?.toString(),
                                                    ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                data['userName'] ??
                                                    data['userEmail'] ??
                                                    '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        if (!isRecalled &&
                                            data['attachments'] != null)
                                          _buildMessageAttachments(
                                            List<String>.from(
                                              data['attachments'],
                                            ),
                                            isMe,
                                            Theme.of(context).colorScheme,
                                          ),
                                        _buildMessageText(text, isRecalled),
                                      ],
                                    ),
                                  ),
                                  if (!isRecalled)
                                    _buildSeenAvatars(
                                      seenBy,
                                      data['userEmail'] ?? '',
                                    ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      _buildPinnedMessagesBar(comments),
                      _buildMentionsOverlay(),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReplyPreview(),
                _buildEditHeader(),
                _buildDraftAttachments(),
                if (_liveSpeechText.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_liveSpeechText),
                  ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Ảnh',
                      onPressed: _isUploading ? null : _showImageSourceSheet,
                      icon: const Icon(Icons.image_outlined),
                    ),
                    IconButton(
                      tooltip: 'Tệp',
                      onPressed: _isUploading ? null : _pickFileAttachment,
                      icon: const Icon(Icons.attach_file),
                    ),
                    IconButton(
                      tooltip: 'Giọng nói',
                      onPressed: _toggleVoiceInput,
                      icon: Icon(
                        _isListening ? Icons.stop_circle : Icons.mic_none,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendComment(),
                        decoration: InputDecoration(
                          hintText: 'Viết thảo luận...',
                          counterText: '',
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      onPressed: _isUploading ? null : _sendComment,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupNoteCard(Note note) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    var accentColor = note.coverColor;
    if (isDark) {
      final hsl = HSLColor.fromColor(accentColor);
      accentColor = hsl
          .withSaturation((hsl.saturation + 0.16).clamp(0.0, 1.0).toDouble())
          .withLightness(0.58)
          .toColor();
    }
    final cardColor = colorScheme.surfaceContainerLow;
    final titleColor = note.resolvedTitleColor ?? colorScheme.onSurface;
    final titleFontSize = note.titleFontSize > 0 ? note.titleFontSize : 18.0;
    final mutedText = colorScheme.onSurfaceVariant;
    final completedTodos = note.todos.where((todo) => todo.isDone).length;
    final progress = note.isTodo && note.todos.isNotEmpty
        ? completedTodos / note.todos.length
        : 0.0;
    final priority = NotePriority.normalize(note.priority);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NoteDetailScreen(note: note),
            ),
          );
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showNoteQuickActions(note);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 54,
                decoration: BoxDecoration(
                  color: accentColor,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: note.titleIsBold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontStyle: note.titleIsItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              decoration: note.titleIsUnderlined
                                  ? TextDecoration.underline
                                  : null,
                              color: titleColor,
                            ),
                          ),
                        ),
                        if (note.isPinned) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                        ],
                        const SizedBox(width: 8),
                        Text(
                          note.date.split('T')[0],
                          style: TextStyle(fontSize: 10, color: mutedText),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (note.isTodo) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: accentColor.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tiến độ: ${(progress * 100).toInt()}%',
                            style: TextStyle(fontSize: 11, color: mutedText),
                          ),
                          Text(
                            '$completedTodos/${note.todos.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ] else
                      Text(
                        note.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: mutedText),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _InfoChip(label: note.label, icon: Icons.label_outline),
                        if (note.todos.any(
                          (t) =>
                              t.assigneeEmail.toLowerCase() ==
                              AppState.currentUserEmail.toLowerCase(),
                        ))
                          _InfoChip(
                            label: 'Bạn phụ trách',
                            icon: Icons.assignment_ind_outlined,
                            color: Colors.orange,
                          ),
                        if (priority != NotePriority.none)
                          _InfoChip(
                            label: NotePriority.label(priority),
                            icon: Icons.flag_outlined,
                            color: _priorityColor(priority),
                          ),
                        if (note.attachments.isNotEmpty)
                          _InfoChip(
                            label: '${note.attachments.length} tệp',
                            icon: Icons.attach_file,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case NotePriority.high:
        return Colors.red;
      case NotePriority.medium:
        return Colors.orange;
      case NotePriority.low:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Future<void> _showNoteQuickActions(Note note) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final creatorEmail = note.createdByEmail.toLowerCase().trim();
    final isAdmin = AppState.currentUserRole.toLowerCase() == 'admin';
    final isOwner =
        (creatorEmail.isNotEmpty && creatorEmail == myEmail) ||
        (creatorEmail.isEmpty &&
            note.groupId.isEmpty &&
            note.sharedWith.isEmpty);

    final isGroupNote = note.groupId.isNotEmpty;
    bool canManageGroup = false;
    if (isGroupNote) {
      canManageGroup = await FirebaseService.canCurrentUserManageGroupTasks(
        note.groupId,
      );
    }

    // Quyền chỉnh sửa (Dành cho người tạo, Admin, hoặc Trưởng nhóm/Điều phối)
    final canEdit = isOwner || isAdmin || canManageGroup;

    // Quyền xóa vĩnh viễn cho cả nhóm (Chỉ dành cho Admin hoặc Trưởng nhóm/Điều phối)
    // Người tạo nếu là thành viên thông thường thì không được xóa cho cả nhóm
    final canDeleteForGroup = isAdmin || canManageGroup;

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: note.isPinned ? Colors.amber : null,
              ),
              title: Text(
                note.isPinned ? 'Bỏ ghim khỏi nhóm' : 'Ghim lên đầu nhóm',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleNotePin(note);
              },
            ),

            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Sửa ghi chú'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateEditNoteScreen(note: note),
                    ),
                  );
                },
              ),

            if (canDeleteForGroup)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: const Text('Xóa vĩnh viễn cho cả nhóm'),
                textColor: Theme.of(context).colorScheme.error,
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _confirmDeleteNote(note);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleNotePin(Note note) async {
    final isPinned = note.isPinned;
    await FirebaseService.toggleGroupNotePin(note.id, !isPinned);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !isPinned ? 'Đã ghim ghi chú lên đầu nhóm' : 'Đã bỏ ghim ghi chú',
        ),
      ),
    );
  }

  Future<void> _confirmDeleteNote(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa vĩnh viễn?'),
        content: const Text(
          'Hành động này sẽ xóa ghi chú cho TẤT CẢ thành viên trong nhóm. Bạn có chắc không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Xóa vĩnh viễn',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseService.deleteNote(note.id, note.title);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa ghi chú vĩnh viễn')));
    }
  }

  Widget _buildPinnedMessagesBar(List<QueryDocumentSnapshot> allComments) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('comments')
          .where('isPinned', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];
        final docs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final hiddenBy = List<String>.from(data['hiddenBy'] ?? const []);
          return !hiddenBy.contains(AppState.currentUserEmail);
        }).toList();

        if (docs.isEmpty) return const SizedBox.shrink();
        final colorScheme = Theme.of(context).colorScheme;

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.95,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4),
              ],
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const Border(),
              leading: Icon(
                Icons.push_pin,
                size: 18,
                color: colorScheme.primary,
              ),
              title: Text(
                '${docs.length} tin nhắn đã ghim',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return ListTile(
                  dense: true,
                  onTap: () => _scrollToMessage(doc.id, allComments),
                  title: Text(
                    data['text'] ??
                        (data['attachments']?.isNotEmpty == true
                            ? '[Tệp đính kèm]'
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  subtitle: Text(
                    'Từ ${data['userName']}',
                    style: const TextStyle(fontSize: 9),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.push_pin_outlined, size: 14),
                        onPressed: () => FirebaseService.toggleGroupCommentPin(
                          widget.groupId,
                          doc.id,
                          false,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 14),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditHeader() {
    if (_editingCommentId == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: Colors.amber, width: 4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 16, color: Colors.amber),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Đang chỉnh sửa thảo luận',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() {
              _editingCommentId = null;
              _commentController.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    if (_replyingTo == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: colorScheme.primary, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang trả lời ${_replyingTo!['senderName']}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                Text(
                  _replyingTo!['text'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftAttachments() {
    if (_attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _attachments.length; i++)
            InputChip(
              avatar: Icon(
                isImageValue(_attachments[i])
                    ? Icons.image_outlined
                    : Icons.attach_file,
                size: 18,
              ),
              label: Text(attachmentLabel(_attachments[i], i)),
              onDeleted: () => setState(() => _attachments.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageAttachments(
    List<String> attachments,
    bool isMe,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < attachments.length; i++) ...[
          if (isImageValue(attachments[i]))
            GestureDetector(
              onTap: () => _showImagePreview(attachments[i], i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                constraints: const BoxConstraints(
                  maxHeight: 180,
                  minWidth: 120,
                ),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Image.memory(
                  bytesFromDataUri(attachments[i])!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image),
                ),
              ),
            )
          else
            InkWell(
              onTap: () => _openAttachment(attachments[i], i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.attach_file,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        attachmentLabel(attachments[i], i),
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      final capturedText = _liveSpeechText;
      await _speech.stop();
      _insertVoiceText(capturedText);
      if (mounted) setState(() => _isListening = false);
      return;
    }

    final microphoneStatus = await Permission.microphone.request();
    if (!microphoneStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn cần cấp quyền micro để nhập bằng giọng nói.'),
          ),
        );
      }
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        if (status == 'done' || status == 'notListening') {
          _insertVoiceText(_liveSpeechText);
          setState(() => _isListening = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isListening = false);
      },
    );

    if (!available) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thiết bị chưa hỗ trợ nhận giọng nói.')),
        );
      return;
    }

    setState(() {
      _isListening = true;
      _liveSpeechText = '';
      _lastInsertedSpeech = '';
    });

    await _speech.listen(
      localeId: 'vi_VN',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() => _liveSpeechText = result.recognizedWords);
        if (result.finalResult) _insertVoiceText(result.recognizedWords);
      },
    );
  }

  void _insertVoiceText(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty || cleanText == _lastInsertedSpeech) return;
    _lastInsertedSpeech = cleanText;
    final current = _commentController.text.trim();
    _commentController.text = current.isEmpty
        ? cleanText
        : '$current $cleanText';
    _commentController.selection = TextSelection.fromPosition(
      TextPosition(offset: _commentController.text.length),
    );
    setState(() => _liveSpeechText = '');
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImageAttachment(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickImageAttachment(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageAttachment(ImageSource source) async {
    if (_isUploading) return;

    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bạn cần cấp quyền camera để chụp ảnh.'),
            ),
          );
        return;
      }
    } else {
      if (Platform.isIOS) {
        await Permission.photos.request();
      } else {
        await Permission.photos.request();
        await Permission.storage.request();
      }
    }

    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 50,
      maxWidth: 800,
    );
    if (image == null) return;

    final bytes = await image.readAsBytes();
    setState(() => _attachments.add(buildDataUri(bytes, image.name)));
  }

  Future<void> _pickFileAttachment() async {
    try {
      final result = await FilePicker.pickFiles(withData: true);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(
            () => _attachments.add(buildDataUri(file.bytes!, file.name)),
          );
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi chọn tệp: $e')));
    }
  }

  void _showImagePreview(String value, int index) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            Center(child: Image.memory(bytesFromDataUri(value)!)),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(String value, int index) async {
    try {
      final bytes = bytesFromDataUri(value);
      if (bytes == null) return;
      final fileName = fileNameFromDataUri(value);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(bytes);
      await OpenFilex.open(tempFile.path);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể mở tệp: $e')));
    }
  }

  Widget _buildMentionsOverlay() {
    if (!_showMentions || _mentionSuggestions.isEmpty)
      return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _mentionSuggestions.length,
        itemBuilder: (context, index) {
          final member = _mentionSuggestions[index];
          final isAll = member['isAll'] == true;
          return ListTile(
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: isAll ? Colors.teal : null,
              backgroundImage: isAll
                  ? null
                  : avatarImageProvider(member['avatar'], name: member['name']),
              child: isAll
                  ? const Icon(Icons.groups, size: 16, color: Colors.white)
                  : null,
            ),
            title: Text(
              member['name'] ?? member['email'],
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              isAll ? 'Nhắc tên cả nhóm' : member['email'],
              style: const TextStyle(fontSize: 10),
            ),
            onTap: () => _selectMention(member),
          );
        },
      ),
    );
  }

  void _showCommentDetails(Map<String, dynamic> data) {
    final seenBy = List<String>.from(data['seenBy'] ?? []);
    String seenSummary = 'Chưa có ai xem';
    if (seenBy.isNotEmpty) {
      final names = seenBy.take(3).map((email) {
        final m = _allMembers.firstWhere(
          (m) => m['email'] == email,
          orElse: () => {},
        );
        return m['name'] ?? email;
      }).toList();
      seenSummary = names.join(', ');
      if (seenBy.length > 3) {
        seenSummary += ' và ${seenBy.length - 3} người khác';
      }
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chi tiết tin nhắn',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _detailRow(
                Icons.person_outline,
                'Người gửi',
                data['userName'] ?? 'Không xác định',
              ),
              _detailRow(
                Icons.access_time,
                'Thời gian',
                _formatTimestamp(data['createdAt']),
              ),
              if (data['isEdited'] == true)
                _detailRow(Icons.edit_outlined, 'Trạng thái', 'Đã chỉnh sửa'),
              _detailRow(
                Icons.remove_red_eye_outlined,
                'Đã xem bởi',
                seenSummary,
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Đang xử lý...';
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.day}/${date.month}/${date.year}';
    }
    return timestamp.toString();
  }

  Widget _buildMessageText(String text, bool isRecalled) {
    if (isRecalled) {
      return Text(
        text,
        style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final List<InlineSpan> spans = [];
    final RegExp mentionRegex = RegExp(r'@\[([^\]]+)\]');

    int lastIndex = 0;
    final matches = mentionRegex.allMatches(text).toList();

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      final name = match.group(1)!;

      spans.add(
        TextSpan(
          text: '@$name',
          style: const TextStyle(
            color: Color(0xFF0068FF), // Zalo Blue
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              final searchName = name.trim().toLowerCase();
              final member = _allMembers.firstWhere((m) {
                final mName = (m['name'] ?? '').toString().toLowerCase();
                final mEmail = (m['email'] ?? '').toString().toLowerCase();
                return mName == searchName ||
                    mName.contains(searchName) ||
                    mEmail.contains(searchName);
              }, orElse: () => {});

              if (member.isNotEmpty && member['email'] != null) {
                _showUserProfile(member['email']);
              } else if (searchName == 'tất cả' || searchName == 'all') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bạn đã nhắc tên tất cả thành viên'),
                  ),
                );
              }
            },
        ),
      );
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return RichText(
      text: TextSpan(
        children: spans,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 14,
          fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
        ),
      ),
    );
  }

  Widget _buildSeenAvatars(List<String> seenBy, String senderEmail) {
    // Filter out the sender
    final others = seenBy.where((email) => email != senderEmail).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    const maxVisible = 3;
    final visibleUsers = others.take(maxVisible).toList();
    final remaining = others.length - visibleUsers.length;
    final stackWidth = visibleUsers.isEmpty
        ? 0.0
        : (visibleUsers.length - 1) * 12.0 + 20.0;

    return GestureDetector(
      onTap: () => _showSeenDetails(others),
      child: Padding(
        padding: const EdgeInsets.only(top: 2, right: 4, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 20,
              width: stackWidth,
              child: Stack(
                children: [
                  for (var i = 0; i < visibleUsers.length; i++)
                    Positioned(
                      left: i * 12.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 8,
                          backgroundImage: avatarImageProvider(
                            _allMembers
                                .firstWhere(
                                  (m) => m['email'] == visibleUsers[i],
                                  orElse: () => {},
                                )['avatar']
                                ?.toString(),
                            name: _allMembers
                                .firstWhere(
                                  (m) => m['email'] == visibleUsers[i],
                                  orElse: () => {},
                                )['name']
                                ?.toString(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              remaining > 0 ? '+ $remaining' : 'Đã xem',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeenDetails(List<String> seenByEmails) {
    String summaryText = 'Đã xem bởi';
    if (seenByEmails.isEmpty) {
      summaryText = 'Chưa có ai xem';
    } else {
      final names = seenByEmails.take(3).map((email) {
        final m = _allMembers.firstWhere(
          (m) => m['email'] == email,
          orElse: () => {},
        );
        return m['name'] ?? email;
      }).toList();

      summaryText = names.join(', ');
      if (seenByEmails.length > 3) {
        summaryText += ' và ${seenByEmails.length - 3} người khác';
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summaryText,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: seenByEmails.length,
                  itemBuilder: (context, index) {
                    final email = seenByEmails[index];
                    final member = _allMembers.firstWhere(
                      (m) => m['email'] == email,
                      orElse: () => {'name': email, 'avatar': ''},
                    );
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatarImageProvider(
                          member['avatar'],
                          name: member['name'],
                        ),
                      ),
                      title: Text(member['name'] ?? email),
                      subtitle: Text(email),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showUserProfile(String email) async {
    if (email.isEmpty) return;

    final colorScheme = Theme.of(context).colorScheme;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final targetEmail = email.toLowerCase().trim();
    final isMe = targetEmail == myEmail;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: targetEmail)
          .limit(1)
          .get();

      if (!mounted) return;
      Navigator.pop(context);

      if (userSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy thông tin người dùng')),
        );
        return;
      }

      final userData = userSnap.docs.first.data();
      final name = (userData['name'] ?? targetEmail).toString();
      final avatar = (userData['avatar'] ?? '').toString();
      final lastActive = userData['lastActive'] as Timestamp?;
      final isOnline = userData['isOnline'] == true;

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  CircleAvatar(
                    radius: 50,
                    backgroundImage: avatarImageProvider(avatar, name: name),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    targetEmail,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (lastActive != null)
                    Text(
                      isOnline
                          ? 'Đang hoạt động'
                          : 'Hoạt động lần cuối: ${_formatLastActiveStatus(lastActive)}',
                      style: TextStyle(
                        color: isOnline
                            ? Colors.green
                            : colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: isOnline
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  const SizedBox(height: 32),
                  if (!isMe)
                    FutureBuilder<String>(
                      future: FirebaseService.checkFriendshipStatus(
                        targetEmail,
                      ),
                      builder: (context, snapshot) {
                        final status = snapshot.data ?? 'LOADING';
                        if (status == 'LOADING')
                          return const SizedBox(
                            height: 54,
                            child: Center(child: CircularProgressIndicator()),
                          );

                        String btnText = 'Gửi lời mời kết bạn';
                        IconData btnIcon = Icons.person_add_outlined;
                        bool canClick = true;

                        if (status == 'FRIEND') {
                          btnText = 'Đã là bạn bè';
                          btnIcon = Icons.check_circle_outline;
                          canClick = false;
                        } else if (status == 'PENDING_SENT') {
                          btnText = 'Đã gửi lời mời';
                          btnIcon = Icons.hourglass_empty;
                          canClick = false;
                        }

                        return SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: canClick
                                ? () async {
                                    final result =
                                        await FirebaseService.sendFriendRequest(
                                          targetEmail,
                                        );
                                    if (result == "SUCCESS")
                                      setSheetState(() {});
                                  }
                                : null,
                            icon: Icon(btnIcon),
                            label: Text(btnText),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                      label: const Text('Đóng'),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  String _formatLastActiveStatus(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 5) return 'Vừa mới truy cập';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _InfoChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
