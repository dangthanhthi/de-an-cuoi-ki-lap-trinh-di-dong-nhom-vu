import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/app_models.dart';

class LocalService {
  static const String _notesBoxName = 'notes_cache';
  static const String _syncQueueBoxName = 'sync_queue';

  static Future<void> init() async {
    await Hive.openBox(_notesBoxName);
    await Hive.openBox(_syncQueueBoxName);
  }

  static Box get _notesBox => Hive.box(_notesBoxName);
  static Box get _syncQueueBox => Hive.box(_syncQueueBoxName);

  // Notes Cache
  static void cacheNotes(List<Note> notes) {
    final Map<String, String> data = {};
    for (final note in notes) {
      data[note.id] = jsonEncode(note.toJson());
    }
    _notesBox.putAll(data);
  }

  static void cacheNote(Note note) {
    _notesBox.put(note.id, jsonEncode(note.toJson()));
  }

  static void removeCachedNote(String noteId) {
    _notesBox.delete(noteId);
  }

  static List<Note> getCachedNotes() {
    return _notesBox.values
        .map((e) => Note.fromJson(jsonDecode(e as String)))
        .toList();
  }

  // Sync Queue
  static void addToSyncQueue(Note note, String action) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _syncQueueBox.put(id, jsonEncode({
      'id': id,
      'action': action,
      'note': note.toJson(),
      'timestamp': DateTime.now().toIso8601String(),
    }));
  }

  static List<Map<String, dynamic>> getSyncQueue() {
    final list = _syncQueueBox.values
        .map((e) => jsonDecode(e as String) as Map<String, dynamic>)
        .toList();
    // Sort by timestamp to preserve order
    list.sort((a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String));
    return list;
  }

  static void removeFromSyncQueue(String queueId) {
    _syncQueueBox.delete(queueId);
  }

  static void clearSyncQueue() {
    _syncQueueBox.clear();
  }

  static void clearNotesCache() {
    _notesBox.clear();
  }

  static bool get hasPendingSync => _syncQueueBox.isNotEmpty;
}


