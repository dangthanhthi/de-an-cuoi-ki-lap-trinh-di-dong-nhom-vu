import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';

import 'app_state.dart';

class AiMessage {
  final String id;
  final String role;
  final String content;
  final DateTime timestamp;
  final List<AiTodoSuggestion> todoSuggestions;

  const AiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.todoSuggestions = const [],
  });

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toFirestore() => {
    'role': role,
    'content': content,
    'timestamp': Timestamp.fromDate(timestamp),
    'todoSuggestions': todoSuggestions.map((todo) => todo.toMap()).toList(),
  };

  factory AiMessage.fromFirestore(String id, Map<String, dynamic> data) {
    final ts = data['timestamp'];
    return AiMessage(
      id: id,
      role: (data['role'] ?? 'user').toString(),
      content: (data['content'] ?? '').toString(),
      timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
      todoSuggestions: (data['todoSuggestions'] as List? ?? [])
          .map(
            (item) => AiTodoSuggestion.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class AiTodoSuggestion {
  final String task;
  final String priority;
  final String? deadline;

  const AiTodoSuggestion({
    required this.task,
    this.priority = 'none',
    this.deadline,
  });

  Map<String, dynamic> toMap() => {
    'task': task,
    'priority': priority,
    'deadline': deadline,
  };

  factory AiTodoSuggestion.fromMap(Map<String, dynamic> map) {
    return AiTodoSuggestion(
      task: (map['task'] ?? '').toString(),
      priority: (map['priority'] ?? 'none').toString(),
      deadline: map['deadline']?.toString(),
    );
  }
}

class AiChatSession {
  final String sessionId;
  final String? noteId;
  final String? noteTitle;
  final DateTime createdAt;
  final String lastMessage;

  const AiChatSession({
    required this.sessionId,
    this.noteId,
    this.noteTitle,
    required this.createdAt,
    required this.lastMessage,
  });

  factory AiChatSession.fromFirestore(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'];
    return AiChatSession(
      sessionId: id,
      noteId: data['noteId']?.toString(),
      noteTitle: data['noteTitle']?.toString(),
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      lastMessage: (data['lastMessage'] ?? '').toString(),
    );
  }
}

class AIServiceException implements Exception {
  final String message;

  const AIServiceException(this.message);

  @override
  String toString() => message;
}

enum _NoteTopic {
  work,
  study,
  family,
  travel,
  shopping,
  finance,
  health,
  event,
  personal,
  generic,
}

class AIService {
  /// Phân tích ghi chú để tự động đề xuất Nhãn, Độ ưu tiên và Nhắc nhở.
  static Future<Map<String, dynamic>> analyzeNoteMetadata({
    required String title,
    required String content,
  }) async {
    final combined = "$title\n$content";
    final label = suggestLabel(title, content);

    // Phân tích độ ưu tiên
    String priority = NotePriority.none;
    final lower = combined.toLowerCase();
    if (lower.contains('gấp') ||
        lower.contains('quan trọng') ||
        lower.contains('ngay lập tức') ||
        lower.contains('khẩn cấp') ||
        lower.contains('priority') ||
        lower.contains('asap')) {
      priority = NotePriority.high;
    } else if (lower.contains('cần làm') ||
        lower.contains('sớm') ||
        lower.contains('tuần này') ||
        lower.contains('ra soát')) {
      priority = NotePriority.medium;
    }

    // Phân tích nhắc nhở (tìm ngày/giờ chi tiết hơn)
    DateTime? reminder;
    final dateRegex = RegExp(
      r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})|(\d{1,2})\s+tháng\s+(\d{1,2})(\s+năm\s+(\d{4}))?',
      caseSensitive: false,
    );
    final timeRegex = RegExp(
      r'(\d{1,2})[h:](\d{2})',
      caseSensitive: false,
    );

    final dateMatch = dateRegex.firstMatch(combined);
    final timeMatch = timeRegex.firstMatch(combined);

    if (dateMatch != null) {
      try {
        int day = 0, month = 0, year = DateTime.now().year;
        if (dateMatch.group(1) != null) {
          day = int.parse(dateMatch.group(1)!);
          month = int.parse(dateMatch.group(2)!);
          year = int.parse(dateMatch.group(3)!);
        } else if (dateMatch.group(4) != null) {
          day = int.parse(dateMatch.group(4)!);
          month = int.parse(dateMatch.group(5)!);
          if (dateMatch.group(7) != null) {
            year = int.parse(dateMatch.group(7)!);
          }
        }

        int hour = 9, minute = 0;
        if (timeMatch != null) {
          hour = int.parse(timeMatch.group(1)!);
          minute = int.parse(timeMatch.group(2)!);
        }

        reminder = DateTime(year, month, day, hour, minute);
        if (year < 100) {
          reminder = DateTime(year + 2000, month, day, hour, minute);
        }
      } catch (_) {}
    } else if (timeMatch != null) {
      // Nếu chỉ có giờ, mặc định là hôm nay hoặc mai
      try {
        final hour = int.parse(timeMatch.group(1)!);
        final minute = int.parse(timeMatch.group(2)!);
        final now = DateTime.now();
        reminder = DateTime(now.year, now.month, now.day, hour, minute);
        if (reminder.isBefore(now)) {
          reminder = reminder.add(const Duration(days: 1));
        }
      } catch (_) {}
    }

    return {
      'label': label,
      'priority': priority,
      'reminder': reminder,
    };
  }

  static const int _maxHistoryMessages = 20;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String userMessageFor(Object error) {
    if (error is AIServiceException) return error.message;
    return 'Khong the xu ly yeu cau luc nay.';
  }

  static String get _uid {
    final email = AppState.currentUserEmail;
    if (email.isEmpty) return 'anonymous';
    return email.replaceAll(RegExp(r'[.@]'), '_');
  }

  static CollectionReference get _sessionsRef =>
      _db.collection('ai_chats').doc(_uid).collection('sessions');

  static CollectionReference _messagesRef(String sessionId) =>
      _sessionsRef.doc(sessionId).collection('messages');

  static String get _workLabel =>
      AppState.labels.isNotEmpty ? AppState.labels.first : 'Công việc';

  static String get _personalLabel =>
      AppState.labels.length > 1 ? AppState.labels[1] : 'Cá nhân';

  static String get _studyLabel =>
      AppState.labels.length > 2 ? AppState.labels[2] : 'Học tập';


  static Future<String> createSession({
    String? noteId,
    String? noteTitle,
  }) async {
    final docRef = await _sessionsRef.add({
      'noteId': noteId ?? '',
      'noteTitle': noteTitle ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
    });
    return docRef.id;
  }

  static Stream<List<AiChatSession>> getSessionsStream() {
    return _sessionsRef
        .orderBy('updatedAt', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => AiChatSession.fromFirestore(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  static Stream<List<AiMessage>> getMessagesStream(String sessionId) {
    return _messagesRef(sessionId)
        .orderBy('timestamp', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) => AiMessage.fromFirestore(
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                ),
              )
              .toList(),
        );
  }

  static Future<void> deleteSession(String sessionId) async {
    final messages = await _messagesRef(sessionId).get();
    for (final doc in messages.docs) {
      await doc.reference.delete();
    }
    await _sessionsRef.doc(sessionId).delete();
  }

  static Future<AiMessage> sendMessage({
    required String sessionId,
    required String userText,
    String? noteTitle,
    String? noteContent,
  }) async {
    final cleanText = userText.trim();
    if (cleanText.isEmpty) {
      throw const AIServiceException('Tin nhan khong duoc de trong.');
    }

    await _messagesRef(sessionId).add(
      AiMessage(
        id: '',
        role: 'user',
        content: cleanText,
        timestamp: DateTime.now(),
      ).toFirestore(),
    );

    final historySnap = await _messagesRef(
      sessionId,
    ).orderBy('timestamp', descending: true).limit(_maxHistoryMessages).get();

    final historyMessages = historySnap.docs.reversed
        .map(
          (doc) => AiMessage.fromFirestore(
            doc.id,
            doc.data() as Map<String, dynamic>,
          ),
        )
        .where((message) => message.isUser || message.isAssistant)
        .toList();

    final parsed = _buildAssistantPayload(
      userMessage: cleanText,
      noteTitle: noteTitle,
      noteContent: noteContent,
      history: historyMessages,
    );

    final assistantDocRef = await _messagesRef(sessionId).add(
      AiMessage(
        id: '',
        role: 'assistant',
        content: parsed.cleanText,
        timestamp: DateTime.now(),
        todoSuggestions: parsed.todos,
      ).toFirestore(),
    );

    await _sessionsRef.doc(sessionId).update({
      'lastMessage': parsed.cleanText.length > 80
          ? '${parsed.cleanText.substring(0, 80)}...'
          : parsed.cleanText,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return AiMessage(
      id: assistantDocRef.id,
      role: 'assistant',
      content: parsed.cleanText,
      timestamp: DateTime.now(),
      todoSuggestions: parsed.todos,
    );
  }

  static Future<List<AiTodoSuggestion>> suggestTodosFromNote({
    required String noteTitle,
    required String noteContent,
  }) async {
    if (_isUnsafeRequest('$noteTitle\n$noteContent')) {
      return [];
    }
    return _buildLocalTodoSuggestions(
      noteTitle: noteTitle,
      noteContent: noteContent,
    );
  }

  static Future<String> suggestNoteContent({required String noteTitle}) async {
    if (noteTitle.trim().isEmpty) return '';
    if (_isUnsafeRequest(noteTitle)) {
      return _unsafeResponse();
    }
    return _buildLocalNoteContent(noteTitle);
  }

  static Future<String> summarizeNote(String title, String content) async {
    if (content.trim().isEmpty) {
      return 'Noi dung trong, chua the tom tat.';
    }
    if (_isUnsafeRequest('$title\n$content')) {
      return _unsafeResponse();
    }
    return _buildLocalSummary(title, content);
  }

  static Future<String> getStrategicAdvice(String title, String content) async {
    if (_isUnsafeRequest('$title\n$content')) {
      return _unsafeResponse();
    }
    return _buildLocalAdvice(title, content);
  }

  static String suggestLabel(
    String title,
    String content, {
    bool isTodo = false,
  }) {
    final text = _normalizeText('$title\n$content');
    if (text.isEmpty) return _workLabel;

    final topic = _detectTopic('$title\n$content');
    switch (topic) {
      case _NoteTopic.work:
        return _workLabel;
      case _NoteTopic.study:
        return _studyLabel;
      case _NoteTopic.travel:
        return 'Du lịch';
      case _NoteTopic.family:
        return 'Gia đình';
      case _NoteTopic.shopping:
        return 'Mua sắm';
      case _NoteTopic.finance:
        return 'Tài chính';
      case _NoteTopic.health:
        return 'Sức khỏe';
      case _NoteTopic.event:
        return 'Sự kiện';
      case _NoteTopic.personal:
        return _personalLabel;
      case _NoteTopic.generic:
        return isTodo ? _workLabel : _personalLabel;
    }
  }

  static _ParsedResponse _buildAssistantPayload({
    required String userMessage,
    String? noteTitle,
    String? noteContent,
    List<AiMessage> history = const [],
  }) {
    final title = (noteTitle ?? '').trim();
    final content = (noteContent ?? '').trim();
    final fullContext = [
      title,
      content,
      userMessage.trim(),
    ].where((part) => part.isNotEmpty).join('\n');

    if (_isUnsafeRequest(fullContext)) {
      return _ParsedResponse(cleanText: _unsafeResponse(), todos: const []);
    }

    final lower = _normalizeText(userMessage);
    if (_looksLikeTodoRequest(lower)) {
      return _ParsedResponse(
        cleanText:
            'Mình đã tách nội dung này thành checklist cụ thể hơn để bạn dùng ngay.',
        todos: _buildLocalTodoSuggestions(
          noteTitle: title,
          noteContent: content,
        ),
      );
    }

    if (_looksLikeSummaryRequest(lower)) {
      return _ParsedResponse(
        cleanText: _buildLocalSummary(title, content),
        todos: const [],
      );
    }

    if (_looksLikeAdviceRequest(lower)) {
      return _ParsedResponse(
        cleanText: _buildLocalAdvice(title, content),
        todos: const [],
      );
    }

    final topic = _detectTopic(fullContext);
    final todos = _buildLocalTodoSuggestions(
      noteTitle: title,
      noteContent: content.isNotEmpty ? content : userMessage,
      maxItems: 4,
    );
    final reply = StringBuffer();
    final travelInfo = _extractTravelInfo('$title\n$content\n$userMessage');

    switch (topic) {
      case _NoteTopic.travel:
        reply.writeln(
          travelInfo.destination != null
              ? 'Đây giống một kế hoạch chuyến đi ${travelInfo.destination}.'
              : 'Đây giống một kế hoạch cho một chuyến đi.',
        );
        if (travelInfo.duration != null || travelInfo.timing != null) {
          reply.writeln('');
          if (travelInfo.duration != null) {
            reply.writeln('- Thời lượng: ${travelInfo.duration}');
          }
          if (travelInfo.timing != null) {
            reply.writeln('- Thời điểm: ${travelInfo.timing}');
          }
        }
        break;
      case _NoteTopic.study:
        reply.writeln('Mình hiểu đây là ghi chú học tập và ôn bài.');
        break;
      case _NoteTopic.work:
        reply.writeln(
          'Mình hiểu đây là ghi chú công việc cần sắp xếp rõ đầu việc.',
        );
        break;
      case _NoteTopic.family:
        reply.writeln('Mình hiểu đây là ghi chú liên quan đến gia đình.');
        break;
      default:
        reply.writeln(
          title.isNotEmpty
              ? 'Mình đang hỗ trợ bạn dựa trên ghi chú "$title".'
              : 'Mình đang hỗ trợ bạn dựa trên nội dung hiện có.',
        );
        break;
    }

    final ideas = _extractKeyIdeas(
      content.isNotEmpty
          ? content
          : title.isNotEmpty
          ? title
          : userMessage,
      maxItems: 3,
    );
    if (ideas.isNotEmpty) {
      reply.writeln('');
      reply.writeln('Điểm chính:');
      for (final idea in ideas) {
        reply.writeln('- $idea');
      }
    }

    if (todos.isNotEmpty) {
      reply.writeln('');
      reply.writeln('Bạn nên làm trước:');
      for (final todo in todos.take(3)) {
        reply.writeln('- ${todo.task}');
      }
    }

    if (history.where((message) => message.isUser).length > 2) {
      reply.writeln('');
      reply.writeln(
        'Mình vẫn đang giữ ngữ cảnh cuộc trò chuyện để gợi ý nhất quán hơn.',
      );
    }

    reply.writeln('');
    reply.write(
      'Nếu muốn, mình có thể chuyển tiếp phần này thành checklist chi tiết hơn.',
    );

    return _ParsedResponse(cleanText: reply.toString().trim(), todos: const []);
  }

  static bool _looksLikeTodoRequest(String input) {
    return input.contains('todo') ||
        input.contains('checklist') ||
        input.contains('cong viec') ||
        input.contains('nhiem vu') ||
        input.contains('viec can lam') ||
        input.contains('task');
  }

  static bool _looksLikeSummaryRequest(String input) {
    return input.contains('tom tat') ||
        input.contains('summary') ||
        input.contains('rut gon') ||
        input.contains('tong hop');
  }

  static bool _looksLikeAdviceRequest(String input) {
    return input.contains('loi khuyen') ||
        input.contains('goi y') ||
        input.contains('chien luoc') ||
        input.contains('huong dan') ||
        input.contains('tu van');
  }

  static String _buildLocalSummary(String title, String content) {
    final source = content.trim().isNotEmpty ? content.trim() : title.trim();
    final topic = _detectTopic('$title\n$content');

    if (source.isEmpty) {
      return 'Chưa có đủ nội dung để tóm tắt.';
    }

    if (topic == _NoteTopic.travel) {
      final info = _extractTravelInfo('$title\n$content');
      final buffer = StringBuffer();
      buffer.writeln(
        title.trim().isNotEmpty ? 'Tóm tắt cho "$title":' : 'Tóm tắt nhanh:',
      );
      if (info.destination != null) {
        buffer.writeln('- Điểm đến: ${info.destination}');
      }
      if (info.duration != null) {
        buffer.writeln('- Thời lượng: ${info.duration}');
      }
      if (info.timing != null) {
        buffer.writeln('- Thời điểm: ${info.timing}');
      }
      buffer.writeln(
        '- Trọng tâm: chốt di chuyển, chỗ ở, lịch trình và đồ cần mang.',
      );
      return buffer.toString().trim();
    }

    final ideas = _extractKeyIdeas(source, maxItems: 4);
    if (ideas.isEmpty) {
      return title.trim().isNotEmpty
          ? 'Tóm tắt nhanh: ghi chú đang xoay quanh "$title". Hãy bổ sung thêm chi tiết để tóm tắt rõ hơn.'
          : 'Chưa có đủ nội dung để tóm tắt.';
    }

    final buffer = StringBuffer();
    buffer.writeln(
      title.trim().isNotEmpty ? 'Tóm tắt cho "$title":' : 'Tóm tắt nhanh:',
    );
    for (final idea in ideas) {
      buffer.writeln('- $idea');
    }
    return buffer.toString().trim();
  }

  static String _buildLocalAdvice(String title, String content) {
    final topic = _detectTopic('$title\n$content');
    final todos = _buildLocalTodoSuggestions(
      noteTitle: title,
      noteContent: content,
      maxItems: 4,
    );

    final suggestions = <String>[];
    switch (topic) {
      case _NoteTopic.travel:
        suggestions.addAll([
          'Chốt trước ngân sách, phương tiện và chỗ ở để tránh cập rập sát ngày đi.',
          'Lên lịch trình vừa phải, mỗi ngày chỉ nên có vài điểm chính để chuyến đi thoải mái hơn.',
          'Kiểm tra thời tiết và chuẩn bị đồ theo hoạt động dự định.',
          'Giữ một khoản dự phòng cho chi phí phát sinh trong chuyến đi.',
        ]);
        break;
      case _NoteTopic.study:
        suggestions.addAll([
          'Chia nội dung học thành từng phần nhỏ thay vì ôn dồn một lúc.',
          'Ưu tiên phần trọng tâm hoặc phần bạn còn yếu trước.',
          'Sau mỗi buổi học nên chốt lại 3 ý chính và 1 việc cần làm tiếp.',
          'Nếu có deadline, hãy đặt mốc hoàn thành sớm hơn dự kiến một chút.',
        ]);
        break;
      case _NoteTopic.work:
        suggestions.addAll([
          'Chốt rõ đầu ra mong muốn trước khi bắt tay vào làm.',
          'Tách việc theo mức ưu tiên và người phụ trách để tránh bỏ sót.',
          'Ưu tiên xử lý các việc có phụ thuộc hoặc deadline gần trước.',
          'Cuối ngày nên rà lại tiến độ và cập nhật phần còn vướng.',
        ]);
        break;
      default:
        suggestions.addAll([
          'Chốt mục tiêu chính trước khi triển khai chi tiết.',
          'Chia việc thành các bước nhỏ để dễ theo dõi tiến độ.',
          'Ưu tiên các việc quan trọng hoặc có mốc thời gian rõ ràng.',
          'Rà lại kết quả sau mỗi bước để điều chỉnh sớm nếu cần.',
        ]);
        break;
    }

    if (todos.isNotEmpty) {
      suggestions[0] =
          'Bạn nên bắt đầu từ việc "${todos.first.task}" để tạo đà cho toàn bộ kế hoạch.';
    }

    final buffer = StringBuffer();
    buffer.writeln(title.trim().isNotEmpty ? 'Gợi ý cho "$title":' : 'Gợi ý:');
    for (var i = 0; i < suggestions.length; i++) {
      buffer.writeln('${i + 1}. ${suggestions[i]}');
    }
    return buffer.toString().trim();
  }

  static String _buildLocalNoteContent(String noteTitle) {
    final title = noteTitle.trim();
    final topic = _detectTopic(title);
    final label = suggestLabel(title, '');
    final todos = _buildLocalTodoSuggestions(
      noteTitle: title,
      noteContent: '',
      maxItems: 6,
    );

    final buffer = StringBuffer();
    buffer.writeln(title.isNotEmpty ? title : 'Ghi chú mới');
    buffer.writeln('');
    buffer.writeln('Nhãn đề xuất: $label');

    switch (topic) {
      case _NoteTopic.travel:
        final info = _extractTravelInfo(title);
        buffer.writeln('');
        buffer.writeln('Thông tin chính');
        if (info.destination != null) {
          buffer.writeln('- Điểm đến: ${info.destination}');
        }
        if (info.duration != null) {
          buffer.writeln('- Thời lượng: ${info.duration}');
        }
        if (info.timing != null) {
          buffer.writeln('- Thời điểm: ${info.timing}');
        }
        buffer.writeln(
          '- Mục tiêu chuyến đi: nghỉ ngơi, tham quan và trải nghiệm.',
        );
        break;
      case _NoteTopic.study:
        buffer.writeln('');
        buffer.writeln('Mục tiêu học tập');
        buffer.writeln('- Xác định phần kiến thức cần hoàn thành.');
        buffer.writeln('- Chốt thời gian học và mốc cần đạt.');
        break;
      case _NoteTopic.work:
        buffer.writeln('');
        buffer.writeln('Mục tiêu công việc');
        buffer.writeln('- Xác định kết quả đầu ra mong muốn.');
        buffer.writeln('- Chốt deadline và người liên quan.');
        break;
      default:
        buffer.writeln('');
        buffer.writeln('Mục tiêu');
        buffer.writeln(
          title.isNotEmpty
              ? '- Làm rõ mục tiêu và phạm vi của "$title".'
              : '- Xác định mục tiêu chính của ghi chú này.',
        );
        buffer.writeln('- Ghi lại đầu việc, thời gian và kết quả mong muốn.');
        break;
    }

    buffer.writeln('');
    buffer.writeln('Kế hoạch đề xuất');
    for (final todo in todos) {
      buffer.writeln('- ${todo.task}');
    }

    buffer.writeln('');
    buffer.writeln('Thông tin cần bổ sung');
    switch (topic) {
      case _NoteTopic.travel:
        buffer.writeln('- Ngân sách dự kiến cho đi lại, lưu trú và ăn uống.');
        buffer.writeln(
          '- Danh sách địa điểm muốn đi hoặc hoạt động muốn trải nghiệm.',
        );
        buffer.writeln('- Người đi cùng, giờ khởi hành và phương án dự phòng.');
        break;
      case _NoteTopic.study:
        buffer.writeln('- Tài liệu học, đề cương hoặc bài tập liên quan.');
        buffer.writeln('- Mốc thời gian ôn tập hoặc nộp bài.');
        buffer.writeln('- Những phần còn chưa chắc để ưu tiên ôn lại.');
        break;
      case _NoteTopic.work:
        buffer.writeln('- Deadline, người phụ trách và đầu ra cụ thể.');
        buffer.writeln('- Tài liệu, dữ liệu hoặc nguồn lực liên quan.');
        buffer.writeln('- Các rủi ro hoặc việc phụ thuộc cần theo dõi.');
        break;
      default:
        buffer.writeln('- Mốc thời gian hoặc deadline quan trọng.');
        buffer.writeln('- Người phụ trách hoặc người cần phối hợp.');
        buffer.writeln('- Tài liệu, chi phí hoặc ghi chú liên quan.');
        break;
    }

    return buffer.toString().trim();
  }

  static List<AiTodoSuggestion> _buildLocalTodoSuggestions({
    required String noteTitle,
    required String noteContent,
    int maxItems = 8,
  }) {
    final source = [
      noteTitle.trim(),
      noteContent.trim(),
    ].where((part) => part.isNotEmpty).join('\n');

    if (_isUnsafeRequest(source)) {
      return const [];
    }

    final topic = _detectTopic(source);
    final suggestions = <AiTodoSuggestion>[];
    final seen = <String>{};

    void addTask(String task, {String? priority, String? deadline}) {
      final cleaned = task.trim();
      if (cleaned.isEmpty) return;
      final key = _normalizeKey(cleaned);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      suggestions.add(
        AiTodoSuggestion(
          task: cleaned,
          priority: priority ?? _inferPriority(cleaned),
          deadline: deadline,
        ),
      );
    }

    for (final task in _buildTopicTasks(topic, noteTitle, noteContent)) {
      addTask(task);
      if (suggestions.length >= maxItems) {
        return suggestions;
      }
    }

    final actionableIdeas = _extractActionableIdeas(
      source,
      maxItems: maxItems * 2,
    );
    for (final idea in actionableIdeas) {
      addTask(_toActionTask(idea));
      if (suggestions.length >= maxItems) {
        return suggestions;
      }
    }

    for (final task in _buildGenericFallbackTasks(noteTitle)) {
      addTask(task);
      if (suggestions.length >= maxItems) {
        break;
      }
    }

    return suggestions;
  }

  static List<String> _buildTopicTasks(
    _NoteTopic topic,
    String noteTitle,
    String noteContent,
  ) {
    final source = '$noteTitle\n$noteContent';
    switch (topic) {
      case _NoteTopic.travel:
        return _buildTravelTasks(source);
      case _NoteTopic.study:
        return _buildStudyTasks(source);
      case _NoteTopic.work:
        return _buildWorkTasks(source);
      case _NoteTopic.family:
        return _buildFamilyTasks(source);
      case _NoteTopic.shopping:
        return _buildShoppingTasks(source);
      case _NoteTopic.finance:
        return _buildFinanceTasks(source);
      case _NoteTopic.health:
        return _buildHealthTasks(source);
      case _NoteTopic.event:
        return _buildEventTasks(source);
      case _NoteTopic.personal:
        return _buildPersonalTasks(source);
      case _NoteTopic.generic:
        return const [];
    }
  }

  static List<String> _buildTravelTasks(String source) {
    final info = _extractTravelInfo(source);
    final destinationSuffix = info.destination != null
        ? ' cho chuyến ${info.destination}'
        : '';
    final timingSuffix = info.timing != null ? ' ${info.timing}' : '';
    final staySuffix = info.duration != null
        ? ' cho ${info.duration}'
        : ' cho chuyến đi';

    return [
      'Chốt ngân sách$destinationSuffix',
      'Đặt phương tiện di chuyển$timingSuffix',
      'Tìm và đặt chỗ ở$staySuffix',
      'Lên lịch trình tham quan theo từng ngày',
      'Lập danh sách đồ cần mang theo',
      'Kiểm tra thời tiết và xác nhận giờ khởi hành',
    ];
  }

  static List<String> _buildStudyTasks(String source) {
    final subject = _extractPrimarySubject(source);
    final subjectSuffix = subject != null ? ' cho $subject' : '';
    return [
      'Chốt mục tiêu học tập$subjectSuffix',
      'Chia nội dung thành các phần nhỏ để học dần',
      'Lập lịch học hoặc lịch ôn tập cụ thể',
      'Chuẩn bị tài liệu, đề cương hoặc bài tập liên quan',
      'Tổng hợp các phần còn chưa rõ để ôn lại',
      'Tự kiểm tra tiến độ sau mỗi buổi học',
    ];
  }

  static List<String> _buildWorkTasks(String source) {
    final subject = _extractPrimarySubject(source);
    final subjectSuffix = subject != null ? ' cho $subject' : '';
    return [
      'Chốt mục tiêu và kết quả đầu ra$subjectSuffix',
      'Liệt kê đầu việc chính và người phụ trách',
      'Sắp xếp công việc theo mức ưu tiên và deadline',
      'Chuẩn bị tài liệu hoặc dữ liệu cần thiết',
      'Theo dõi tiến độ và cập nhật phần còn vướng',
      'Rà soát lại kết quả trước khi hoàn tất',
    ];
  }

  static List<String> _buildFamilyTasks(String source) {
    return [
      'Chốt việc chính cần chuẩn bị cho gia đình',
      'Xác định thời gian và địa điểm cụ thể',
      'Phân chia việc cho từng người nếu cần',
      'Chuẩn bị đồ dùng hoặc quà tặng liên quan',
      'Kiểm tra lại các việc quan trọng trước ngày diễn ra',
    ];
  }

  static List<String> _buildShoppingTasks(String source) {
    return [
      'Liệt kê món cần mua theo mức ưu tiên',
      'Chốt ngân sách cho từng nhóm món',
      'So sánh giá hoặc nơi mua phù hợp',
      'Kiểm tra lại số lượng và chất lượng trước khi thanh toán',
      'Rà soát lại các món đã mua để tránh thiếu sót',
    ];
  }

  static List<String> _buildFinanceTasks(String source) {
    return [
      'Ghi lại các khoản thu chi liên quan',
      'Chốt ngân sách hoặc hạn mức cần giữ',
      'Ưu tiên các khoản cần xử lý trước',
      'Theo dõi phát sinh và cập nhật số liệu',
      'Rà soát lại kết quả sau khi hoàn thành',
    ];
  }

  static List<String> _buildHealthTasks(String source) {
    return [
      'Ghi lại mục tiêu sức khỏe hoặc triệu chứng chính',
      'Đặt lịch khám, nghỉ ngơi hoặc tập luyện nếu cần',
      'Chuẩn bị thuốc, giấy tờ hoặc vật dụng liên quan',
      'Theo dõi tình trạng theo từng ngày',
      'Đánh giá lại kết quả và điều chỉnh kế hoạch',
    ];
  }

  static List<String> _buildEventTasks(String source) {
    return [
      'Chốt mục tiêu và quy mô của sự kiện',
      'Xác định thời gian, địa điểm và danh sách người tham gia',
      'Chuẩn bị nội dung, trang trí hoặc hậu cần cần thiết',
      'Phân chia việc cho từng hạng mục',
      'Kiểm tra lại toàn bộ trước thời điểm diễn ra',
    ];
  }

  static List<String> _buildPersonalTasks(String source) {
    return [
      'Chốt mục tiêu chính của việc này',
      'Liệt kê các bước cần làm theo thứ tự',
      'Sắp xếp thời gian thực hiện phù hợp',
      'Chuẩn bị những thứ cần thiết trước khi bắt đầu',
      'Rà soát lại kết quả sau khi hoàn thành',
    ];
  }

  static List<String> _buildGenericFallbackTasks(String noteTitle) {
    return [
      // Removed redundant title-based task
      'Liệt kê 3 đến 5 đầu việc cụ thể cần hoàn thành',
      'Sắp xếp việc theo mức ưu tiên và thời gian',
      'Chuẩn bị tài liệu hoặc nguồn lực cần thiết',
      'Rà soát lại kết quả trước khi kết thúc',
    ];
  }

  static List<String> _extractKeyIdeas(String source, {int maxItems = 6}) {
    if (source.trim().isEmpty) return [];

    final ideas = <String>[];
    final seen = <String>{};
    for (final piece in _splitSourcePieces(source)) {
      final cleaned = _cleanIdea(piece);
      final key = _normalizeKey(cleaned);
      if (cleaned.isEmpty || seen.contains(key) || _isWeakIdea(cleaned)) {
        continue;
      }
      seen.add(key);
      ideas.add(_capitalize(cleaned));
      if (ideas.length >= maxItems) break;
    }
    return ideas;
  }

  static List<String> _extractActionableIdeas(
    String source, {
    int maxItems = 8,
  }) {
    final ideas = <String>[];
    final seen = <String>{};

    for (final piece in _splitSourcePieces(source)) {
      final cleaned = _cleanIdea(piece);
      final key = _normalizeKey(cleaned);
      if (cleaned.isEmpty || seen.contains(key) || _isWeakIdea(cleaned)) {
        continue;
      }
      if (_looksLikeTitleOnlyPhrase(cleaned)) {
        continue;
      }
      seen.add(key);
      ideas.add(cleaned);
      if (ideas.length >= maxItems) {
        break;
      }
    }

    return ideas;
  }

  static Iterable<String> _splitSourcePieces(String source) sync* {
    final normalized = source
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[•\-\*]+'), '\n')
        .replaceAll(RegExp(r'\n+'), '\n');

    for (final part in normalized.split(RegExp(r'[\n\.\!\?;]+'))) {
      yield part.trim();
    }
  }

  static String _cleanIdea(String value) {
    var result = value.trim();
    result = result.replaceFirst(RegExp(r'^\d+[\)\.\-: ]*'), '').trim();
    result = result
        .replaceFirst(
          RegExp(
            r'^(todo|checklist|ghi chú|ghi chu)\s*[:\-]*\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    if (result.length > 120) {
      result = result.substring(0, 120).trim();
    }
    return result;
  }

  static bool _isWeakIdea(String value) {
    final normalized = _normalizeText(value);
    if (normalized.length < 4) return true;

    const weakIdeas = {
      'cong viec',
      'muc tieu',
      'noi dung',
      'ghi chu',
      'thong tin',
      'ke hoach',
      'chi tiet',
      'du kien',
      'viec',
      'task',
      'todo',
    };

    if (weakIdeas.contains(normalized)) return true;
    if (RegExp(r'^\d+$').hasMatch(normalized)) return true;
    return false;
  }

  static bool _looksLikeTitleOnlyPhrase(String value) {
    final normalized = _normalizeText(value);
    return normalized.startsWith('ke hoach ') ||
        normalized.startsWith('lap ke hoach ') ||
        normalized.startsWith('len ke hoach ') ||
        normalized.startsWith('ghi chu ') ||
        normalized.startsWith('muc tieu ');
  }

  static String _toActionTask(String idea) {
    final trimmed = idea.trim();
    if (trimmed.isEmpty) return trimmed;

    final lower = _normalizeText(trimmed);
    const actionPrefixes = [
      'lap ',
      'chuan bi ',
      'kiem tra ',
      'lien he ',
      'dat ',
      'mua ',
      'xac dinh ',
      'sap xep ',
      'viet ',
      'hoan thanh ',
      'tong hop ',
      'chot ',
      'len ',
      'ra soat ',
    ];

    for (final prefix in actionPrefixes) {
      if (lower.startsWith(prefix)) {
        return _capitalize(trimmed);
      }
    }

    if (lower.contains('ngan sach')) {
      return 'Chốt ngân sách cho phần này';
    }
    if (lower.contains('lich trinh')) {
      return 'Lên lịch trình chi tiết';
    }
    if (lower.contains('dia diem')) {
      return 'Chọn địa điểm phù hợp';
    }
    if (lower.contains('khach san') ||
        lower.contains('homestay') ||
        lower.contains('cho o')) {
      return 'Đặt chỗ ở phù hợp';
    }
    if (lower.contains('ve') || lower.contains('phuong tien')) {
      return 'Đặt phương tiện di chuyển';
    }
    if (lower.contains('tai lieu')) {
      return 'Chuẩn bị tài liệu liên quan';
    }
    if (lower.contains('deadline')) {
      return 'Chốt deadline và thứ tự ưu tiên';
    }

    return 'Làm rõ: ${trimmed[0].toLowerCase()}${trimmed.substring(1)}';
  }

  static String _inferPriority(String task) {
    final lower = _normalizeText(task);
    if (lower.contains('dat ') ||
        lower.contains('chot ') ||
        lower.contains('deadline') ||
        lower.contains('gio khoi hanh') ||
        lower.contains('lich') ||
        lower.contains('ngan sach')) {
      return 'high';
    }
    if (lower.contains('kiem tra') ||
        lower.contains('chuan bi') ||
        lower.contains('tong hop') ||
        lower.contains('ra soat')) {
      return 'medium';
    }
    return 'low';
  }

  static _NoteTopic _detectTopic(String text) {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return _NoteTopic.generic;

    int score(List<String> keywords) {
      var total = 0;
      for (final keyword in keywords) {
        if (normalized.contains(keyword)) total++;
      }
      return total;
    }

    final scores = <_NoteTopic, int>{
      _NoteTopic.work: score([
        'cong viec',
        'du an',
        'meeting',
        'hop',
        'khach hang',
        'bao cao',
        'deadline',
        'doi tac',
        'trien khai',
        'ke hoach kinh doanh',
        'hop dong',
        'van phong',
        'cong ty',
        'doanh nghiep',
        'nhan su',
        'tai lieu',
        'proposal',
        'pitch',
      ]),
      _NoteTopic.study: score([
        'hoc',
        'on thi',
        'bai tap',
        'kiem tra',
        'de cuong',
        'thuyet trinh',
        'mon hoc',
        'do an',
        'giua ky',
        'cuoi ky',
        'luan van',
        'nghien cuu',
        'scholarship',
        'hoc bong',
      ]),
      _NoteTopic.family: score([
        'gia dinh',
        'ba me',
        'bo me',
        'vo chong',
        'con cai',
        'sinh nhat',
        've que',
        'don con',
        'dam gio',
        'le tet',
        'an com',
        'mua bim',
        'sua cho con',
      ]),
      _NoteTopic.travel: score([
        'du lich',
        'chuyen di',
        'di choi',
        'tham quan',
        'lich trinh',
        'khach san',
        'homestay',
        'check in',
        've may bay',
        'dat phong',
        'da lat',
        'vung tau',
        'ha noi',
        'da nang',
        'phu quoc',
        'nha trang',
        'bali',
        'thai lan',
        'duong bay',
        'hanh ly',
      ]),
      _NoteTopic.shopping: score([
        'mua sam',
        'shopping',
        'gio hang',
        'don hang',
        'mua',
        'san pham',
        'shopee',
        'lazada',
        'tiki',
        'gia bao nhieu',
        'thanh toan',
      ]),
      _NoteTopic.finance: score([
        'tai chinh',
        'chi tieu',
        'tiet kiem',
        'ngan sach ca nhan',
        'thu chi',
        'hoa don',
        'tra no',
        'vay von',
        'dau tu',
        'chung khoan',
        'lai suat',
        'ngan hang',
      ]),
      _NoteTopic.health: score([
        'suc khoe',
        'kham',
        'thuoc',
        'benh vien',
        'the duc',
        'tap gym',
        'dinh duong',
        'yoga',
        'chay bo',
        'uong nuoc',
        'vitamin',
        'bac si',
      ]),
      _NoteTopic.event: score([
        'su kien',
        'sinh nhat',
        'tiec',
        'party',
        'dam cuoi',
        'hoi nghi',
        'workshop',
        'seminar',
      ]),
      _NoteTopic.personal: score([
        'ca nhan',
        'thoi quen',
        'lich ca nhan',
        'muc tieu ca nhan',
        'ban than',
      ]),
    };

    _NoteTopic bestTopic = _NoteTopic.generic;
    var bestScore = 0;
    scores.forEach((topic, topicScore) {
      if (topicScore > bestScore) {
        bestScore = topicScore;
        bestTopic = topic;
      }
    });

    if (bestScore <= 0) {
      if (normalized.contains('ke hoach') || normalized.contains('lich')) {
        return _NoteTopic.personal;
      }
      return _NoteTopic.generic;
    }

    return bestTopic;
  }

  static _TravelInfo _extractTravelInfo(String source) {
    final text = source.trim();
    if (text.isEmpty) return const _TravelInfo();

    final destinationMatch = RegExp(
      r'(?:du lịch|du lich|đi du lịch|di du lich|đi|di|đến|den|tới|toi)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(text);

    String? destination;
    if (destinationMatch != null) {
      var candidate = destinationMatch.group(1)?.trim() ?? '';
      candidate = candidate
          .split(
            RegExp(
              r'\b\d+\s*(?:ngày|ngay)\b|\b(?:vào|vao|thứ|thu|tuần|tuan|ngày|ngay|cuối tuần|cuoi tuan)\b|[,.;]',
              caseSensitive: false,
            ),
          )
          .first
          .trim();
      if (candidate.isNotEmpty && candidate.length <= 40) {
        destination = candidate;
      }
    }

    final durationMatch = RegExp(
      r'\d+\s*(?:ngày|ngay)(?:\s*\d+\s*(?:đêm|dem))?',
      caseSensitive: false,
    ).firstMatch(text);

    final timingMatch = RegExp(
      r'(?:thứ|thu)\s*[2-7](?:\s+(?:tuần|tuan)\s+sau)?|(?:chủ nhật|chu nhat)(?:\s+(?:tuần|tuan)\s+sau)?|ngày mai|ngay mai|cuối tuần|cuoi tuan|tuần sau|tuan sau',
      caseSensitive: false,
    ).firstMatch(text);

    return _TravelInfo(
      destination: destination,
      duration: durationMatch?.group(0)?.trim(),
      timing: timingMatch?.group(0)?.trim(),
    );
  }

  static String? _extractPrimarySubject(String source) {
    final ideas = _extractKeyIdeas(source, maxItems: 1);
    return ideas.isEmpty ? null : ideas.first;
  }

  static bool _isUnsafeRequest(String text) {
    final normalized = _normalizeText(text);
    const keywords = [
      'cuop',
      'ngan hang',
      'tan cong',
      'giet',
      'bom',
      'vu khi',
      'hack',
      'lua dao',
      'ma tuy',
      'khung bo',
      'dot nhap',
      'an cap',
      'dau doc',
      'ban sung',
      'danh bom',
    ];
    return keywords.any(normalized.contains);
  }

  static String _unsafeResponse() {
    return 'Mình không thể hỗ trợ nội dung gây hại, phạm pháp hoặc nguy hiểm. '
        'Nếu muốn, mình có thể giúp chuyển chủ đề này sang một kế hoạch học tập, công việc, du lịch hoặc quản lý rủi ro an toàn.';
  }

  static String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('đ', 'd')
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ả', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('ạ', 'a')
        .replaceAll('ă', 'a')
        .replaceAll('ắ', 'a')
        .replaceAll('ằ', 'a')
        .replaceAll('ẳ', 'a')
        .replaceAll('ẵ', 'a')
        .replaceAll('ặ', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ấ', 'a')
        .replaceAll('ầ', 'a')
        .replaceAll('ẩ', 'a')
        .replaceAll('ẫ', 'a')
        .replaceAll('ậ', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ẻ', 'e')
        .replaceAll('ẽ', 'e')
        .replaceAll('ẹ', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ế', 'e')
        .replaceAll('ề', 'e')
        .replaceAll('ể', 'e')
        .replaceAll('ễ', 'e')
        .replaceAll('ệ', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('ỉ', 'i')
        .replaceAll('ĩ', 'i')
        .replaceAll('ị', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('ỏ', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ọ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ố', 'o')
        .replaceAll('ồ', 'o')
        .replaceAll('ổ', 'o')
        .replaceAll('ỗ', 'o')
        .replaceAll('ộ', 'o')
        .replaceAll('ơ', 'o')
        .replaceAll('ớ', 'o')
        .replaceAll('ờ', 'o')
        .replaceAll('ở', 'o')
        .replaceAll('ỡ', 'o')
        .replaceAll('ợ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('ủ', 'u')
        .replaceAll('ũ', 'u')
        .replaceAll('ụ', 'u')
        .replaceAll('ư', 'u')
        .replaceAll('ứ', 'u')
        .replaceAll('ừ', 'u')
        .replaceAll('ử', 'u')
        .replaceAll('ữ', 'u')
        .replaceAll('ự', 'u')
        .replaceAll('ý', 'y')
        .replaceAll('ỳ', 'y')
        .replaceAll('ỷ', 'y')
        .replaceAll('ỹ', 'y')
        .replaceAll('ỵ', 'y')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeKey(String value) {
    return _normalizeText(value);
  }

  static String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _ParsedResponse {
  final String cleanText;
  final List<AiTodoSuggestion> todos;

  const _ParsedResponse({required this.cleanText, required this.todos});
}

class _TravelInfo {
  final String? destination;
  final String? duration;
  final String? timing;

  const _TravelInfo({this.destination, this.duration, this.timing});
}


