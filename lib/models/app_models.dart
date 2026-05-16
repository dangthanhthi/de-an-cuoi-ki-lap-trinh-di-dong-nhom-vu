import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../controllers/app_state.dart';

class TodoItem {
  String task;
  bool isDone;
  String assigneeEmail;
  String assigneeName;
  DateTime? deadline;
  DateTime? completedAt;
  String status;
  String textColor; // Hex color or preset
  bool isBold;
  bool isItalic;
  bool isUnderlined;
  bool isUppercase;
  double fontSize;
  String priority; // urgent, high, medium, low, none
  List<String> attachments;

  TodoItem({
    required this.task,
    this.isDone = false,
    this.assigneeEmail = '',
    this.assigneeName = '',
    this.deadline,
    this.completedAt,
    String? status,
    this.textColor = '',
    this.isBold = false,
    this.isItalic = false,
    this.isUnderlined = false,
    this.isUppercase = false,
    this.fontSize = 16.0,
    this.priority = 'none',
    List<String>? attachments,
  }) : status = status ?? (isDone ? TodoStatus.done : TodoStatus.todo),
       attachments = attachments ?? [];

  TodoItem copyWith({
    String? task,
    bool? isDone,
    String? assigneeEmail,
    String? assigneeName,
    DateTime? deadline,
    bool clearDeadline = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    bool markCompletedNow = false,
    String? status,
    String? textColor,
    bool? isBold,
    bool? isItalic,
    bool? isUnderlined,
    bool? isUppercase,
    double? fontSize,
    String? priority,
    List<String>? attachments,
  }) {
    final nextStatus = TodoStatus.normalize(status ?? this.status);
    final nextIsDone = isDone ?? nextStatus == TodoStatus.done;
    return TodoItem(
      task: task ?? this.task,
      isDone: nextIsDone,
      assigneeEmail: assigneeEmail ?? this.assigneeEmail,
      assigneeName: assigneeName ?? this.assigneeName,
      deadline: clearDeadline ? null : deadline ?? this.deadline,
      completedAt: !nextIsDone
          ? null
          : clearCompletedAt
          ? null
          : completedAt ??
                (markCompletedNow ? DateTime.now() : this.completedAt),
      status: nextIsDone ? TodoStatus.done : nextStatus,
      textColor: textColor ?? this.textColor,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      isUnderlined: isUnderlined ?? this.isUnderlined,
      isUppercase: isUppercase ?? this.isUppercase,
      fontSize: fontSize ?? this.fontSize,
      priority: priority ?? this.priority,
      attachments: attachments ?? List.from(this.attachments),
    );
  }

  bool get isOverdue {
    if (status == TodoStatus.done || deadline == null) return false;
    final now = DateTime.now();
    // Nếu giờ và phút là 0:0, coi như là deadline cả ngày (tính đến cuối ngày)
    // Nếu có giờ phút cụ thể, so sánh trực tiếp
    if (deadline!.hour == 0 && deadline!.minute == 0) {
      final endOfDay = DateTime(
        deadline!.year,
        deadline!.month,
        deadline!.day,
        23,
        59,
        59,
      );
      return endOfDay.isBefore(now);
    }
    return deadline!.isBefore(now);
  }

  String get effectiveStatus => isOverdue ? TodoStatus.overdue : status;

  Map<String, dynamic> toMap() {
    return {
      'task': task,
      'isDone': status == TodoStatus.done || isDone,
      'assigneeEmail': assigneeEmail,
      'assigneeName': assigneeName,
      'deadline': deadline?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'status': status == TodoStatus.done || isDone
          ? TodoStatus.done
          : TodoStatus.normalize(status),
      'textColor': textColor,
      'isBold': isBold,
      'isItalic': isItalic,
      'isUnderlined': isUnderlined,
      'isUppercase': isUppercase,
      'fontSize': fontSize,
      'priority': priority,
      'attachments': attachments,
    };
  }

  factory TodoItem.fromMap(Map<String, dynamic> data) {
    final rawDeadline = data['deadline'];
    final rawCompletedAt = data['completedAt'];
    final isDone = data['isDone'] == true;
    return TodoItem(
      task: (data['task'] ?? '').toString(),
      isDone: isDone,
      assigneeEmail: (data['assigneeEmail'] ?? '').toString(),
      assigneeName: (data['assigneeName'] ?? '').toString(),
      deadline: rawDeadline is String && rawDeadline.isNotEmpty
          ? DateTime.tryParse(rawDeadline)
          : null,
      completedAt: rawCompletedAt is Timestamp
          ? rawCompletedAt.toDate()
          : rawCompletedAt is String && rawCompletedAt.isNotEmpty
          ? DateTime.tryParse(rawCompletedAt)
          : null,
      status: TodoStatus.normalize(
        (data['status'] ?? (isDone ? TodoStatus.done : TodoStatus.todo))
            .toString(),
      ),
      textColor: data['textColor']?.toString() ?? '',
      isBold: data['isBold'] == true,
      isItalic: data['isItalic'] == true,
      isUnderlined: data['isUnderlined'] == true,
      isUppercase: data['isUppercase'] == true,
      fontSize: (data['fontSize'] ?? 16.0).toDouble(),
      priority: (data['priority'] ?? 'none').toString(),
      attachments: data['attachments'] is List
          ? List<String>.from(data['attachments'])
          : [],
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      task: (json['task'] ?? '').toString(),
      isDone: json['isDone'] == true,
      assigneeEmail: (json['assigneeEmail'] ?? '').toString(),
      assigneeName: (json['assigneeName'] ?? '').toString(),
      deadline: json['deadline'] != null
          ? DateTime.tryParse(json['deadline'])
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'])
          : null,
      status: TodoStatus.normalize((json['status'] ?? '').toString()),
      textColor: json['textColor']?.toString() ?? '',
      isBold: json['isBold'] == true,
      isItalic: json['isItalic'] == true,
      isUnderlined: json['isUnderlined'] == true,
      isUppercase: json['isUppercase'] == true,
      fontSize: (json['fontSize'] ?? 16.0).toDouble(),
      priority: (json['priority'] ?? 'none').toString(),
      attachments:
          (json['attachments'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          [],
    );
  }
}

class TodoStatus {
  static const todo = 'todo';
  static const doing = 'doing';
  static const done = 'done';
  static const overdue = 'overdue';

  static const values = [todo, doing, done];

  static String normalize(String value) {
    final cleanValue = value.toLowerCase().trim();
    if (cleanValue == done) return done;
    if (cleanValue == doing) return doing;
    return todo;
  }

  static String label(String value) {
    switch (value) {
      case doing:
        return 'Đang làm';
      case done:
        return 'Hoàn thành';
      case overdue:
        return 'Trễ hạn';
      case todo:
      default:
        return 'Chưa làm';
    }
  }
}

class NotePriority {
  static const none = 'none';
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';
  static const urgent = 'urgent';
  static const custom = 'custom';

  static const values = [none, low, medium, high, urgent, custom];
  static const presetValues = [none, low, medium, high, urgent];

  static String normalize(String value) {
    final rawValue = value.trim();
    final cleanValue = rawValue.toLowerCase();
    if (rawValue.isEmpty) return none;
    if (cleanValue == low ||
        cleanValue == medium ||
        cleanValue == high ||
        cleanValue == urgent ||
        cleanValue == none ||
        cleanValue == custom) {
      return cleanValue;
    }
    return rawValue;
  }

  static String choiceValue(String value) {
    final normalized = normalize(value);
    return presetValues.contains(normalized) ? normalized : custom;
  }

  static String label(String value) {
    switch (normalize(value)) {
      case none:
        return 'Không ưu tiên';
      case low:
        return 'Thấp';
      case medium:
        return 'Vừa';
      case high:
        return 'Cao';
      case urgent:
        return 'Khẩn cấp';
      case custom:
        return 'Khác';
      default:
        return value.trim();
    }
  }

  static int weight(String value) {
    switch (normalize(value)) {
      case urgent:
        return 4;
      case high:
        return 3;
      case medium:
        return 2;
      case low:
        return 1;
      case none:
      default:
        return 0;
    }
  }
}

class Note {
  String id;
  String title;
  String content;
  String titleTextColor;
  bool titleIsBold;
  bool titleIsItalic;
  bool titleIsUnderlined;
  double titleFontSize;
  String contentTextColor;
  bool contentIsBold;
  bool contentIsItalic;
  bool contentIsUnderlined;
  double contentFontSize;
  String label;
  String date;
  Color coverColor;
  bool isTodo;
  List<TodoItem> todos;
  List<String> sharedWith;
  bool hasReminder;
  DateTime? reminderTime;
  List<String> attachments;
  bool isPinned;
  String priority;
  String createdByEmail;
  String createdByName;
  String groupId;
  String groupName;
  bool isRichText;
  List<String> pinnedBy;
  List<String> viewedBy;
  List<String> hiddenBy;
  String status;

  // New fields
  bool titleIsStrikethrough;
  bool contentIsStrikethrough;
  bool isArchived;
  bool isLocked;
  bool isShared;
  bool isHidden;
  bool isFavorite;
  bool isChecklist;
  int? backgroundColor;
  String userId;
  List<String> assignedTo;
  DateTime? lastViewedAt;
  int viewCount;

  Note({
    required this.id,
    required this.title,
    required this.content,
    this.titleTextColor = '',
    this.titleIsBold = true,
    this.titleIsItalic = false,
    this.titleIsUnderlined = false,
    this.titleIsStrikethrough = false,
    this.titleFontSize = 26.0,
    this.contentTextColor = '',
    this.contentIsBold = false,
    this.contentIsItalic = false,
    this.contentIsUnderlined = false,
    this.contentIsStrikethrough = false,
    this.contentFontSize = 17.0,
    required this.label,
    required this.date,
    required this.coverColor,
    this.isTodo = false,
    this.todos = const [],
    this.sharedWith = const [],
    this.hasReminder = false,
    this.reminderTime,
    this.attachments = const [],
    this.isPinned = false,
    this.priority = NotePriority.none,
    this.createdByEmail = '',
    this.createdByName = '',
    this.groupId = '',
    this.groupName = '',
    this.isRichText = false,
    this.pinnedBy = const [],
    this.viewedBy = const [],
    this.hiddenBy = const [],
    this.isArchived = false,
    this.isLocked = false,
    this.isShared = false,
    this.isHidden = false,
    this.isFavorite = false,
    this.isChecklist = false,
    this.backgroundColor,
    this.userId = '',
    this.assignedTo = const [],
    this.lastViewedAt,
    this.viewCount = 0,
    this.status = TodoStatus.todo,
  });

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? titleTextColor,
    bool? titleIsBold,
    bool? titleIsItalic,
    bool? titleIsUnderlined,
    double? titleFontSize,
    String? contentTextColor,
    bool? contentIsBold,
    bool? contentIsItalic,
    bool? contentIsUnderlined,
    double? contentFontSize,
    String? label,
    String? date,
    Color? coverColor,
    bool? isTodo,
    List<TodoItem>? todos,
    List<String>? sharedWith,
    bool? hasReminder,
    DateTime? reminderTime,
    List<String>? attachments,
    bool? isPinned,
    String? priority,
    String? createdByEmail,
    String? createdByName,
    String? groupId,
    String? groupName,
    bool? isRichText,
    List<String>? pinnedBy,
    List<String>? viewedBy,
    List<String>? hiddenBy,
    bool? titleIsStrikethrough,
    bool? contentIsStrikethrough,
    bool? isArchived,
    bool? isLocked,
    bool? isShared,
    bool? isHidden,
    bool? isFavorite,
    bool? isChecklist,
    int? backgroundColor,
    String? userId,
    List<String>? assignedTo,
    DateTime? lastViewedAt,
    int? viewCount,
    String? status,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      titleTextColor: titleTextColor ?? this.titleTextColor,
      titleIsBold: titleIsBold ?? this.titleIsBold,
      titleIsItalic: titleIsItalic ?? this.titleIsItalic,
      titleIsUnderlined: titleIsUnderlined ?? this.titleIsUnderlined,
      titleIsStrikethrough: titleIsStrikethrough ?? this.titleIsStrikethrough,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      contentTextColor: contentTextColor ?? this.contentTextColor,
      contentIsBold: contentIsBold ?? this.contentIsBold,
      contentIsItalic: contentIsItalic ?? this.contentIsItalic,
      contentIsUnderlined: contentIsUnderlined ?? this.contentIsUnderlined,
      contentIsStrikethrough: contentIsStrikethrough ?? this.contentIsStrikethrough,
      contentFontSize: contentFontSize ?? this.contentFontSize,
      label: label ?? this.label,
      date: date ?? this.date,
      coverColor: coverColor ?? this.coverColor,
      isTodo: isTodo ?? this.isTodo,
      todos: todos ?? this.todos,
      sharedWith: sharedWith ?? this.sharedWith,
      hasReminder: hasReminder ?? this.hasReminder,
      reminderTime: reminderTime ?? this.reminderTime,
      attachments: attachments ?? this.attachments,
      isPinned: isPinned ?? this.isPinned,
      priority: priority ?? this.priority,
      createdByEmail: createdByEmail ?? this.createdByEmail,
      createdByName: createdByName ?? this.createdByName,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      isRichText: isRichText ?? this.isRichText,
      pinnedBy: pinnedBy ?? this.pinnedBy,
      viewedBy: viewedBy ?? this.viewedBy,
      hiddenBy: hiddenBy ?? this.hiddenBy,
      isArchived: isArchived ?? this.isArchived,
      isLocked: isLocked ?? this.isLocked,
      isShared: isShared ?? this.isShared,
      isHidden: isHidden ?? this.isHidden,
      isFavorite: isFavorite ?? this.isFavorite,
      isChecklist: isChecklist ?? this.isChecklist,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      userId: userId ?? this.userId,
      assignedTo: assignedTo ?? this.assignedTo,
      lastViewedAt: lastViewedAt ?? this.lastViewedAt,
      viewCount: viewCount ?? this.viewCount,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'titleTextColor': titleTextColor,
      'titleIsBold': titleIsBold,
      'titleIsItalic': titleIsItalic,
      'titleIsUnderlined': titleIsUnderlined,
      'titleFontSize': titleFontSize,
      'label': label,
      'date': date,
      'color': coverColor.toARGB32(),
      'isTodo': isTodo,
      'todos': todos.map((t) => t.toJson()).toList(),
      'sharedWith': sharedWith,
      'hasReminder': hasReminder,
      'reminderTime': reminderTime?.toIso8601String(),
      'attachments': attachments,
      'isPinned': isPinned,
      'priority': priority,
      'createdByEmail': createdByEmail,
      'createdByName': createdByName,
      'groupId': groupId,
      'groupName': groupName,
      'isRichText': isRichText,
      'pinnedBy': pinnedBy,
      'viewedBy': viewedBy,
      'hiddenBy': hiddenBy,
      'titleIsStrikethrough': titleIsStrikethrough,
      'contentIsStrikethrough': contentIsStrikethrough,
      'isArchived': isArchived,
      'isLocked': isLocked,
      'isShared': isShared,
      'isHidden': isHidden,
      'isFavorite': isFavorite,
      'isChecklist': isChecklist,
      'backgroundColor': backgroundColor,
      'userId': userId,
      'assignedTo': assignedTo,
      'lastViewedAt': lastViewedAt?.toIso8601String(),
      'viewCount': viewCount,
      'status': status,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      titleTextColor: json['titleTextColor']?.toString() ?? '',
      titleIsBold: json['titleIsBold'] != false,
      titleIsItalic: json['titleIsItalic'] == true,
      titleIsUnderlined: json['titleIsUnderlined'] == true,
      titleFontSize: (json['titleFontSize'] ?? 26.0).toDouble(),
      contentTextColor: (json['contentTextColor'] ?? '').toString(),
      contentIsBold: json['contentIsBold'] == true,
      contentIsItalic: json['contentIsItalic'] == true,
      contentIsUnderlined: json['contentIsUnderlined'] == true,
      contentFontSize: (json['contentFontSize'] ?? 17.0).toDouble(),
      label: (json['label'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      coverColor: Color(json['color'] ?? 0xFFFFFFFF),
      isTodo: json['isTodo'] ?? false,
      todos: (json['todos'] as List? ?? [])
          .map((t) => TodoItem.fromJson(t))
          .toList(),
      sharedWith:
          (json['sharedWith'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      hasReminder: json['hasReminder'] ?? false,
      reminderTime: json['reminderTime'] != null
          ? DateTime.tryParse(json['reminderTime'])
          : null,
      attachments:
          (json['attachments'] as List?)?.map((e) => e.toString()).toList() ??
          [],
      isPinned: json['isPinned'] ?? false,
      priority: (json['priority'] ?? NotePriority.none).toString(),
      createdByEmail: (json['createdByEmail'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? '').toString(),
      groupId: (json['groupId'] ?? '').toString(),
      groupName: (json['groupName'] ?? '').toString(),
      isRichText: json['isRichText'] ?? false,
      pinnedBy:
          (json['pinnedBy'] as List?)?.map((e) => e.toString()).toList() ?? [],
      viewedBy:
          (json['viewedBy'] as List?)?.map((e) => e.toString()).toList() ?? [],
      hiddenBy:
          (json['hiddenBy'] as List?)?.map((e) => e.toString()).toList() ?? [],
      titleIsStrikethrough: json['titleIsStrikethrough'] == true,
      contentIsStrikethrough: json['contentIsStrikethrough'] == true,
      isArchived: json['isArchived'] == true,
      isLocked: json['isLocked'] == true,
      isShared: json['isShared'] == true,
      isHidden: json['isHidden'] == true,
      isFavorite: json['isFavorite'] == true,
      isChecklist: json['isChecklist'] == true,
      backgroundColor: json['backgroundColor'] as int?,
      userId: (json['userId'] ?? '').toString(),
      assignedTo: (json['assignedTo'] as List?)?.map((e) => e.toString()).toList() ?? [],
      lastViewedAt: json['lastViewedAt'] != null ? DateTime.tryParse(json['lastViewedAt']) : null,
      viewCount: (json['viewCount'] ?? 0) as int,
      status: TodoStatus.normalize((json['status'] ?? '').toString()),
    );
  }

  bool get isPinnedByUser {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    return pinnedBy.contains(myEmail);
  }

  bool get isUnread {
    final myEmail = AppState.currentUserEmail.toLowerCase().trim();
    // Only shared notes can be unread
    if (createdByEmail.toLowerCase().trim() == myEmail) return false;
    return !viewedBy.contains(myEmail);
  }

  Color? get resolvedTitleColor {
    if (titleTextColor.isEmpty) return null;
    try {
      return Color(int.parse(titleTextColor, radix: 16));
    } catch (_) {
      return null;
    }
  }

  Color? get resolvedContentColor {
    if (contentTextColor.isEmpty) return null;
    try {
      return Color(int.parse(contentTextColor, radix: 16));
    } catch (_) {
      return null;
    }
  }
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

class ChatMessage {
  final String id;
  final String senderEmail;
  final String senderName;
  final String text;
  final List<String> attachments;
  final DateTime? createdAt;
  final String replyToId;
  final String replyToText;
  final String replyToSender;
  final List<String> seenBy;
  final bool isRecalled;
  final bool isEdited;
  final bool isPinned;
  final Map<String, String> reactions; // email -> emoji

  ChatMessage({
    required this.id,
    required this.senderEmail,
    required this.senderName,
    required this.text,
    this.attachments = const [],
    this.createdAt,
    this.replyToId = '',
    this.replyToText = '',
    this.replyToSender = '',
    this.seenBy = const [],
    this.isRecalled = false,
    this.isEdited = false,
    this.isPinned = false,
    this.reactions = const {},
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: id,
      senderEmail: (data['senderEmail'] ?? '').toString(),
      senderName: (data['senderName'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      attachments: List<String>.from(data['attachments'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      replyToId: (data['replyToId'] ?? '').toString(),
      replyToText: (data['replyToText'] ?? '').toString(),
      replyToSender: (data['replyToSender'] ?? '').toString(),
      seenBy: List<String>.from(data['seenBy'] ?? []),
      isRecalled: data['isRecalled'] == true,
      isEdited: data['isEdited'] == true,
      isPinned: data['isPinned'] == true,
      reactions: Map<String, String>.from(data['reactions'] ?? {}),
    );
  }
}

class GroupComment {
  final String id;
  final String userId;
  final String userEmail;
  final String userName;
  final String userAvatar;
  final String text;
  final List<String> attachments;
  final Map<String, dynamic>? replyTo;
  final DateTime? createdAt;
  final List<String> seenBy;
  final bool isRecalled;
  final bool isEdited;
  final bool isPinned;
  final Map<String, String> reactions; // email -> emoji

  GroupComment({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.userAvatar,
    required this.text,
    this.attachments = const [],
    this.replyTo,
    this.createdAt,
    this.seenBy = const [],
    this.isRecalled = false,
    this.isEdited = false,
    this.isPinned = false,
    this.reactions = const {},
  });

  factory GroupComment.fromMap(String id, Map<String, dynamic> data) {
    return GroupComment(
      id: id,
      userId: (data['userId'] ?? '').toString(),
      userEmail: (data['userEmail'] ?? '').toString(),
      userName: (data['userName'] ?? '').toString(),
      userAvatar: (data['userAvatar'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      attachments: List<String>.from(data['attachments'] ?? []),
      replyTo: data['replyTo'] as Map<String, dynamic>?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      seenBy: List<String>.from(data['seenBy'] ?? []),
      isRecalled: data['isRecalled'] == true,
      isEdited: data['isEdited'] == true,
      isPinned: data['isPinned'] == true,
      reactions: Map<String, String>.from(data['reactions'] ?? {}),
    );
  }
}
