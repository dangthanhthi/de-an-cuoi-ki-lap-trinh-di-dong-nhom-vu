import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../controllers/local_service.dart';
import '../controllers/app_state.dart';

import '../models/app_models.dart';
import '../utils/media_utils.dart';
import '../utils/note_utils.dart';
import 'create_edit_note_screen.dart';
import 'groups_list_screen.dart';
import 'requests_screen.dart';
import 'note_detail_screen.dart';
import 'statistics_screen.dart';
import 'calendar_screen.dart';
import 'contacts_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedLabel = AppState.selectedLabel;
  String _searchQuery = '';
  String _viewMode = 'ALL';
  String _filterCreator = '';
  String _filterAssignee = '';
  DateTime? _filterCreatedDate;
  DateTime? _filterDeadline;
  bool? _filterHasAttachments;
  String _filterTodoStatus = 'all';
  String _filterPriority = 'all'; // all, low, medium, high
  String _filterNoteType = 'all'; // all, note, todo
  bool? _filterIsPinned;
  bool? _filterHasReminder;
  String _sortBy = 'date_desc'; // date_desc, date_asc, priority_desc, title_asc
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOffline = false;
  Stream<List<Note>>? _cachedNotesStream;
  String? _lastStreamKey;

  Stream<List<Note>> _getNotesStream() {
    final key = _viewMode;
    if (_cachedNotesStream != null && _lastStreamKey == key) {
      return _cachedNotesStream!;
    }
    _lastStreamKey = key;
    _cachedNotesStream = _viewMode == 'SHARED'
        ? FirebaseService.getSharedNotesStream().map(
            (snap) => snap.docs.map(FirebaseService.noteFromDocument).toList(),
          )
        : (_viewMode == 'ALL'
            ? FirebaseService.getAllMyNotesStream()
            : FirebaseService.getMyNotesStream().map(
                (snap) => snap.docs.map(FirebaseService.noteFromDocument).toList(),
              ));
    return _cachedNotesStream!;
  }


  bool get _hasAdvancedFilters =>
      _filterCreator.trim().isNotEmpty ||
      _filterAssignee.trim().isNotEmpty ||
      _filterCreatedDate != null ||
      _filterDeadline != null ||
      _filterHasAttachments != null ||
      _filterTodoStatus != 'all' ||
      _filterPriority != 'all' ||
      _filterNoteType != 'all' ||
      _filterIsPinned != null ||
      _filterHasReminder != null;

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
    FirebaseService.isOnline().then((online) {
      if (mounted) {
        setState(() => _isOffline = !online);
        if (online) FirebaseService.syncOfflineChanges();
      }
    });
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isOffline = results.contains(ConnectivityResult.none);
    if (isOffline != _isOffline) {
      if (mounted) {
        setState(() => _isOffline = isOffline);
        if (!isOffline) {
          FirebaseService.syncOfflineChanges();
        }
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  DateTime? _noteCreatedDate(Note note) => DateTime.tryParse(note.date);

  Color _priorityColor(String priority) {
    switch (NotePriority.normalize(priority)) {
      case NotePriority.low:
        return Colors.green;
      case NotePriority.medium:
        return Colors.indigo;
      case NotePriority.high:
        return Colors.orange;
      case NotePriority.urgent:
        return Colors.red;
      case NotePriority.none:
        return Colors.grey;
      default:
        return Colors.purple;
    }
  }

  bool _matchesAdvancedFilters(Note note) {
    final creator = _filterCreator.toLowerCase().trim();
    if (creator.isNotEmpty &&
        !note.createdByEmail.toLowerCase().contains(creator) &&
        !note.createdByName.toLowerCase().contains(creator)) {
      return false;
    }

    final assignee = _filterAssignee.toLowerCase().trim();
    if (assignee.isNotEmpty &&
        (note.groupId.isEmpty ||
            !note.todos.any(
              (todo) =>
                  todo.assigneeEmail.toLowerCase().contains(assignee) ||
                  todo.assigneeName.toLowerCase().contains(assignee),
            ))) {
      return false;
    }

    if (_filterCreatedDate != null) {
      final createdDate = _noteCreatedDate(note);
      if (createdDate == null ||
          !_isSameDay(createdDate, _filterCreatedDate!)) {
        return false;
      }
    }

    if (_filterDeadline != null &&
        (note.groupId.isEmpty ||
            !note.todos.any(
              (todo) =>
                  todo.deadline != null &&
                  _isSameDay(todo.deadline!, _filterDeadline!),
            ))) {
      return false;
    }

    if (_filterHasAttachments != null &&
        note.attachments.isNotEmpty != _filterHasAttachments) {
      return false;
    }

    if (_filterTodoStatus != 'all') {
      if (note.groupId.isEmpty) return false;
      final hasStatus = note.todos.any(
        (todo) => _filterTodoStatus == TodoStatus.overdue
            ? todo.isOverdue
            : todo.effectiveStatus == _filterTodoStatus,
      );
      if (!hasStatus) return false;
    }

    if (_filterPriority != 'all' && note.priority != _filterPriority) {
      return false;
    }

    if (_filterNoteType != 'all') {
      if (_filterNoteType == 'todo' && !note.isTodo) return false;
      if (_filterNoteType == 'note' && note.isTodo) return false;
    }

    if (_filterIsPinned != null && note.isPinnedByUser != _filterIsPinned) {
      return false;
    }

    if (_filterHasReminder != null && note.hasReminder != _filterHasReminder) {
      return false;
    }

    return true;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Bất kỳ';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<DateTime?> _pickFilterDate(DateTime? current) {
    return showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
  }

  List<String> get _activeFilterBadges {
    final badges = <String>[];
    if (_filterCreator.trim().isNotEmpty) {
      badges.add('Người tạo: ${_filterCreator.trim()}');
    }
    if (_filterAssignee.trim().isNotEmpty) {
      badges.add('Người được giao: ${_filterAssignee.trim()}');
    }
    if (_filterCreatedDate != null) {
      badges.add('Ngày tạo: ${_formatDate(_filterCreatedDate)}');
    }
    if (_filterDeadline != null) {
      badges.add('Deadline: ${_formatDate(_filterDeadline)}');
    }
    if (_filterHasAttachments != null) {
      badges.add(
        _filterHasAttachments == true ? 'Có tệp đính kèm' : 'Không có tệp',
      );
    }
    if (_filterTodoStatus != 'all') {
      badges.add(
        _filterTodoStatus == TodoStatus.overdue
            ? 'Trễ hạn'
            : TodoStatus.label(_filterTodoStatus),
      );
    }
    if (_filterPriority != 'all') {
      badges.add('Ưu tiên: ${NotePriority.label(_filterPriority)}');
    }
    if (_filterNoteType != 'all') {
      badges.add(
        'Loại: ${_filterNoteType == "note" ? "Văn bản" : "Công việc"}',
      );
    }
    return badges;
  }

  void _showSnack(String message, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? null : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _toggleNotePin(Note note) async {
    final isPinned = note.isPinnedByUser;
    await FirebaseService.toggleNotePin(note.id, !isPinned);
    if (!mounted) return;
    _showSnack(!isPinned ? 'Đã ghim ghi chú' : 'Đã bỏ ghim ghi chú');
  }

  Future<void> _confirmDeleteNote(Note note) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa ghi chú?'),
        content: Text('Bạn có chắc muốn xóa "${note.title}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    final result = await FirebaseService.deleteNote(note.id, note.title);
    if (result != 'SUCCESS') {
      if (!mounted) return;
      _showSnack(result, success: false);
      return;
    }
    if (!mounted) return;
    _showSnack('Đã xóa ghi chú');
  }





  Future<void> _showNoteQuickActions(Note note) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final creatorEmail = note.createdByEmail.toLowerCase().trim();
    final isAdmin = AppState.currentUserRole.toLowerCase() == 'admin';
    final isOwner = (creatorEmail.isNotEmpty && creatorEmail == myEmail) ||
        (creatorEmail.isEmpty && note.groupId.isEmpty && note.sharedWith.isEmpty);

    final isGroupNote = note.groupId.isNotEmpty;
    bool canManageGroup = false;
    if (isGroupNote) {
      canManageGroup = await FirebaseService.canCurrentUserManageGroupTasks(note.groupId);
    }

    // Quyền chỉnh sửa (Dành cho người tạo, Admin, hoặc Trưởng nhóm/Điều phối)
    final canEdit = isOwner || isAdmin || canManageGroup;
    
    // Quyền xóa vĩnh viễn (Chỉ dành cho Admin hoặc Trưởng nhóm/Điều phối nếu là group note)
    // Nếu là note cá nhân thì owner được xóa
    final canDeletePermanently = isAdmin || canManageGroup || (!isGroupNote && isOwner);

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
                note.isPinnedByUser ? Icons.push_pin : Icons.push_pin_outlined,
                color: note.isPinnedByUser ? Colors.amber : null,
              ),
              title: Text(note.isPinnedByUser ? 'Bỏ ghim khỏi màn hình chính' : 'Ghim vào màn hình chính'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleNotePin(note);
              },
            ),

            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Xóa khỏi màn hình chính'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final result = await FirebaseService.hideNoteForMe(note.id);
                if (result == 'SUCCESS') {
                  _showSnack('Đã ẩn ghi chú khỏi màn hình chính');
                } else {
                  _showSnack(result, success: false);
                }
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

            if (isOwner && !isGroupNote)
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Chia sẻ ghi chú'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _shareNote(note);
                },
              ),

            if (canDeletePermanently)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(note.groupId.isNotEmpty ? 'Xóa vĩnh viễn cho cả nhóm' : 'Xóa ghi chú'),
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

  void _shareNote(Note note) {
    NoteUtils.showShareSheet(
      context,
      note,
      onShareSuccess: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _showAdvancedFiltersSheet() async {
    final creatorCtrl = TextEditingController(text: _filterCreator);
    final assigneeCtrl = TextEditingController(text: _filterAssignee);
    DateTime? createdDate = _filterCreatedDate;
    DateTime? deadline = _filterDeadline;
    var attachmentMode = _filterHasAttachments == null
        ? 'all'
        : (_filterHasAttachments! ? 'with' : 'without');
    const allowedTodoStatuses = {
      'all',
      TodoStatus.todo,
      TodoStatus.doing,
      TodoStatus.done,
      TodoStatus.overdue,
    };
    var todoStatus = allowedTodoStatuses.contains(_filterTodoStatus)
        ? _filterTodoStatus
        : 'all';
    var priority = _filterPriority;
    var noteType = _filterNoteType;
    var isPinned = _filterIsPinned;
    var hasReminder = _filterHasReminder;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Tìm kiếm nâng cao',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              creatorCtrl.clear();
                              assigneeCtrl.clear();
                              createdDate = null;
                              deadline = null;
                              attachmentMode = 'all';
                              todoStatus = 'all';
                              priority = 'all';
                              noteType = 'all';
                              isPinned = null;
                              hasReminder = null;
                            });
                          },
                          child: const Text('Đặt lại'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _FilterSection(
                      title: 'Thông tin người dùng',
                      children: [
                        TextField(
                          controller: creatorCtrl,
                          decoration: InputDecoration(
                            labelText: 'Người tạo',
                            hintText: 'Tên hoặc email...',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: assigneeCtrl,
                          decoration: InputDecoration(
                            labelText: 'Người được giao (Nhóm)',
                            hintText: 'Tên hoặc email...',
                            prefixIcon: const Icon(
                              Icons.assignment_ind_outlined,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FilterSection(
                      title: 'Thời gian',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DateFilterTile(
                                label: 'Ngày tạo',
                                date: createdDate,
                                icon: Icons.today_outlined,
                                onTap: () async {
                                  final picked = await _pickFilterDate(
                                    createdDate,
                                  );
                                  if (picked != null) {
                                    setSheetState(() => createdDate = picked);
                                  }
                                },
                                onClear: () =>
                                    setSheetState(() => createdDate = null),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DateFilterTile(
                                label: 'Deadline',
                                date: deadline,
                                icon: Icons.event_outlined,
                                onTap: () async {
                                  final picked = await _pickFilterDate(
                                    deadline,
                                  );
                                  if (picked != null) {
                                    setSheetState(() => deadline = picked);
                                  }
                                },
                                onClear: () =>
                                    setSheetState(() => deadline = null),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FilterSection(
                      title: 'Loại ghi chú & Ưu tiên',
                      children: [
                        Text(
                          'Loại ghi chú',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _ChoiceChip(
                              label: 'Tất cả',
                              selected: noteType == 'all',
                              onSelected: (s) =>
                                  setSheetState(() => noteType = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _ChoiceChip(
                              label: 'Văn bản',
                              selected: noteType == 'note',
                              onSelected: (s) =>
                                  setSheetState(() => noteType = 'note'),
                            ),
                            const SizedBox(width: 8),
                            _ChoiceChip(
                              label: 'Công việc',
                              selected: noteType == 'todo',
                              onSelected: (s) =>
                                  setSheetState(() => noteType = 'todo'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Mức độ ưu tiên',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ChoiceChip(
                                label: 'Tất cả',
                                selected: priority == 'all',
                                onSelected: (s) =>
                                    setSheetState(() => priority = 'all'),
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Thấp',
                                selected: priority == NotePriority.low,
                                onSelected: (s) => setSheetState(
                                  () => priority = NotePriority.low,
                                ),
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Trung bình',
                                selected: priority == NotePriority.medium,
                                onSelected: (s) => setSheetState(
                                  () => priority = NotePriority.medium,
                                ),
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Cao',
                                selected: priority == NotePriority.high,
                                onSelected: (s) => setSheetState(
                                  () => priority = NotePriority.high,
                                ),
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Khẩn cấp',
                                selected: priority == NotePriority.urgent,
                                onSelected: (s) => setSheetState(
                                  () => priority = NotePriority.urgent,
                                ),
                                color: Colors.deepOrange,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Khác',
                                selected: priority == NotePriority.custom,
                                onSelected: (s) => setSheetState(
                                  () => priority = NotePriority.custom,
                                ),
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FilterSection(
                      title: 'Nội dung & Trạng thái',
                      children: [
                        Text(
                          'Tệp đính kèm',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ChoiceChip(
                                label: 'Tất cả',
                                selected: attachmentMode == 'all',
                                onSelected: (s) =>
                                    setSheetState(() => attachmentMode = 'all'),
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Có tệp',
                                selected: attachmentMode == 'with',
                                onSelected: (s) => setSheetState(
                                  () => attachmentMode = 'with',
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Không có tệp',
                                selected: attachmentMode == 'without',
                                onSelected: (s) => setSheetState(
                                  () => attachmentMode = 'without',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Trạng thái công việc nhóm',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ChoiceChip(
                                label: 'Tất cả',
                                selected: todoStatus == 'all',
                                onSelected: (s) =>
                                    setSheetState(() => todoStatus = 'all'),
                              ),
                              for (final status in [
                                TodoStatus.todo,
                                TodoStatus.doing,
                                TodoStatus.done,
                                TodoStatus.overdue,
                              ]) ...[
                                const SizedBox(width: 8),
                                _ChoiceChip(
                                  label: status == TodoStatus.overdue
                                      ? 'Trễ hạn'
                                      : TodoStatus.label(status),
                                  selected: todoStatus == status,
                                  onSelected: (s) =>
                                      setSheetState(() => todoStatus = status),
                                  color: status == TodoStatus.overdue
                                      ? Colors.red
                                      : null,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _FilterSection(
                      title: 'Trạng thái đặc biệt',
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ChoiceChip(
                                label: 'Đã ghim',
                                selected: isPinned == true,
                                onSelected: (s) => setSheetState(
                                  () => isPinned = s ? true : null,
                                ),
                                color: Colors.indigo,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Chưa ghim',
                                selected: isPinned == false,
                                onSelected: (s) => setSheetState(
                                  () => isPinned = s ? false : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Có nhắc nhở',
                                selected: hasReminder == true,
                                onSelected: (s) => setSheetState(
                                  () => hasReminder = s ? true : null,
                                ),
                                color: Colors.deepPurple,
                              ),
                              const SizedBox(width: 8),
                              _ChoiceChip(
                                label: 'Không nhắc nhở',
                                selected: hasReminder == false,
                                onSelected: (s) => setSheetState(
                                  () => hasReminder = s ? false : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _filterCreator = creatorCtrl.text;
                          _filterAssignee = assigneeCtrl.text;
                          _filterCreatedDate = createdDate;
                          _filterDeadline = deadline;
                          _filterHasAttachments = switch (attachmentMode) {
                            'with' => true,
                            'without' => false,
                            _ => null,
                          };
                          _filterTodoStatus = todoStatus;
                          _filterPriority = priority;
                          _filterNoteType = noteType;
                          _filterIsPinned = isPinned;
                          _filterHasReminder = hasReminder;
                        });
                        Navigator.pop(sheetContext);
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Áp dụng bộ lọc',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _filterCreator = '';
                          _filterAssignee = '';
                          _filterCreatedDate = null;
                          _filterDeadline = null;
                          _filterHasAttachments = null;
                          _filterTodoStatus = 'all';
                          _filterPriority = 'all';
                          _filterNoteType = 'all';
                          _filterIsPinned = null;
                          _filterHasReminder = null;
                        });
                        Navigator.pop(sheetContext);
                      },
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: const Text(
                        'Xóa tất cả bộ lọc',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    creatorCtrl.dispose();
    assigneeCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (context) => StreamBuilder<int>(
                stream: FirebaseService.menuNotificationsCountStream(),
                builder: (context, menuSnap) {
                  final menuCount = menuSnap.data ?? 0;
                  return IconButton(
                    icon: Badge(
                      isLabelVisible: menuCount > 0,
                      label: Text(menuCount.toString()),
                      child: const Icon(Icons.menu),
                    ),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  );
                },
              ),
            ),
            title: Text(
              _viewMode == 'SHARED'
                  ? 'Được chia sẻ với tôi'
                  : 'Ghi chú của tôi',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              if (_isOffline)
                const Tooltip(
                  message: 'Đang ở chế độ ngoại tuyến',
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Icon(Icons.cloud_off, color: Colors.orange),
                  ),
                ),
              StreamBuilder<int>(
                stream: FirebaseService.bellRequestsCountStream(),
                builder: (context, bellSnap) {
                  return _buildNotificationBell(bellSnap.data ?? 0);
                },
              ),
            ],
          ),
          drawer: StreamBuilder<int>(
            stream: FirebaseService.bellRequestsCountStream(),
            builder: (context, bellSnap) {
              return _buildDrawer(bellSnap.data ?? 0);
            },
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchBar(),
              _buildAdvancedSearchRow(),
              if (_hasAdvancedFilters) _buildActiveFiltersBar(),
              _buildLabelFilters(),
              Expanded(child: _buildNotesList()),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateEditNoteScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Tạo mới'),
          ),
        );
  }

  Widget _buildNotificationBell(int totalCount) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const RequestsScreen(),
              ),
            );
          },
        ),
        if (totalCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                '$totalCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm tiêu đề, nội dung...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildAdvancedSearchRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _FilterActionButton(
            icon: Icons.tune_rounded,
            label: 'Bộ lọc',
            onTap: _showAdvancedFiltersSheet,
            isActive: _hasAdvancedFilters,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _FilterActionButton(
            icon: Icons.sort_rounded,
            label: 'Sắp xếp',
            onTap: _showSortSheet,
            color: colorScheme.secondary,
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sắp xếp theo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            _SortOption(
              label: 'Mới nhất trước',
              icon: Icons.calendar_today,
              selected: _sortBy == 'date_desc',
              onTap: () {
                setState(() => _sortBy = 'date_desc');
                Navigator.pop(context);
              },
            ),
            _SortOption(
              label: 'Cũ nhất trước',
              icon: Icons.history,
              selected: _sortBy == 'date_asc',
              onTap: () {
                setState(() => _sortBy = 'date_asc');
                Navigator.pop(context);
              },
            ),
            _SortOption(
              label: 'Mức độ ưu tiên',
              icon: Icons.flag_outlined,
              selected: _sortBy == 'priority_desc',
              onTap: () {
                setState(() => _sortBy = 'priority_desc');
                Navigator.pop(context);
              },
            ),
            _SortOption(
              label: 'Tiêu đề (A-Z)',
              icon: Icons.sort_by_alpha,
              selected: _sortBy == 'title_asc',
              onTap: () {
                setState(() => _sortBy = 'title_asc');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFiltersBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final activeBadges = _activeFilterBadges;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'Bộ lọc đang áp dụng (${activeBadges.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _filterCreator = '';
                    _filterAssignee = '';
                    _filterCreatedDate = null;
                    _filterDeadline = null;
                    _filterHasAttachments = null;
                    _filterTodoStatus = 'all';
                    _filterPriority = 'all';
                    _filterNoteType = 'all';
                    _filterIsPinned = null;
                    _filterHasReminder = null;
                  });
                },
                child: const Text('Xóa nhanh'),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: activeBadges.map((badge) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [AppState.selectedLabel, ...AppState.labels].map((label) {
          final isSelected = _selectedLabel == label;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
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
    );
  }

  Widget _buildNotesList() {
    return StreamBuilder<List<Note>>(
      stream: _getNotesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !_isOffline) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Note> allNotesList = [];
        if (snapshot.hasData) {
          allNotesList = snapshot.data ?? [];
          if (_viewMode == 'ALL') {
            LocalService.cacheNotes(allNotesList);
          }
        } else if (_isOffline && _viewMode == 'ALL') {
          allNotesList = LocalService.getCachedNotes();
        } else if (snapshot.hasError) {
          return Center(child: Text('Lỗi tải dữ liệu: ${snapshot.error}'));
        } else if (!_isOffline) {
          return const Center(child: CircularProgressIndicator());
        }

        final notes = allNotesList
          ..sort((a, b) {
            if (a.isPinnedByUser != b.isPinnedByUser) return a.isPinnedByUser ? -1 : 1;

            switch (_sortBy) {
              case 'date_asc':
                return a.date.compareTo(b.date);
              case 'priority_desc':
                final pa = NotePriority.weight(a.priority);
                final pb = NotePriority.weight(b.priority);
                return pb.compareTo(pa);
              case 'title_asc':
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              case 'date_desc':
              default:
                return b.date.compareTo(a.date);
            }
          });

        final query = NoteUtils.removeDiacritics(_searchQuery).trim();
        final filteredNotes = notes.where((note) {
          final matchLabel =
              _selectedLabel == AppState.selectedLabel ||
              note.label == _selectedLabel;
          
          bool matchSearch = true;
          if (query.isNotEmpty) {
            final title = NoteUtils.removeDiacritics(note.title);
            final content = NoteUtils.removeDiacritics(note.content);
            final label = NoteUtils.removeDiacritics(note.label);
            final creatorEmail = NoteUtils.removeDiacritics(note.createdByEmail);
            final creatorName = NoteUtils.removeDiacritics(note.createdByName);
            
            matchSearch = title.contains(query) ||
                content.contains(query) ||
                label.contains(query) ||
                creatorEmail.contains(query) ||
                creatorName.contains(query) ||
                note.todos.any(
                  (todo) {
                    final task = NoteUtils.removeDiacritics(todo.task);
                    final assigneeEmail = NoteUtils.removeDiacritics(todo.assigneeEmail);
                    final assigneeName = NoteUtils.removeDiacritics(todo.assigneeName);
                    return task.contains(query) ||
                        (note.groupId.isNotEmpty &&
                            (assigneeEmail.contains(query) ||
                                assigneeName.contains(query)));
                  },
                );
          }
          
          final isHidden = note.hiddenBy.contains(AppState.currentUserEmail.toLowerCase().trim());
          return matchLabel && matchSearch && _matchesAdvancedFilters(note) && !isHidden;
        }).toList();

        if (filteredNotes.isEmpty) {
          return _EmptyState(
            icon: Icons.search_off,
            text: _viewMode == 'SHARED'
                ? 'Chưa có ai chia sẻ ghi chú cho bạn'
                : 'Chưa có ghi chú nào',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          itemCount: filteredNotes.length,
          itemBuilder: (context, index) {
            return _buildNoteCard(filteredNotes[index]);
          },
        );
      },
    );
  }

  Widget _buildNoteCard(Note note) {
    final isSharedWithMe = _viewMode == 'SHARED';
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
    final titleColor = colorScheme.onSurface;
    final styledTitleColor = note.resolvedTitleColor ?? titleColor;
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
                                  : FontWeight.w600,
                              fontStyle: note.titleIsItalic
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              decoration: note.titleIsUnderlined
                                  ? TextDecoration.underline
                                  : null,
                              color: styledTitleColor,
                            ),
                          ),
                        ),
                        if (isSharedWithMe)
                          Icon(Icons.group, size: 16, color: colorScheme.error),
                        if (note.isPinnedByUser) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.push_pin,
                            size: 16,
                            color: Colors.amber.shade700,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (note.isTodo) ...[
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor:
                                  colorScheme.surfaceContainerHighest,
                              color: accentColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$completedTodos/${note.todos.length}',
                            style: TextStyle(
                              fontSize: 12,
                              color: mutedText,
                              fontWeight: FontWeight.w600,
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
                        if (note.groupId.isNotEmpty)
                          _InfoChip(
                            label:
                                'Nhóm: ${note.groupName.isNotEmpty ? note.groupName : "Ghi chú nhóm"}',
                            icon: Icons.groups_outlined,
                            color: colorScheme.primary,
                          ),
                        if (note.todos.any(
                          (t) =>
                              t.assigneeEmail.toLowerCase() ==
                              AppState.currentUserEmail.toLowerCase(),
                        ))
                          _InfoChip(
                            label: 'Được giao cho bạn',
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
                        if (note.groupId.isNotEmpty &&
                            note.todos.any((todo) => todo.isOverdue))
                          _InfoChip(
                            label: 'Trễ hạn',
                            icon: Icons.warning_amber_outlined,
                            color: colorScheme.error,
                          ),
                        if (isSharedWithMe)
                          _InfoChip(
                            label: 'Được chia sẻ',
                            icon: Icons.group_outlined,
                            color: colorScheme.error,
                          ),
                      ],
                    ),
                    if (isSharedWithMe && note.createdByName.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 14,
                            color: colorScheme.error.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Chia sẻ bởi: ${note.createdByName}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.error.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      note.date,
                      style: TextStyle(fontSize: 12, color: mutedText),
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

  Widget _buildDrawer(int requestCount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            accountName: Text(
              AppState.currentUserName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
            accountEmail: Text(
              AppState.currentUserEmail,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.85),
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              backgroundImage: avatarImageProvider(
                AppState.currentUserAvatar,
                name: AppState.currentUserName,
              ),
              radius: 36,
            ),
          ),
          _DrawerItem(
            icon: Icons.note,
            title: 'Ghi chú của tôi',
            selected: _viewMode == 'ALL',
            selectedColor: isDark ? Colors.indigoAccent : Colors.indigo,
            onTap: () {
              setState(() => _viewMode = 'ALL');
              Navigator.pop(context);
            },
          ),
          StreamBuilder<int>(
            stream: FirebaseService.unreadSharedNotesCountStream(),
            builder: (context, sharedCountSnap) {
              return _DrawerItem(
                icon: Icons.group,
                title: 'Được chia sẻ với tôi',
                selected: _viewMode == 'SHARED',
                badgeCount: sharedCountSnap.data ?? 0,
                selectedColor: isDark ? Colors.redAccent : Colors.red,
                onTap: () {
                  setState(() => _viewMode = 'SHARED');
                  FirebaseService.markAllSharedNotesAsViewed();
                  Navigator.pop(context);
                },
              );
            },
          ),
          const Divider(),
          StreamBuilder<int>(
            stream: FirebaseService.unreadGroupMessagesCountStream(),
            builder: (context, unreadSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getGroupInvitesStream(),
                builder: (context, invitesSnap) {
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseService.getGroupRequestsForLeaderStream(),
                    builder: (context, requestsSnap) {
                      final total = (invitesSnap.data?.docs.length ?? 0) +
                          (requestsSnap.data?.docs.length ?? 0) +
                          (unreadSnap.data ?? 0);
                      return _DrawerItem(
                        icon: Icons.group_work,
                        title: 'Nhóm của tôi',
                        badgeCount: total,
                        selectedColor: isDark ? Colors.tealAccent : Colors.teal,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GroupsListScreen(),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          const Divider(),
          _DrawerItem(
            icon: Icons.calendar_month,
            title: 'Lịch biểu',
            selectedColor: isDark ? Colors.deepPurpleAccent : Colors.deepPurple,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CalendarScreen()),
              );
            },
          ),
          _DrawerItem(
            icon: Icons.bar_chart,
            title: 'Thống kê',
            selectedColor: isDark ? Colors.orangeAccent : Colors.orange,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StatisticsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          StreamBuilder<int>(
            stream: FirebaseService.unreadChatMessagesCountStream(),
            builder: (context, unreadSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getFriendRequestsStream(),
                builder: (context, snapshot) {
                  final friendCount = snapshot.data?.docs.length ?? 0;
                  final unreadCount = unreadSnap.data ?? 0;
                  return _DrawerItem(
                    icon: Icons.contacts,
                    title: 'Danh bạ của tôi',
                    badgeCount: friendCount + unreadCount,
                    selectedColor: isDark ? Colors.blueAccent : Colors.blue,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ContactsScreen(),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _InfoChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: chipColor)),
        ],
      ),
    );
  }
}

class _FilterActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final Color? color;

  const _FilterActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = color ?? colorScheme.primary;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 18,
        color: isActive ? colorScheme.onPrimary : activeColor,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: isActive ? colorScheme.onPrimary : colorScheme.onSurface,
          fontSize: 13,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? activeColor : null,
        side: isActive
            ? BorderSide.none
            : BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        minimumSize: const Size(0, 40),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  final int badgeCount;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.selectedColor,
    required this.onTap,
    this.selected = false,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? selectedColor
        : Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: selectedColor),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          color: color,
        ),
      ),
      trailing: badgeCount > 0
          ? Badge(
              label: Text('$badgeCount'),
              child: const SizedBox.shrink(),
            )
          : null,
      onTap: onTap,
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 72, color: colorScheme.primary),
            ),
            const SizedBox(height: 32),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Hãy bắt đầu ghi lại những ý tưởng tuyệt vời của bạn ngay bây giờ!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FilterSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _DateFilterTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateFilterTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDate = date != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: hasDate
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasDate ? colorScheme.primary : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: hasDate ? colorScheme.primary : null),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    hasDate
                        ? '${date!.day}/${date!.month}/${date!.year}'
                        : 'Bất kỳ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasDate ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (hasDate)
              GestureDetector(
                onTap: () {
                  onClear();
                },
                child: const Icon(Icons.close, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color? color;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor:
          color?.withValues(alpha: 0.2) ?? colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected
            ? (color ?? colorScheme.primary)
            : colorScheme.onSurfaceVariant,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(
        color: selected
            ? (color ?? colorScheme.primary)
            : colorScheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCheckmark: false,
    );
  }
}




