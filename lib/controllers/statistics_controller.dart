import '../models/app_models.dart';

class StatisticsController {
  static StatsData calculateStats(List<Note> notes, {int days = 7}) {
    final now = DateTime.now();
    final startTime = days == 0 ? DateTime(2000) : now.subtract(Duration(days: days));
    
    int todo = 0;
    int doing = 0;
    int done = 0;
    int overdue = 0;
    
    final priorityCounts = <String, int>{};
    final labelCounts = <String, int>{};
    final memberStats = <String, MemberStat>{};
    final dailyActivity = <int, int>{}; // weekday index (1-7) -> count
    
    // Initialize daily activity
    for (int i = 1; i <= 7; i++) {
      dailyActivity[i] = 0;
    }

    for (final note in notes) {
      // Basic Status & Priority
      final todos = note.todos;
      if (todos.isNotEmpty) {
        final completedItems = todos.where((t) => t.isDone || t.status == TodoStatus.done).toList();
        
        if (completedItems.length == todos.length) {
          done++;
        } else if (todos.any((t) => t.isOverdue)) {
          overdue++;
          todo++;
        } else if (completedItems.isNotEmpty || todos.any((t) => t.status == TodoStatus.doing)) {
          doing++;
        } else {
          todo++;
        }

        for (final item in todos) {
          // Priority
          final p = NotePriority.normalize(item.priority);
          priorityCounts[p] = (priorityCounts[p] ?? 0) + 1;

          // Member stats
          if (item.isDone || item.status == TodoStatus.done) {
            final email = item.assigneeEmail.isEmpty ? 'Hệ thống' : item.assigneeEmail;
            final name = item.assigneeName.isEmpty ? email : item.assigneeName;
            
            final key = email.toLowerCase().trim();
            if (!memberStats.containsKey(key)) {
              memberStats[key] = MemberStat(email: email, name: name);
            }
            memberStats[key]!.completedCount++;

            // Daily activity (within filter range)
            final completedAt = item.completedAt;
            if (completedAt != null && completedAt.isAfter(startTime)) {
              dailyActivity[completedAt.weekday] = (dailyActivity[completedAt.weekday] ?? 0) + 1;
            }
          }
        }
      } else {
        // Regular note (treat as todo if not group note, or just a generic task)
        todo++;
        final p = NotePriority.normalize(note.priority);
        priorityCounts[p] = (priorityCounts[p] ?? 0) + 1;
      }

      // Labels
      if (note.label.isNotEmpty) {
        labelCounts[note.label] = (labelCounts[note.label] ?? 0) + 1;
      }
    }

    final sortedMembers = memberStats.values.toList()
      ..sort((a, b) => b.completedCount.compareTo(a.completedCount));

    return StatsData(
      todo: todo,
      doing: doing,
      done: done,
      overdue: overdue,
      totalNotes: notes.length,
      priorityCounts: priorityCounts,
      labelCounts: labelCounts,
      topMembers: sortedMembers.take(5).toList(),
      dailyActivity: dailyActivity,
    );
  }
}

class StatsData {
  final int todo;
  final int doing;
  final int done;
  final int overdue;
  final int totalNotes;
  final Map<String, int> priorityCounts;
  final Map<String, int> labelCounts;
  final List<MemberStat> topMembers;
  final Map<int, int> dailyActivity;

  StatsData({
    required this.todo,
    required this.doing,
    required this.done,
    required this.overdue,
    required this.totalNotes,
    required this.priorityCounts,
    required this.labelCounts,
    required this.topMembers,
    required this.dailyActivity,
  });

  double get doneRate => totalNotes == 0 ? 0.0 : done / totalNotes;
}

class MemberStat {
  final String email;
  final String name;
  int completedCount = 0;

  MemberStat({required this.email, required this.name});
}
