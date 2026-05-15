# Hướng dẫn tích hợp AI Feature (Gemini 1.5 Flash - FREE)

## 1. Thêm package vào pubspec.yaml

Đảm bảo bạn đã có các thư viện sau:
```yaml
dependencies:
  google_generative_ai: ^0.4.7
  http: ^1.2.0   # Cần cho một số xử lý mở rộng
```

Chạy: `flutter pub get`

---

## 2. Cấu hình Gemini API Key

Mở `ai_service.dart`, tìm dòng:
```dart
static const String _apiKey = 'AIzaSyCn...'; // Key của bạn đã được điền sẵn
```
Đây là gói **Gemini 1.5 Flash** hoàn toàn miễn phí (giới hạn 1500 request/ngày), rất phù hợp cho học tập và demo.

---

## 3. Cấu hình Firestore Rules

Thêm vào `firestore.rules` để lưu lịch sử chat:
```
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

### Mở Chat AI độc lập
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const AIChatNoteScreen()),
);
```

### Mở Chat AI với ngữ cảnh ghi chú (để AI hiểu nội dung bạn đang viết)
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

### Gắn vào nút "Gợi ý AI" trong CreateEditNoteScreen
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
                _todos.add(TodoItem(task: s.task));
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

## Các tính năng nổi bật của bản cập nhật này:
1.  **Lịch sử chat:** Tin nhắn được lưu vào Firestore, không bị mất khi thoát ứng dụng.
2.  **Retry tự động:** Nếu mạng yếu hoặc server AI bận, app sẽ tự động thử lại (tối đa 3 lần).
3.  **Gợi ý Todo:** AI trả về JSON chuẩn, cho phép người dùng nhấn nút để thêm thẳng công việc vào ghi chú hiện tại.
4.  **UI Cao cấp:** Typing indicator (3 chấm animation), chip tác vụ nhanh, card gợi ý công việc đẹp mắt.
