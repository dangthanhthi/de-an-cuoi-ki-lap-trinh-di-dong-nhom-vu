import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_models.dart';
import '../../views/create_edit_note_screen.dart';
import '../../views/note_detail_screen.dart';
import '../../controllers/app_state.dart';
import '../../utils/snack_utils.dart';

class KanbanView extends StatelessWidget {
  final List<Note> notes;
  final String viewMode;

  const KanbanView({super.key, required this.notes, required this.viewMode});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Flatten notes into tasks (each todo or note itself is a task)
    final tasks = <Map<String, dynamic>>[];
    for (final note in notes) {
      if (note.isTodo && note.todos.isNotEmpty) {
        for (var i = 0; i < note.todos.length; i++) {
          tasks.add({
            'type': 'todo',
            'note': note,
            'todo': note.todos[i],
            'index': i,
            'status': note.todos[i].status,
          });
        }
      } else {
        // Regular note or empty todo list
        tasks.add({'type': 'note', 'note': note, 'status': note.status});
      }
    }

    final columns = [
      (TodoStatus.todo, 'Cần làm', Icons.list_alt_rounded, colorScheme.outline),
      (
        TodoStatus.doing,
        'Đang làm',
        Icons.pending_actions_rounded,
        colorScheme.primary,
      ),
      (
        TodoStatus.done,
        'Hoàn thành',
        Icons.check_circle_outline_rounded,
        colorScheme.tertiary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          color: colorScheme.surface.withValues(alpha: 0.5),
          height: constraints.maxHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns.map((col) {
                final colStatus = col.$1;
                final colTasks = tasks
                    .where((t) => t['status'] == colStatus)
                    .toList();

                return _KanbanColumn(
                  status: colStatus,
                  title: col.$2,
                  icon: col.$3,
                  color: col.$4,
                  tasks: colTasks,
                  maxHeight: constraints.maxHeight - 20,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  final String status;
  final String title;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> tasks;
  final double maxHeight;

  const _KanbanColumn({
    required this.status,
    required this.title,
    required this.icon,
    required this.color,
    required this.tasks,
    required this.maxHeight,
  });

  int _getTaskScore(Map<String, dynamic> t, String myEmail) {
    final type = t['type'] as String;
    final note = t['note'] as Note;
    final noteAssignedTo = note.assignedTo.map((e) => e.toLowerCase().trim()).toList();

    if (type == 'todo') {
      final todo = t['todo'] as TodoItem;
      final assignee = todo.assigneeEmail.toLowerCase().trim();
      if (assignee == myEmail) return 2;
      if (assignee.isEmpty && noteAssignedTo.contains(myEmail)) return 2;
      if (assignee.isEmpty && noteAssignedTo.isEmpty) {
        if (note.createdByEmail.toLowerCase().trim() == myEmail) return 2;
        return 1;
      }
      return 0;
    } else {
      if (noteAssignedTo.contains(myEmail)) return 2;
      if (noteAssignedTo.isEmpty) {
        if (note.createdByEmail.toLowerCase().trim() == myEmail) return 2;
        return 1;
      }
      return 0;
    }
  }

  bool _isNotMyTask(Map<String, dynamic> t, String myEmail) {
    final type = t['type'] as String;
    final note = t['note'] as Note;
    final noteAssignedTo = note.assignedTo.map((e) => e.toLowerCase().trim()).toList();

    if (type == 'todo') {
      final todo = t['todo'] as TodoItem;
      final assignee = todo.assigneeEmail.toLowerCase().trim();
      if (assignee.isNotEmpty) {
        return assignee != myEmail;
      } else {
        if (noteAssignedTo.isNotEmpty) return !noteAssignedTo.contains(myEmail);
        return false;
      }
    } else {
      return noteAssignedTo.isNotEmpty && !noteAssignedTo.contains(myEmail);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();

    final sortedTasks = List<Map<String, dynamic>>.from(tasks);
    sortedTasks.sort((a, b) {
      int scoreA = _getTaskScore(a, myEmail);
      int scoreB = _getTaskScore(b, myEmail);
      return scoreB.compareTo(scoreA);
    });

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return data['status'] != status;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        _updateStatusDirectly(context, data, status);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return Container(
          width: 280,
          height: maxHeight,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: isHovered
                ? colorScheme.primaryContainer.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered ? colorScheme.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tasks.length.toString(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: sortedTasks.isEmpty
                    ? Padding(
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
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: sortedTasks.length,
                        itemBuilder: (context, idx) =>
                            _buildTaskCard(context, sortedTasks[idx], myEmail),
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardContent(
    BuildContext context,
    Map<String, dynamic> t,
    String myEmail, {
    bool dragFeedback = false,
  }) {
    final note = t['note'] as Note;
    final type = t['type'] as String;
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = t['status'] == TodoStatus.done;
    final isNotMine = _isNotMyTask(t, myEmail);

    String mainText = '';
    String? priority;
    if (type == 'todo') {
      final todo = t['todo'] as TodoItem;
      mainText = todo.task;
      priority = todo.priority;
    } else {
      mainText = note.title;
      priority = note.priority;
    }

    return Opacity(
      opacity: isNotMine ? 0.5 : 1.0,
      child: Container(
        width: dragFeedback ? 256 : double.infinity,
        margin: dragFeedback ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dragFeedback ? 0.15 : 0.04),
              blurRadius: dragFeedback ? 16 : 10,
              offset: Offset(0, dragFeedback ? 8 : 4),
            ),
          ],
          border: Border.all(
            color: isDone
                ? Colors.green.withValues(alpha: 0.2)
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      mainText,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        height: 1.4,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? colorScheme.outline : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (priority != 'none' && priority != 'low')
                    _MiniChip(
                      label: _getPriorityLabel(priority),
                      color: _getPriorityColor(priority),
                      icon: Icons.priority_high_rounded,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type == 'todo'
                              ? Icons.description_outlined
                              : Icons.note_outlined,
                          size: 12,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            type == 'todo'
                                ? note.title
                                : (note.label.isNotEmpty ? note.label : 'Ghi chú'),
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
                  if (type == 'todo' && note.label.isNotEmpty)
                    _MiniChip(
                      label: note.label,
                      color: colorScheme.secondary,
                      icon: Icons.label_outline_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Map<String, dynamic> t, String myEmail) {
    final note = t['note'] as Note;
    return LongPressDraggable<Map<String, dynamic>>(
      data: t,
      feedback: Material(
        color: Colors.transparent,
        child: _buildCardContent(context, t, myEmail, dragFeedback: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCardContent(context, t, myEmail),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
            FocusScope.of(context).unfocus();
            _showQuickActions(context, t);
          },
          child: _buildCardContent(context, t, myEmail),
        ),
      ),
    );
  }

  void _confirmDeleteNote(BuildContext context, Note note) async {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    bool hasUnfinishedTasks = false;
    if (note.isTodo) {
      if (note.groupId.isEmpty) {
        hasUnfinishedTasks = note.todos.any((t) => !t.isDone && t.status != TodoStatus.done);
      } else {
        hasUnfinishedTasks = note.todos.any((t) =>
            t.assigneeEmail.toLowerCase().trim() == myEmail &&
            !t.isDone &&
            t.status != TodoStatus.done);
      }
    }

    final String contentText;
    if (note.groupId.isNotEmpty) {
      if (hasUnfinishedTasks) {
        contentText = 'Ghi chú này còn công việc của bạn chưa hoàn thành. Hành động này sẽ xóa ghi chú của CẢ NHÓM. Bạn có chắc chắn muốn xóa không?';
      } else {
        contentText = 'Hành động này sẽ xóa ghi chú cho TẤT CẢ thành viên trong nhóm. Bạn có chắc không?';
      }
    } else {
      if (hasUnfinishedTasks) {
        contentText = 'Ghi chú này còn công việc chưa hoàn thành. Bạn có chắc chắn muốn xóa ghi chú này không?';
      } else {
        contentText = 'Bạn có chắc muốn xóa ghi chú này không?';
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa vĩnh viễn?'),
        content: Text(contentText),
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
      final res = await FirebaseService.deleteNote(note.id, note.title);
      if (context.mounted) {
        if (res != 'SUCCESS') {
          SnackUtils.show(context, res, success: false);
        } else {
          SnackUtils.show(context, 'Đã xóa ghi chú vĩnh viễn');
        }
      }
    }
  }

  Future<void> _showQuickActions(BuildContext context, Map<String, dynamic> t) async {
    final colorScheme = Theme.of(context).colorScheme;
    final currentStatus = t['status'] as String;
    final note = t['note'] as Note;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final creatorEmail = note.createdByEmail.toLowerCase().trim();
    final isAdmin = AppState.currentUserRole.toLowerCase() == 'admin';
    
    final isOwner = (creatorEmail.isNotEmpty && creatorEmail == myEmail) ||
        (creatorEmail.isEmpty && note.groupId.isEmpty && note.sharedWith.isEmpty);

    final bool canManageGroup = note.groupId.isEmpty
        ? true
        : await FirebaseService.canCurrentUserManageGroupTasks(note.groupId);

    final isSharedWithMe = note.sharedWith.any((e) => e.toLowerCase().trim() == myEmail);
    final canEdit = isOwner || 
        isSharedWithMe || 
        (note.groupId.isEmpty && isAdmin) || 
        (note.groupId.isNotEmpty && canManageGroup);
    final canDelete = (note.groupId.isEmpty && isAdmin) || 
        (note.groupId.isNotEmpty ? canManageGroup : isOwner);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Cập nhật trạng thái',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            if (currentStatus != TodoStatus.todo)
              _ActionTile(
                title: 'Di chuyển sang Cần làm',
                icon: Icons.list_alt_rounded,
                color: colorScheme.outline,
                onTap: () => _updateStatus(sheetContext, t, TodoStatus.todo),
              ),
            if (currentStatus != TodoStatus.doing)
              _ActionTile(
                title: 'Cập nhật thành Đang làm',
                icon: Icons.pending_actions_rounded,
                color: colorScheme.primary,
                onTap: () => _updateStatus(sheetContext, t, TodoStatus.doing),
              ),
            if (currentStatus != TodoStatus.done)
              _ActionTile(
                title: 'Cập nhật thành Hoàn thành',
                icon: Icons.check_circle_outline_rounded,
                color: colorScheme.tertiary,
                onTap: () => _updateStatus(sheetContext, t, TodoStatus.done),
              ),
            const SizedBox(height: 12),
            const Divider(),
            if (canEdit)
              _ActionTile(
                title: 'Chỉnh sửa',
                icon: Icons.edit_outlined,
                color: colorScheme.onSurface,
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
            if (canDelete)
              _ActionTile(
                title: 'Xóa vĩnh viễn',
                icon: Icons.delete_outline,
                color: colorScheme.error,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDeleteNote(context, note);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _updateStatus(
    BuildContext context,
    Map<String, dynamic> t,
    String newStatus,
  ) async {
    Navigator.pop(context);
    await _updateStatusDirectly(context, t, newStatus);
  }

  Future<void> _updateStatusDirectly(
    BuildContext context,
    Map<String, dynamic> t,
    String newStatus,
  ) async {
    final note = t['note'] as Note;
    final type = t['type'] as String;

    try {
      final String res;
      if (type == 'todo') {
        res = await FirebaseService.updateTodoStatus(
          note.id,
          t['index'] as int,
          newStatus,
        );
      } else {
        res = await NoteService.updateNoteStatus(note.id, newStatus);
      }

      if (res != 'SUCCESS') {
        if (context.mounted) {
          SnackUtils.show(context, res, success: false);
        }
        return;
      }

      HapticFeedback.mediumImpact();

      if (context.mounted) {
        SnackUtils.show(context, 'Cập nhật trạng thái thành công');
      }
    } catch (e) {
      if (context.mounted) {
        SnackUtils.show(context, 'Lỗi: ${e.toString()}', success: false);
      }
    }
  }

  String _getPriorityLabel(String priority) {
    switch (priority) {
      case 'high':
        return 'Cao';
      case 'medium':
        return 'Vừa';
      default:
        return 'Thấp';
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _MiniChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
    );
  }
}
