import '../models/app_models.dart';
import 'app_state.dart';

class StatisticsController {
  static StatsData calculateStats(List<Note> notes, {int days = 7}) {
    final now = DateTime.now();
    final startTime = days == 0 ? DateTime(2000) : now.subtract(Duration(days: days));
    final myEmail = (AppState.currentUserEmail).toLowerCase().trim();
    
    int todo = 0;
    int doing = 0;
    int done = 0;
    int overdue = 0;
    
    final priorityCounts = <String, int>{};
    final labelCounts = <String, int>{};
    final sharerStats = <String, SharerStat>{};
    final groupStats = <String, GroupStat>{};
    final dailyActivity = <int, int>{}; // weekday index (1-7) -> count
    
    for (int i = 1; i <= 7; i++) {
      dailyActivity[i] = 0;
    }

    for (final note in notes) {
      final isCreator = note.createdByEmail.toLowerCase().trim() == myEmail;
      final isGroupNote = note.groupId.isNotEmpty;
      
      // Track groups
      if (isGroupNote) {
        final groupKey = note.groupId;
        final groupName = note.groupName.isNotEmpty ? note.groupName : 'Nhóm không tên';
        if (!groupStats.containsKey(groupKey)) {
          groupStats[groupKey] = GroupStat(id: groupKey, name: groupName);
        }
      }

      // Track sharers
      if (!isCreator || isGroupNote) {
        final sharerEmail = note.createdByEmail.toLowerCase().trim();
        final sharerName = note.createdByName.isNotEmpty ? note.createdByName : sharerEmail;
        
        if (sharerEmail.isNotEmpty && sharerEmail != myEmail) {
          if (!sharerStats.containsKey(sharerEmail)) {
            sharerStats[sharerEmail] = SharerStat(email: sharerEmail, name: sharerName);
          }
          sharerStats[sharerEmail]!.count++;
        }
      }

      final todos = note.todos;
      final myTodos = todos.where((t) => t.assigneeEmail.toLowerCase().trim() == myEmail).toList();
      
      // Determine if this note belongs to "me" in statistics
      bool includeInMyStats = false;
      bool isNoteDone = false;
      bool isNoteOverdue = false;
      bool isNoteDoing = false;

      if (myTodos.isNotEmpty) {
        includeInMyStats = true;
        isNoteDone = myTodos.every((t) => t.isDone || t.status == TodoStatus.done);
        isNoteOverdue = myTodos.any((t) => t.isOverdue);
        isNoteDoing = !isNoteDone && myTodos.any((t) => t.status == TodoStatus.doing);
      } else if (isCreator) {
        includeInMyStats = true;
        if (todos.isEmpty) {
          isNoteDone = true;
        } else {
          isNoteDone = todos.every((t) => t.isDone || t.status == TodoStatus.done);
          isNoteOverdue = todos.any((t) => t.isOverdue);
          isNoteDoing = !isNoteDone && todos.any((t) => t.status == TodoStatus.doing);
        }
      }

      if (includeInMyStats) {
        if (isNoteDone) {
          done++;
          DateTime? completionDate;
          if (todos.isNotEmpty) {
             final doneTodos = todos.where((t) => (t.isDone || t.status == TodoStatus.done) && t.completedAt != null).toList();
             if (doneTodos.isNotEmpty) {
               completionDate = doneTodos.map((t) => t.completedAt!).reduce((a, b) => a.isAfter(b) ? a : b);
             }
          }
          final activeTime = completionDate ?? now; 
          if (activeTime.isAfter(startTime)) {
            dailyActivity[activeTime.weekday] = (dailyActivity[activeTime.weekday] ?? 0) + 1;
          }
        } else if (isNoteOverdue) {
          overdue++;
          todo++;
        } else if (isNoteDoing) {
          doing++;
        } else {
          todo++;
        }

        final p = NotePriority.normalize(note.priority);
        priorityCounts[p] = (priorityCounts[p] ?? 0) + 1;
      }

      if (isGroupNote) {
        groupStats[note.groupId]!.totalCount += todos.length;
        groupStats[note.groupId]!.completedCount += todos.where((t) => t.isDone || t.status == TodoStatus.done).length;
      }

      if (includeInMyStats && note.label.isNotEmpty) {
        labelCounts[note.label] = (labelCounts[note.label] ?? 0) + 1;
      }
    }

    final sortedSharers = sharerStats.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final sortedGroups = groupStats.values.toList()
      ..sort((a, b) => b.completedCount.compareTo(a.completedCount));

    return StatsData(
      todo: todo,
      doing: doing,
      done: done,
      overdue: overdue,
      totalItems: todo + doing + done,
      priorityCounts: priorityCounts,
      labelCounts: labelCounts,
      topSharers: sortedSharers,
      topGroups: sortedGroups,
      dailyActivity: dailyActivity,
    );
  }
}

class StatsData {
  final int todo;
  final int doing;
  final int done;
  final int overdue;
  final int totalItems;
  final Map<String, int> priorityCounts;
  final Map<String, int> labelCounts;
  final List<SharerStat> topSharers;
  final List<GroupStat> topGroups;
  final Map<int, int> dailyActivity;

  StatsData({
    required this.todo,
    required this.doing,
    required this.done,
    required this.overdue,
    required this.totalItems,
    required this.priorityCounts,
    required this.labelCounts,
    required this.topSharers,
    required this.topGroups,
    required this.dailyActivity,
  });

  double get doneRate => totalItems == 0 ? 0.0 : done / totalItems;
}

class SharerStat {
  final String email;
  final String name;
  int count = 0;

  SharerStat({required this.email, required this.name});
}

class GroupStat {
  final String id;
  final String name;
  int totalCount = 0;
  int completedCount = 0;

  GroupStat({required this.id, required this.name});
  
  double get efficiency => totalCount == 0 ? 0 : completedCount / totalCount;
}
