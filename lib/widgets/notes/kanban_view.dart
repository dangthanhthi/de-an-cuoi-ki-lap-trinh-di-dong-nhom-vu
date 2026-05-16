import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_models.dart';
import '../../controllers/firebase_service.dart';
import '../../views/create_edit_note_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      height: maxHeight,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
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
            child: tasks.isEmpty
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
                    itemCount: tasks.length,
                    itemBuilder: (context, idx) =>
                        _buildTaskCard(context, tasks[idx]),
                  ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Map<String, dynamic> t) {
    final note = t['note'] as Note;
    final type = t['type'] as String;
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = t['status'] == TodoStatus.done;

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
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CreateEditNoteScreen(note: note),
              ),
            );
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showQuickActions(context, t);
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
                        mainText,
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
                                  : (note.label.isNotEmpty
                                        ? note.label
                                        : 'Ghi chú'),
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
      ),
    );
  }

  void _showQuickActions(BuildContext context, Map<String, dynamic> t) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentStatus = t['status'] as String;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
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
                onTap: () => _updateStatus(context, t, TodoStatus.todo),
              ),
            if (currentStatus != TodoStatus.doing)
              _ActionTile(
                title: 'Cập nhật thành Đang làm',
                icon: Icons.pending_actions_rounded,
                color: colorScheme.primary,
                onTap: () => _updateStatus(context, t, TodoStatus.doing),
              ),
            if (currentStatus != TodoStatus.done)
              _ActionTile(
                title: 'Cập nhật thành Hoàn thành',
                icon: Icons.check_circle_outline_rounded,
                color: colorScheme.tertiary,
                onTap: () => _updateStatus(context, t, TodoStatus.done),
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
    final note = t['note'] as Note;
    final type = t['type'] as String;

    try {
      if (type == 'todo') {
        await FirebaseService.updateTodoStatus(
          note.id,
          t['index'] as int,
          newStatus,
        );
      } else {
        await NoteService.updateNoteStatus(note.id, newStatus);
      }
      HapticFeedback.mediumImpact();

      if (context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text(
                  'Cập nhật trạng thái thành công',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
