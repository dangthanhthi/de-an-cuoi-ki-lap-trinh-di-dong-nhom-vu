import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client để gọi Groq API (miễn phí, không cần thẻ tín dụng).
/// Sử dụng model Llama 3.3 70B chạy trên phần cứng LPU.
///
/// Đăng ký API key miễn phí tại: https://console.groq.com
class GroqClient {
  // =====================================================================
  // CẤU HÌNH — Thay API key của bạn vào đây
  // =====================================================================
  static const String _apiKey = String.fromEnvironment('GROQ_API_KEY', defaultValue: 'YOUR_GROQ_API_KEY_HERE');

  // Model chính: Llama 3.3 70B (chất lượng cao nhất, miễn phí)
  static const String _defaultModel = 'llama-3.3-70b-versatile';

  // Model nhanh: Llama 3.1 8B (nhanh hơn, dùng cho gợi ý nhanh)
  static const String _fastModel = 'llama-3.1-8b-instant';

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxRetries = 2;

  // =====================================================================
  // SYSTEM PROMPTS tiếng Việt chuyên biệt cho SNote
  // =====================================================================

  /// System prompt cho Chat AI chung
  static const String chatSystemPrompt = '''
Bạn là SNote AI — trợ lý thông minh tích hợp trong ứng dụng ghi chú SNote.

NGUYÊN TẮC:
- Luôn trả lời bằng TIẾNG VIỆT tự nhiên, thân thiện, ngắn gọn.
- Xưng hô "mình" (AI) và "bạn" (người dùng).
- Tập trung vào việc giúp người dùng quản lý ghi chú, công việc, lịch trình hiệu quả.
- Khi được hỏi về nội dung ghi chú, hãy phân tích sâu và đưa ra gợi ý cụ thể.
- Không bịa thông tin. Nếu không biết, hãy nói thẳng.
- Trả lời ngắn gọn, dưới 200 từ trừ khi người dùng yêu cầu chi tiết.
- KHÔNG sử dụng markdown formatting (**, ##, vv). Chỉ dùng text thuần, gạch đầu dòng (-) và số thứ tự.
''';

  /// System prompt cho Chat AI có ngữ cảnh ghi chú
  static String chatWithNoteSystemPrompt(String noteTitle, String noteContent) {
    return '''
$chatSystemPrompt

NGỮCẢNH GHI CHÚ HIỆN TẠI:
- Tiêu đề: "$noteTitle"
- Nội dung: "$noteContent"

Hãy trả lời dựa trên ngữ cảnh ghi chú này. Khi người dùng hỏi về ghi chú, hãy phân tích nội dung trên để đưa ra câu trả lời chính xác.
''';
  }

  /// System prompt cho gợi ý Todo
  static const String todoSystemPrompt = '''
Bạn là SNote AI. Nhiệm vụ: phân tích nội dung ghi chú và tạo danh sách công việc (todo) cụ thể.

QUY TẮC BẮT BUỘC:
- Trả về ĐÚNG định dạng JSON array, KHÔNG có text nào khác.
- Mỗi todo có: "task" (string), "priority" (string: "urgent"/"high"/"medium"/"low"), "deadline" (string hoặc null).
- Tạo 4-8 todo items, cụ thể và hành động được (actionable).
- Priority dựa trên mức độ khẩn cấp và quan trọng của từng việc.
- Deadline dạng "trong X ngày" hoặc null nếu không xác định được.

VÍ DỤ OUTPUT:
[{"task":"Chốt danh sách tài liệu cần ôn","priority":"high","deadline":"trong 1 ngày"},{"task":"Ôn lại chương 3 về cấu trúc dữ liệu","priority":"medium","deadline":"trong 3 ngày"}]
''';

  /// System prompt cho tóm tắt
  static const String summarySystemPrompt = '''
Bạn là SNote AI. Nhiệm vụ: tóm tắt nội dung ghi chú một cách ngắn gọn, mạch lạc.

QUY TẮC:
- Tóm tắt bằng tiếng Việt, dưới 150 từ.
- Nêu rõ các điểm chính, mục tiêu và hành động cần làm.
- Không bịa thêm thông tin không có trong ghi chú gốc.
- Sử dụng gạch đầu dòng (-) cho các điểm chính.
''';

  /// System prompt cho lời khuyên chiến lược
  static const String adviceSystemPrompt = '''
Bạn là SNote AI. Nhiệm vụ: đưa ra 3-5 lời khuyên chiến lược cụ thể dựa trên nội dung ghi chú.

QUY TẮC:
- Lời khuyên phải thực tế, cụ thể và áp dụng được ngay.
- Dựa trên nội dung thực của ghi chú, không chung chung.
- Đánh số thứ tự 1, 2, 3...
- Mỗi lời khuyên dưới 2 câu.
- Tổng cộng dưới 200 từ.
''';

  /// System prompt cho gợi ý nội dung ghi chú
  static const String suggestContentSystemPrompt = '''
Bạn là SNote AI. Nhiệm vụ: dựa trên tiêu đề ghi chú, gợi ý nội dung chi tiết cho ghi chú đó.

QUY TẮC:
- Viết nội dung bằng tiếng Việt, có cấu trúc rõ ràng.
- Bao gồm: Mục tiêu, Kế hoạch đề xuất (3-6 bước), Thông tin cần bổ sung.
- Sử dụng gạch đầu dòng (-) cho danh sách.
- Tổng cộng dưới 300 từ.
- Viết dưới dạng nội dung ghi chú (không phải hội thoại).
''';

  // =====================================================================
  // API METHODS
  // =====================================================================

  /// Kiểm tra API key đã được cấu hình chưa
  static bool get isConfigured =>
      _apiKey.isNotEmpty && _apiKey != 'YOUR_GROQ_API_KEY_HERE';

  /// Gọi Groq Chat Completion API.
  /// Trả về nội dung text phản hồi từ AI.
  /// Throw [GroqException] nếu có lỗi.
  static Future<String> chatCompletion({
    required List<Map<String, String>> messages,
    String? model,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    if (!isConfigured) {
      throw const GroqException('API key chưa được cấu hình.');
    }

    final body = jsonEncode({
      'model': model ?? _defaultModel,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
    });

    Exception? lastError;
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(_baseUrl),
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
              },
              body: body,
            )
            .timeout(_timeout);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final message = choices[0]['message'] as Map<String, dynamic>?;
            return (message?['content'] ?? '').toString().trim();
          }
          throw const GroqException('API trả về phản hồi rỗng.');
        }

        // Xử lý các mã lỗi
        if (response.statusCode == 429) {
          // Rate limit — chờ rồi thử lại
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
            continue;
          }
          throw const GroqException(
            'AI đang bận (hết quota tạm thời). Vui lòng thử lại sau vài giây.',
          );
        }

        if (response.statusCode == 401) {
          throw const GroqException('API key không hợp lệ.');
        }

        if (response.statusCode >= 500) {
          if (attempt < _maxRetries) {
            await Future.delayed(Duration(seconds: 1 * (attempt + 1)));
            continue;
          }
          throw GroqException(
            'Máy chủ AI tạm thời gặp sự cố (${response.statusCode}).',
          );
        }

        throw GroqException(
          'Lỗi API: ${response.statusCode} - ${response.body}',
        );
      } on TimeoutException {
        lastError = const GroqException('Kết nối AI bị timeout.');
        if (attempt < _maxRetries) continue;
      } on http.ClientException catch (e) {
        lastError = GroqException('Lỗi mạng: ${e.message}');
        if (attempt < _maxRetries) continue;
      } catch (e) {
        if (e is GroqException) rethrow;
        lastError = GroqException('Lỗi không xác định: $e');
        if (attempt < _maxRetries) continue;
      }
    }

    throw lastError ?? const GroqException('Không thể kết nối AI.');
  }

  /// Chat completion với model nhanh (cho gợi ý nhanh)
  static Future<String> fastCompletion({
    required List<Map<String, String>> messages,
    double temperature = 0.5,
    int maxTokens = 512,
  }) {
    return chatCompletion(
      messages: messages,
      model: _fastModel,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  /// Tạo danh sách messages cho API từ system prompt + user messages
  static List<Map<String, String>> buildMessages({
    required String systemPrompt,
    required String userMessage,
    List<Map<String, String>>? history,
  }) {
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    // Thêm lịch sử hội thoại (giới hạn 10 tin nhắn gần nhất)
    if (history != null && history.isNotEmpty) {
      final recentHistory = history.length > 10
          ? history.sublist(history.length - 10)
          : history;
      messages.addAll(recentHistory);
    }

    messages.add({'role': 'user', 'content': userMessage});
    return messages;
  }
}

/// Exception cho lỗi Groq API
class GroqException implements Exception {
  final String message;
  const GroqException(this.message);

  @override
  String toString() => message;
}
