import 'package:flutter/material.dart';
import '../models/app_models.dart';

class AppState {
  static String currentUserRole = 'User';
  static String currentUserName = 'Nguyễn Văn A';
  static String currentUserEmail = 'nva@gmail.com';
  static String? currentUserAvatar;

  static List<String> labels = ['Công việc', 'Cá nhân', 'Học tập', 'Khác'];

  static List<Activity> activities = [];

  static List<Contact> contacts = [
    Contact(id: '1', name: 'Trần Thị B', email: 'ttb@gmail.com'),
    Contact(id: '2', name: 'Lê Văn C', email: 'lvc@gmail.com'),
    Contact(id: '3', name: 'Phạm Văn D', email: 'pvd@gmail.com'),
    Contact(id: '4', name: 'Hoàng Thị E', email: 'hte@gmail.com'),
  ];

  static void logActivity(String action, String details) {
    final now = DateTime.now();
    final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} ${now.day}/${now.month}/${now.year}";
    activities.insert(0, Activity(action: action, details: details, date: timeString));
  }

  static List<Note> notes = [
    Note(
      id: '1',
      title: 'Họp dự án UI/UX',
      content: '- Phân tích yêu cầu\n- Lên wireframe\n- Thiết kế UI trên Figma\n- Review với team',
      label: 'Công việc',
      date: '10/10/2023',
      coverColor: Colors.indigo,
    ),
    Note(
      id: '2',
      title: 'Danh sách đi siêu thị',
      content: '',
      label: 'Cá nhân',
      date: '12/10/2023',
      coverColor: Colors.orange,
      isTodo: true,
      todos: [
        TodoItem(task: 'Sữa tươi', isDone: true),
        TodoItem(task: 'Bánh mì', isDone: false),
        TodoItem(task: 'Trứng', isDone: true),
      ],
    ),
    Note(
      id: '3',
      title: 'Kế hoạch du lịch Đà Lạt',
      content: 'Lịch trình 3 ngày 2 đêm:\n- Ngày 1: Nhận phòng, đi chợ đêm\n- Ngày 2: Săn mây, đi cafe\n- Ngày 3: Mua đặc sản, về lại SG',
      label: 'Cá nhân',
      date: '15/10/2023',
      coverColor: Colors.red,
      sharedWith: ['nva@gmail.com'],
    )
  ];
}