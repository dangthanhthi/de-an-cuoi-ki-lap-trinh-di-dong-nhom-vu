import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/statistics_controller.dart';
import 'note_detail_screen.dart';
import '../models/app_models.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  int _selectedDays = 7; // 7, 30, 0 (All)

  Future<List<Note>> _loadGroupNotes(List<QueryDocumentSnapshot> groups) async {
    final groupNotes = await Future.wait(
      groups.map((group) => FirebaseService.getGroupNotesOnce(group.id)),
    );
    return groupNotes.expand((notes) => notes).toList();
  }

  List<Note> _dedupeNotes(List<Note> notes) {
    final map = <String, Note>{};
    for (final note in notes) {
      map[note.id] = note;
    }
    return map.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thống kê & Phân tích'),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_list),
            initialValue: _selectedDays,
            onSelected: (value) => setState(() => _selectedDays = value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 7, child: Text('7 ngày qua')),
              const PopupMenuItem(value: 30, child: Text('30 ngày qua')),
              const PopupMenuItem(value: 0, child: Text('Tất cả thời gian')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getMyNotesStream(),
        builder: (context, mySnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getSharedNotesStream(),
            builder: (context, sharedSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getMyGroupsStream(),
                builder: (context, groupSnapshot) {
                  if (mySnapshot.hasError || sharedSnapshot.hasError || groupSnapshot.hasError) {
                    return const Center(child: Text('Không tải được dữ liệu thống kê'));
                  }
                  if (mySnapshot.connectionState == ConnectionState.waiting ||
                      sharedSnapshot.connectionState == ConnectionState.waiting ||
                      groupSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final groups = groupSnapshot.data?.docs ?? [];
                  final baseNotes = [
                    ...(mySnapshot.data?.docs ?? []).map(FirebaseService.noteFromDocument),
                    ...(sharedSnapshot.data?.docs ?? []).map(FirebaseService.noteFromDocument),
                  ];

                  return FutureBuilder<List<Note>>(
                    future: _loadGroupNotes(groups),
                    builder: (context, groupNotesSnapshot) {
                      if (groupNotesSnapshot.hasError) {
                        return const Center(child: Text('Không tải được dữ liệu nhóm'));
                      }
                      if (groupNotesSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final notes = _dedupeNotes([
                        ...baseNotes,
                        ...(groupNotesSnapshot.data ?? const []),
                      ]);
                      final stats = StatisticsController.calculateStats(notes, days: _selectedDays);
                      return _StatsView(stats: stats, notes: notes, selectedDays: _selectedDays);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatsView extends StatelessWidget {
  final StatsData stats;
  final List<Note> notes;
  final int selectedDays;

  const _StatsView({required this.stats, required this.notes, required this.selectedDays});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _EfficiencyCircularCard(
          completed: stats.done,
          total: stats.totalItems,
          value: stats.doneRate,
          title: 'Hiệu suất ghi chú',
          subtitle: 'Bạn đã hoàn thành ${stats.done} trên ${stats.totalItems} ghi chú.',
        ),
        const SizedBox(height: 32),
        _SectionTitle(title: 'Tổng quan công việc'),
        const SizedBox(height: 16),
        _buildMetricsGrid(context),
        const SizedBox(height: 40),
        _SectionTitle(
          title: 'Hoạt động tuần này',
          trailing: 'Dựa trên việc hoàn thành',
        ),
        const SizedBox(height: 16),
        _ActivityBarChart(data: stats.dailyActivity, color: colorScheme.primary),
        const SizedBox(height: 40),
        
        if (stats.topGroups.isNotEmpty) ...[
          _SectionTitle(title: 'Nhóm hoạt động nhiều nhất'),
          const SizedBox(height: 16),
          ...stats.topGroups.map((group) => _GroupActivityTile(group: group)),
          const SizedBox(height: 40),
        ],

        if (stats.topSharers.isNotEmpty) ...[
          _SectionTitle(title: 'Top người chia sẻ'),
          const SizedBox(height: 16),
          ...stats.topSharers.map((sharer) => _SharerActivityTile(sharer: sharer)),
          const SizedBox(height: 40),
        ],

        _SectionTitle(title: 'Phân bổ ưu tiên'),
        const SizedBox(height: 16),
        _PriorityBreakdown(priorityCounts: stats.priorityCounts),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMetricsGrid(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    void showNotes(String title, List<Note> filteredNotes) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => _FilteredNotesList(
            title: title, 
            notes: filteredNotes,
            scrollController: scrollController,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 3 : 2;
        final spacing = 12.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        
        final cards = [
          _MetricCard(
            icon: Icons.assignment_outlined,
            label: 'Tổng ghi chú',
            value: '${stats.totalItems}',
            color: colorScheme.primary,
            onTap: () => showNotes('Tất cả ghi chú', notes.where((n) {
              final myEmail = (AppState.currentUserEmail).toLowerCase().trim();
              final isCreator = n.createdByEmail.toLowerCase().trim() == myEmail;
              final isAssignee = n.todos.any((t) => t.assigneeEmail.toLowerCase().trim() == myEmail);
              return isCreator || isAssignee;
            }).toList()),
          ),
          _MetricCard(
            icon: Icons.check_circle_outline,
            label: 'Đã hoàn thành',
            value: '${stats.done}',
            color: Colors.green,
            onTap: () => showNotes('Ghi chú đã xong', notes.where((n) {
              final myEmail = (AppState.currentUserEmail).toLowerCase().trim();
              final myTodos = n.todos.where((t) => t.assigneeEmail.toLowerCase().trim() == myEmail).toList();
              final isCreator = n.createdByEmail.toLowerCase().trim() == myEmail;
              
              if (myTodos.isNotEmpty) {
                return myTodos.every((t) => t.isDone || t.status == TodoStatus.done);
              } else if (isCreator) {
                if (n.todos.isEmpty) return true;
                return n.todos.every((t) => t.isDone || t.status == TodoStatus.done);
              }
              return false;
            }).toList()),
          ),
          _MetricCard(
            icon: Icons.error_outline,
            label: 'Trễ hạn',
            value: '${stats.overdue}',
            color: Colors.red,
            onTap: () => showNotes('Công việc trễ hạn', notes.where((n) => n.todos.any((t) => t.isOverdue)).toList()),
          ),
          _MetricCard(
            icon: Icons.pending_actions,
            label: 'Đang làm',
            value: '${stats.doing}',
            color: Colors.orange,
            onTap: () => showNotes('Đang thực hiện', notes.where((n) {
              if (n.todos.isEmpty) return false;
              final hasDone = n.todos.any((t) => t.isDone || t.status == TodoStatus.done);
              final allDone = n.todos.every((t) => t.isDone || t.status == TodoStatus.done);
              return (hasDone && !allDone) || n.todos.any((t) => t.status == TodoStatus.doing);
            }).toList()),
          ),
          _MetricCard(
            icon: Icons.list_alt,
            label: 'Chưa bắt đầu',
            value: '${stats.todo}',
            color: Colors.blue,
            onTap: () => showNotes('Chưa bắt đầu', notes.where((n) {
              if (n.todos.isEmpty) return true;
              return n.todos.every((t) => t.status == TodoStatus.todo && !t.isDone);
            }).toList()),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

class _EfficiencyCircularCard extends StatelessWidget {
  final int completed;
  final int total;
  final double value;
  final String? title;
  final String? subtitle;

  const _EfficiencyCircularCard({
    required this.completed,
    required this.total,
    required this.value,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title ?? 'Hiệu suất tổng thể',
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle ?? 'Bạn đã hoàn thành $completed trên $total công việc.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    value >= 0.8 ? 'Cực kỳ hiệu quả! 🚀' : value >= 0.5 ? 'Đang tiến triển tốt 👍' : 'Cần cố gắng thêm 💪',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(
                '${(value * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  const _MetricCard({required this.icon, required this.label, required this.value, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 16),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityBarChart extends StatelessWidget {
  final Map<int, int> data;
  final Color color;

  const _ActivityBarChart({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxCount = data.values.fold(0, (max, e) => e > max ? e : max);
    final days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    
    return Container(
      height: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(7, (index) {
          final dayIndex = index + 1;
          final count = data[dayIndex] ?? 0;
          final heightFactor = maxCount == 0 ? 0.0 : count / maxCount;
          
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (count > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('$count', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  height: (100 * heightFactor).clamp(4.0, 100.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color, color.withValues(alpha: 0.6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 12),
                Text(days[index], style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _SharerActivityTile extends StatelessWidget {
  final SharerStat sharer;
  const _SharerActivityTile({required this.sharer});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_outline, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sharer.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  sharer.email,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${sharer.count} ghi chú',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupActivityTile extends StatelessWidget {
  final GroupStat group;
  const _GroupActivityTile({required this.group});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final efficiency = group.efficiency;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.groups_outlined, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${group.completedCount}/${group.totalCount} công việc hoàn thành',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                '${(efficiency * 100).toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: efficiency >= 0.8 ? Colors.green : efficiency >= 0.5 ? colorScheme.primary : colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: efficiency,
              minHeight: 6,
              backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                efficiency >= 0.8 ? Colors.green : efficiency >= 0.5 ? colorScheme.primary : colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _PriorityBreakdown extends StatelessWidget {
  final Map<String, int> priorityCounts;
  const _PriorityBreakdown({required this.priorityCounts});

  @override
  Widget build(BuildContext context) {
    final priorities = [NotePriority.urgent, NotePriority.high, NotePriority.medium, NotePriority.low];
    final colors = [Colors.red.shade900, Colors.red, Colors.orange, Colors.blue];
    
    return Column(
      children: List.generate(priorities.length, (index) {
        final p = priorities[index];
        final count = priorityCounts[p] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[index], shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Text(NotePriority.label(p), style: const TextStyle(fontWeight: FontWeight.w500))),
              Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  const _SectionTitle({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _FilteredNotesList extends StatelessWidget {
  final String title;
  final List<Note> notes;
  final ScrollController scrollController;

  const _FilteredNotesList({required this.title, required this.notes, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: notes.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          );
        }
        final note = notes[index - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            title: Text(note.title.isNotEmpty ? note.title : 'Không có tiêu đề', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(note.label.isNotEmpty ? note.label : 'Không có nhãn'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NoteDetailScreen(note: note),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
