import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import '../controllers/app_state.dart';
import '../models/app_models.dart';
import 'note_detail_screen.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  late Stream<QuerySnapshot> _myNotesStream;
  late Stream<QuerySnapshot> _sharedNotesStream;
  late Stream<QuerySnapshot> _myGroupsStream;

  @override
  void initState() {
    super.initState();
    _myNotesStream = FirebaseService.getMyNotesStream();
    _sharedNotesStream = FirebaseService.getSharedNotesStream();
    _myGroupsStream = FirebaseService.getMyGroupsStream();
  }

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

  List<_CalendarEvent> _getEventsForDay(DateTime day, List<_CalendarEvent> allEvents) {
    return allEvents.where((event) => isSameDay(event.date, day)).toList();
  }

  Future<List<Note>> _loadGroupNotes(List<QueryDocumentSnapshot> groups) async {
    final groupNotes = await Future.wait(
      groups.map((group) => FirebaseService.getGroupNotesOnce(group.id)),
    );
    return groupNotes.expand((notes) => notes).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch nhắc việc')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _myNotesStream,
        builder: (context, mySnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: _sharedNotesStream,
            builder: (context, sharedSnapshot) {
              return StreamBuilder<QuerySnapshot>(
                stream: _myGroupsStream,
                builder: (context, groupSnapshot) {
                  if (mySnapshot.hasError || sharedSnapshot.hasError || groupSnapshot.hasError) {
                    final err = mySnapshot.error ?? sharedSnapshot.error ?? groupSnapshot.error;
                    debugPrint('Error in calendar screen streams: $err');
                    return const Center(child: Text('Không tải được dữ liệu nhắc việc'));
                  }
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
                      if (groupNotesSnapshot.hasError) {
                        debugPrint('Error loading group notes for calendar: ${groupNotesSnapshot.error}');
                        return const Center(child: Text('Không tải được dữ liệu nhóm'));
                      }
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
    final selectedEvents = _getEventsForDay(_selectedDay, events);

    return Column(
      children: [
        TableCalendar<_CalendarEvent>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarFormat: _calendarFormat,
          onFormatChanged: (format) {
            setState(() {
              _calendarFormat = format;
            });
          },
          onPageChanged: (focusedDay) {
            _focusedDay = focusedDay;
          },
          eventLoader: (day) => _getEventsForDay(day, events),
          startingDayOfWeek: StartingDayOfWeek.monday,
          headerStyle: HeaderStyle(
            formatButtonVisible: true,
            titleCentered: true,
            formatButtonDecoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            formatButtonTextStyle: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
            leftChevronIcon: Icon(Icons.chevron_left, color: colorScheme.primary),
            rightChevronIcon: Icon(Icons.chevron_right, color: colorScheme.primary),
          ),
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.primary, width: 2),
            ),
            todayTextStyle: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
            selectedDecoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            selectedTextStyle: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
            markersAlignment: Alignment.bottomCenter,
            outsideDaysVisible: false,
          ),
          calendarBuilders: CalendarBuilders(
            markerBuilder: (context, date, dayEvents) {
              if (dayEvents.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: dayEvents.take(3).map((event) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.0, vertical: 2.0),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: event.isOverdue ? Colors.red : colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  );
                }).toList(),
              );
            },
          ),
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
                      elevation: 0,
                      color: colorScheme.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          event.isOverdue
                              ? Icons.warning_amber_outlined
                              : Icons.event_available_outlined,
                          color: event.isOverdue
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        title: Text(
                          event.title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
