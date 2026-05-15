# SNote - Hệ Sinh Thái Quản Lý Ghi Chú & Nhóm Thông Minh

SNote là một ứng dụng di động mạnh mẽ được xây dựng trên nền tảng Flutter, giúp người dùng không chỉ quản lý ghi chú cá nhân hiệu quả mà còn tối ưu hóa quy trình làm việc nhóm thông qua các tính năng cộng tác thời gian thực.

## 🚀 Tính Năng Chính

### 📝 Quản Lý Ghi Chú Đa Năng
- **Ghi chú đa phương tiện**: Hỗ trợ văn bản, hình ảnh và đính kèm tệp tin (PDF, Doc...).
- **Phân loại thông minh**: Tổ chức ghi chú theo nhãn (Công việc, Học tập, Cá nhân...) và màu sắc.
- **Checklist & To-do**: Tích hợp danh sách việc cần làm ngay trong ghi chú.
- **Nhắc nhở (Reminders)**: Cài đặt thông báo báo thức để không bỏ lỡ các deadline quan trọng.
- **Ưu tiên & Ghim**: Đánh dấu các ghi chú quan trọng lên đầu danh sách.

### 👥 Cộng Tác Nhóm
- **Quản lý nhóm**: Tạo nhóm, mời thành viên qua Email hoặc Mã nhóm (Group Code).
- **Chia sẻ ghi chú**: Mọi thành viên trong nhóm có thể xem và đóng góp vào ghi chú chung.
- **Thảo luận (Comments)**: Hệ thống bình luận trực tiếp dưới mỗi ghi chú nhóm.
- **Trò chuyện (Chat)**: Kênh chat riêng biệt cho từng nhóm, hỗ trợ gửi ảnh và tệp tin.

### 📅 Công Cụ Hỗ Trợ
- **Lịch trình (Calendar)**: Giao diện lịch trực quan giúp theo dõi ghi chú và nhắc nhở theo thời gian.
- **Thống kê (Statistics)**: Biểu đồ phân tích hiệu suất công việc và thói quen ghi chú.
- **Lịch sử hoạt động**: Theo dõi mọi thay đổi và hoạt động của người dùng trên hệ thống.

### 🛡️ Quản Trị Hệ Thống (Admin)
- **Quản lý người dùng**: Xem danh sách, tìm kiếm, khóa hoặc xóa tài khoản vi phạm.
- **Phân quyền**: Hệ thống phân quyền rõ ràng giữa Admin và User.

### 🛠️ Tiện Ích Khác
- **AI Speech-to-Text**: Chuyển đổi giọng nói thành văn bản nhanh chóng.
- **Giao diện tối (Dark Mode)**: Tối ưu hóa trải nghiệm người dùng trong điều kiện ánh sáng yếu.
- **Bảo mật**: Xác thực người dùng mạnh mẽ qua Firebase Auth.

## 💻 Công Nghệ Sử Dụng

- **Ngôn ngữ**: [Dart](https://dart.dev/)
- **Framework**: [Flutter](https://flutter.dev/)
- **Backend**: [Firebase](https://firebase.google.com/)
  - Authentication (Xác thực)
  - Cloud Firestore (Cơ sở dữ liệu thời gian thực)
  - Cloud Storage (Lưu trữ tệp tin)
- **Quản lý trạng thái**: Provider / ValueNotifier
- **Tiện ích khác**: Speech to Text, Local Notifications, Image/File Picker.

## 📥 Cài Đặt

1. **Yêu cầu hệ thống**:
   - Flutter SDK: `^3.10.7`
   - Android Studio / VS Code đã cài đặt plugin Flutter & Dart.

2. **Các bước thực hiện**:
   ```bash
   # Clone dự án
   git clone [URL_GITO_CUA_BAN]

   # Di chuyển vào thư mục dự án
   cd de-an-cuoi-ki-lap-trinh-di-dong-nhom-vu

   # Cài đặt các dependencies
   flutter pub get

   # Chạy ứng dụng
   flutter run
   ```

## 📂 Cấu Trúc Thư Mục

- `lib/models`: Định nghĩa các đối tượng dữ liệu (Note, User, Group...).
- `lib/views`: Giao diện người dùng (Screens, Widgets).
- `lib/controllers`: Xử lý logic nghiệp vụ và tương tác Firebase (AppState, NotificationService...).
- `lib/utils`: Các hàm tiện ích bổ trợ.

## 👥 Đội Ngũ Phát Triển

Dự án được thực hiện bởi **Nhóm Vũ** cho học phần Lập trình thiết bị di động.

---
*Cảm ơn bạn đã quan tâm đến dự án SNote!*
