import 'package:flutter/material.dart';

class TodoItem {
  String task;
  bool isDone;
  TodoItem({required this.task, this.isDone = false});
}

class Note {
  String id;
  String title;
  String content;
  String label;
  String date;
  Color coverColor;
  bool isTodo;
  List<TodoItem> todos;
  List<String> sharedWith;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.label,
    required this.date,
    required this.coverColor,
    this.isTodo = false,
    this.todos = const [],
    this.sharedWith = const [],
  });
}

class Activity {
  String action;
  String details;
  String date;
  Activity({required this.action, required this.details, required this.date});
}

class Contact {
  String id;
  String name;
  String email;
  Contact({required this.id, required this.name, required this.email});
}