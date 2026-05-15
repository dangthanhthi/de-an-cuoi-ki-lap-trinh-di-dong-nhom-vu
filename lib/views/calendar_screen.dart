import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../models/app_models.dart';
import 'note_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = DateTime.now();

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Note> _dedupeNotes(List<Note> notes) {
    final map = <String, Note>{};
    for (final note in notes) {
      map[note.id] = note;
    }
    return map.values.toList();
  }

  List<_CalendarEvent> _eventsFromNotes(List<Note> notes) {
    final events = <_CalendarEvent>[];
    for (final note in notes) {
      if (note.hasReminder && note.reminderTime != null) {
        events.add(
          _CalendarEvent(
            date: note.reminderTime!,
            title: note.title,
            subtitle: 'Nhắc việc ghi chú',
            note: note,
          ),
        );
      }
      if (note.groupId.isEmpty) continue;
      for (final todo in note.todos) {
        if (todo.deadline == null) continue;
        events.add(
          _CalendarEvent(
            date: todo.deadline!,
            title: todo.task,
            subtitle:
                '${note.title} - ${TodoStatus.label(todo.effectiveStatus)}',
            note: note,
            isOverdue: todo.isOverdue,
          ),
        );
      }
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return events;
  }

  Future<List<Note>> _loadGroupNotes(List<QueryDocumentSnapshot> groups) async {
    final groupNotes = await Future.wait(
      groups.map((group) => FirebaseService.getGroupNotesOnce(group.id)),
    );
    return groupNotes.expand((notes) => notes).toList();
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch nhắc việc')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getMyNotesStream(),
        builder: (context, mySnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getSharedNotesStream(),
            builder: (context, sharedSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getMyGroupsStream(),
                builder: (context, groupSnapshot) {
                  if (mySnapshot.connectionState == ConnectionState.waiting ||
                      sharedSnapshot.connectionState ==
                          ConnectionState.waiting ||
                      groupSnapshot.connectionState ==
                          ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final baseNotes = [
                    ...(mySnapshot.data?.docs ?? []).map(
                      FirebaseService.noteFromDocument,
                    ),
                    ...(sharedSnapshot.data?.docs ?? []).map(
                      FirebaseService.noteFromDocument,
                    ),
                  ];

                  return FutureBuilder<List<Note>>(
                    future: _loadGroupNotes(groupSnapshot.data?.docs ?? []),
                    builder: (context, groupNotesSnapshot) {
                      if (groupNotesSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final notes = _dedupeNotes([
                        ...baseNotes,
                        ...(groupNotesSnapshot.data ?? const []),
                      ]);
                      return _buildCalendar(notes);
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

  Widget _buildCalendar(List<Note> notes) {
    final colorScheme = Theme.of(context).colorScheme;
    final events = _eventsFromNotes(notes);
    final selectedEvents = events
        .where((event) => _isSameDay(event.date, _selectedDay))
        .toList();
    final daysInMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + 1,
      0,
    ).day;
    final firstWeekday = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    ).weekday;
    final leadingBlankCount = firstWeekday - 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _moveMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Tháng ${_visibleMonth.month}/${_visibleMonth.year}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _moveMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: const [
              _WeekdayLabel('T2'),
              _WeekdayLabel('T3'),
              _WeekdayLabel('T4'),
              _WeekdayLabel('T5'),
              _WeekdayLabel('T6'),
              _WeekdayLabel('T7'),
              _WeekdayLabel('CN'),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: leadingBlankCount + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlankCount) return const SizedBox.shrink();
            final day = index - leadingBlankCount + 1;
            final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
            final dayEvents = events
                .where((event) => _isSameDay(event.date, date))
                .toList();
            final isSelected = _isSameDay(date, _selectedDay);
            final isToday = _isSameDay(date, DateTime.now());
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedDay = date),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isToday ? colorScheme.primary : Colors.transparent,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    if (dayEvents.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dayEvents.any((event) => event.isOverdue)
                              ? Colors.red
                              : colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const Divider(height: 1),
        Expanded(
          child: selectedEvents.isEmpty
              ? const Center(child: Text('Không có nhắc việc trong ngày này'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: selectedEvents.length,
                  itemBuilder: (context, index) {
                    final event = selectedEvents[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          event.isOverdue
                              ? Icons.warning_amber_outlined
                              : Icons.event_available_outlined,
                          color: event.isOverdue
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        title: Text(event.title),
                        subtitle: Text(event.subtitle),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                NoteDetailScreen(note: event.note),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String text;

  const _WeekdayLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _CalendarEvent {
  final DateTime date;
  final String title;
  final String subtitle;
  final Note note;
  final bool isOverdue;

  const _CalendarEvent({
    required this.date,
    required this.title,
    required this.subtitle,
    required this.note,
    this.isOverdue = false,
  });
}


