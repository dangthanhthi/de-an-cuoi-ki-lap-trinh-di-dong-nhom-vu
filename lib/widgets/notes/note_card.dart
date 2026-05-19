import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/app_models.dart';
import '../../controllers/app_state.dart';
import '../../views/note_detail_screen.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final String viewMode;
  final Function(Note) onLongPress;

  const NoteCard({
    super.key,
    required this.note,
    required this.viewMode,
    required this.onLongPress,
  });

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

  @override
  Widget build(BuildContext context) {
    final isSharedWithMe = viewMode == 'SHARED';
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    final isOwner = note.createdByEmail.toLowerCase().trim() == myEmail;
    
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
    
    final completedTodos = note.todos
        .where((todo) => todo.isDone || todo.status == TodoStatus.done)
        .length;
    final progress = note.isTodo && note.todos.isNotEmpty
        ? completedTodos / note.todos.length
        : 0.0;
    final percentage = (progress * 100).toInt();
    final priority = NotePriority.normalize(note.priority);

    return RepaintBoundary(
      child: Card(
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
            onLongPress(note);
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
                                decoration: null,
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
                                backgroundColor: colorScheme.surfaceContainerHighest,
                                color: accentColor,
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$percentage% ($completedTodos/${note.todos.length})',
                              style: TextStyle(
                                fontSize: 10,
                                color: mutedText,
                                fontWeight: FontWeight.bold,
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
                        ],
                      ),
                      if (!isOwner && note.groupId.isEmpty && (note.createdByName.isNotEmpty || note.createdByEmail.isNotEmpty)) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorScheme.error.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_pin_circle_outlined,
                                size: 14,
                                color: colorScheme.error.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Được chia sẻ bởi: ${note.createdByName.isNotEmpty ? note.createdByName : note.createdByEmail}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.error.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.onSurfaceVariant;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: effectiveColor.withValues(alpha: 0.2)),
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
              fontWeight: FontWeight.w600,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
