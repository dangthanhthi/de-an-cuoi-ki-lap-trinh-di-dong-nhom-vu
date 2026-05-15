import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/firebase_service.dart';
import '../controllers/statistics_controller.dart';
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
        _ProgressSummary(
          completed: stats.done,
          total: stats.totalNotes,
          value: stats.doneRate,
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: 'Tổng quan công việc'),
        const SizedBox(height: 12),
        _buildMetricsGrid(context),
        const SizedBox(height: 32),
        _SectionTitle(
          title: 'Hoạt động tuần này',
          trailing: 'Dựa trên việc hoàn thành',
        ),
        const SizedBox(height: 16),
        _ActivityBarChart(data: stats.dailyActivity, color: colorScheme.primary),
        const SizedBox(height: 32),
        if (stats.topMembers.isNotEmpty) ...[
          _SectionTitle(title: 'Thành viên tích cực'),
          const SizedBox(height: 12),
          ...stats.topMembers.map((member) => _MemberLeaderboardTile(member: member)),
          const SizedBox(height: 32),
        ],
        _SectionTitle(title: 'Phân bổ ưu tiên'),
        const SizedBox(height: 12),
        _PriorityBreakdown(priorityCounts: stats.priorityCounts),
        const SizedBox(height: 32),
        _SectionTitle(title: 'Nhãn phổ biến'),
        const SizedBox(height: 12),
        _LabelCloud(labelCounts: stats.labelCounts),
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
            label: 'Tổng công việc',
            value: '${stats.totalNotes}',
            color: colorScheme.primary,
            onTap: () => showNotes('Tất cả công việc', notes),
          ),
          _MetricCard(
            icon: Icons.check_circle_outline,
            label: 'Hoàn thành',
            value: '${stats.done}',
            color: Colors.green,
            onTap: () => showNotes('Công việc đã xong', notes.where((n) {
              if (n.todos.isEmpty) return false;
              return n.todos.every((t) => t.isDone || t.status == TodoStatus.done);
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

class _ProgressSummary extends StatelessWidget {
  final int completed;
  final int total;
  final double value;

  const _ProgressSummary({required this.completed, required this.total, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primaryContainer.withValues(alpha: 0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hiệu suất tổng thể',
                style: TextStyle(color: colorScheme.onPrimary, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(value * 100).toInt()}%',
                  style: TextStyle(color: colorScheme.onPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Bạn đã hoàn thành $completed trên $total mục tiêu.',
            style: TextStyle(color: colorScheme.onPrimary.withValues(alpha: 0.8), fontSize: 14),
          ),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              backgroundColor: colorScheme.onPrimary.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
            ),
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

class _MemberLeaderboardTile extends StatelessWidget {
  final MemberStat member;
  const _MemberLeaderboardTile({required this.member});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Text(member.name[0].toUpperCase(), style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
        ),
        title: Text(member.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(member.email, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Text('${member.completedCount} đã xong', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
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

class _LabelCloud extends StatelessWidget {
  final Map<String, int> labelCounts;
  const _LabelCloud({required this.labelCounts});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (labelCounts.isEmpty) return const Text('Chưa có nhãn nào');
    
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labelCounts.entries.map((e) => Chip(
        label: Text(e.key),
        avatar: CircleAvatar(child: Text('${e.value}', style: const TextStyle(fontSize: 10))),
        backgroundColor: colorScheme.surfaceContainerHigh,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      )).toList(),
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
              Navigator.pushNamed(context, '/note_detail', arguments: note);
            },
          ),
        );
      },
    );
  }
}
