# Hướng dẫn tích hợp AI Feature (Groq API - LPU Speed)

## 1. Thêm package vào pubspec.yaml

Đảm bảo bạn đã có thư viện kết nối mạng trong `pubspec.yaml`:
```yaml
dependencies:
  http: ^1.2.0
```

Chạy: `flutter pub get` để cài đặt.

---

## 2. Cấu hình Groq API Key

Ứng dụng SNote tích hợp dịch vụ Groq LPU API để chạy mô hình ngôn ngữ lớn **Llama 3.3 (70B)** và **Llama 3.1 (8B)** với tốc độ phản hồi cực nhanh bằng tiếng Việt.

### Đăng ký API Key:
1. Truy cập [Groq Console](https://console.groq.com) và đăng ký tài khoản (miễn phí).
2. Tạo một API Key mới (bắt đầu bằng `gsk_`).

### Đặt cấu hình API Key:
Có 2 cách để ứng dụng nhận API Key:

* **Cách 1 (Khuyên dùng - Bảo mật):** Truyền qua tham số biên dịch khi chạy/build:
  ```bash
  flutter run --dart-define=GROQ_API_KEY=your_api_key_here
  ```
* **Cách 2:** Điền trực tiếp API Key làm giá trị mặc định trong file `lib/controllers/services/groq_client.dart`:
  ```dart
  static const String _apiKey = String.fromEnvironment(
    'GROQ_API_KEY', 
    defaultValue: 'gsk_your_real_api_key_here'
  );
  ```

---

## 3. Cấu hình Firestore Rules

Thêm quy định sau vào file `firestore.rules` để bảo vệ và lưu trữ lịch sử chat riêng tư của từng tài khoản:
```javascript
match /ai_chats/{userId}/sessions/{sessionId} {
  allow read, write: if request.auth != null 
    && userId == request.auth.token.email.replace('.', '_').replace('@', '_');
  
  match /messages/{messageId} {
    allow read, write: if request.auth != null;
  }
}
```

---

## 4. Cách sử dụng trong UI

### Mở Chat AI độc lập (Không có ngữ cảnh):
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const AIChatNoteScreen()),
);
```

### Mở Chat AI với ngữ cảnh ghi chú (Để AI hiểu nội dung ghi chú):
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => AIChatNoteScreen(
      noteTitle: note.title,
      noteContent: note.content,
    ),
  ),
);
```

### Gắn vào nút "Trợ lý AI" trong màn hình Tạo/Sửa ghi chú:
```dart
IconButton(
  icon: const Icon(Icons.auto_awesome_outlined),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AIChatNoteScreen(
          noteTitle: _titleController.text,
          noteContent: _contentController.text,
          onTodosAccepted: (suggestions) {
            setState(() {
              for (final s in suggestions) {
                _todos.add(TodoItem(task: s.task, priority: s.priority));
              }
              _isTodo = true;
            });
          },
        ),
      ),
    );
  },
)
```

---

## Các tính năng nổi bật của Trợ lý AI trong SNote:
1. **Lịch sử trò chuyện**: Các tin nhắn thoại và hội thoại chat được lưu trữ đồng bộ trên Firestore, không bị mất khi đóng ứng dụng.
2. **Gợi ý Todo thông minh**: AI tự động trích xuất JSON array chứa các đầu việc đề xuất có gán sẵn Độ ưu tiên (Urgent/High/Medium/Low) và Hạn chót (Deadline) để người dùng thêm nhanh vào Kanban.
3. **Phân tích Metadata offline (Fallback)**: Khi không có kết nối mạng hoặc chưa cấu hình API Key, hệ thống tự chuyển đổi sang bộ máy phân tích regex và keyword cục bộ để tự động gán nhãn (Label), mức độ ưu tiên và đặt giờ nhắc nhở mà không gây gián đoạn trải nghiệm người dùng.
