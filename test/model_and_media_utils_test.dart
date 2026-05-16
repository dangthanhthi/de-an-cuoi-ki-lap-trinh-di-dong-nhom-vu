import 'dart:convert';

import 'package:deancuoikisnote/models/app_models.dart';
import 'package:deancuoikisnote/utils/media_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TodoItem json round-trip keeps priority and attachments', () {
    final todo = TodoItem(
      task: 'Prepare demo',
      priority: NotePriority.high,
      attachments: const ['https://example.com/FileTokenABC.png'],
    );

    final restored = TodoItem.fromJson(todo.toJson());

    expect(restored.task, 'Prepare demo');
    expect(restored.priority, NotePriority.high);
    expect(restored.attachments, ['https://example.com/FileTokenABC.png']);
  });

  test('Note json round-trip keeps attachment URL casing', () {
    const url =
        'https://firebasestorage.googleapis.com/v0/b/app/o/FileABC.png?token=AbC123';
    final note = Note(
      id: 'note-1',
      title: 'Demo',
      content: 'Content',
      label: 'Công việc',
      date: '2026-05-16',
      coverColor: Colors.blue,
      attachments: const [url],
    );

    final restored = Note.fromJson(note.toJson());

    expect(restored.attachments.single, url);
  });

  test('data URI helpers preserve sanitized file names and bytes', () {
    final bytes = utf8.encode('hello');
    final dataUri = buildDataUri(bytes, 'My File ABC.txt');

    expect(fileNameFromDataUri(dataUri), 'My File ABC.txt');
    expect(utf8.decode(bytesFromDataUri(dataUri)!), 'hello');
  });
}
