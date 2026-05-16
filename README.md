# 🚀 SNote: Hệ Sinh Thái Quản Lý Ghi Chú & Nhóm Cộng Tác Thông Minh

![Banner](https://img.shields.io/badge/Flutter-3.10.7-blue.svg) ![Firebase](https://img.shields.io/badge/Firebase-Latest-orange.svg) ![Giấy_phép](https://img.shields.io/badge/Giấy_phép-MIT-green.svg)

**SNote** không chỉ đơn thuần là một ứng dụng ghi chú. Đây là một giải pháp toàn diện giúp xóa tan ranh giới giữa **Quản lý kiến thức cá nhân** và **Cộng tác nhóm**. Được xây dựng trên nền tảng Flutter hiện đại và nền tảng đám mây Firebase thời gian thực, SNote mang đến trải nghiệm mượt mà, thông minh và đầy cảm hứng.

---

## 🌟 Tầm Nhìn Dự Án
Trong kỷ nguyên số, thông tin thường bị phân tán. SNote ra đời với sứ mệnh hợp nhất:
- **Ghi chú**: Nơi lưu giữ và nuôi dưỡng ý tưởng.
- **Công việc**: Nơi biến ý tưởng thành hành động thông qua mô hình bảng Kanban.
- **Giao tiếp**: Nơi thảo luận và thống nhất mục tiêu trong tập thể.

---

## 🛠️ Hệ Sinh Thái Tính Năng Vượt Trội

### 1. Quản Lý Ghi Chú Hiện Đại
*   **Đa phương tiện**: Hỗ trợ đính kèm hình ảnh, tệp tin (PDF, Word) và các bản vẽ tay.
*   **Cá nhân hóa tối đa**: Tự do thay đổi màu sắc bìa, phông chữ, kích thước và định dạng văn bản (Đậm, Nghiêng, Gạch chân).
*   **Hệ thống Nhãn (Labels)**: Phân loại khoa học giúp tìm kiếm thông tin chỉ trong một nốt nhạc.
*   **Hạn ngạch Ghim Thông Minh (3x3)**:
    - Cơ chế ghim thông minh: Tối đa 3 ghim cho mỗi loại (Cá nhân, Chia sẻ, Được giao).
    - Giúp màn hình chính luôn gọn gàng, tập trung vào những việc quan trọng nhất.

### 2. Quản Lý Công Việc & Bảng Kanban
*   **Đồng bộ tự động**: Các danh sách việc cần làm (Todo) trong ghi chú nhóm sẽ tự động xuất hiện trên bảng Kanban.
*   **Cập nhật trạng thái 1-Chạm**: Nhấn giữ thẻ công việc để chuyển nhanh giữa các trạng thái: *Cần làm*, *Đang làm*, và *Hoàn thành*.
*   **Phản hồi trực quan**: Hiệu ứng rung nhẹ và thông báo SnackBar ngay khi có thay đổi trạng thái thành công.

### 3. Cộng Tác Nhóm & Trung Tâm Thảo Luận
*   **Quản Lý Nhóm Chuyên Nghiệp**: Phân quyền rõ ràng (Trưởng nhóm/Thành viên), mời bạn bè tham gia qua mã nhóm hoặc email.
*   **Bộ lọc thép (Iron Filter)**: 
    - Thuật toán thông minh tự động "thu hồi" các ghi chú bị lỗi dữ liệu về đúng mục cá nhân.
    - Phân tách rõ ràng luồng dữ liệu: **Của tôi**, **Được chia sẻ**, và **Nhiệm vụ được giao**.
*   **Trung tâm Giao tiếp**:
    - **Trò chuyện Nhóm**: Nhắn tin thời gian thực với tốc độ cực nhanh.
    - **Trạng thái Đã xem**: Hiển thị avatar những người đã đọc tin nhắn cực kỳ trực quan.
    - **Cảm xúc (Reactions)**: Thả biểu tượng cảm xúc để tương tác nhanh với đồng đội.

### 4. Công Nghệ & Trí Tuệ Nhân Tạo
*   **Chuyển Giọng Nói Thành Văn Bản**: Ghi âm và tự động chuyển hóa thành chữ viết với độ chính xác cao.
*   **Thống kê & Phân tích**: Biểu đồ trực quan hóa năng suất làm việc và thói quen ghi chú theo tuần/tháng.
*   **Chế độ Nền tối (Dark Mode)**: Giao diện tối sang trọng, giúp bảo vệ mắt và tiết kiệm pin tối đa.

---

## 🧠 Giải Pháp Kỹ Thuật Đặc Sắc

### 🔹 Quản lý Trạng thái (Provider)
Sử dụng `NoteProvider` làm "bộ não" điều phối dữ liệu. Mọi thao tác lọc, tìm kiếm và ghim đều được xử lý tập trung, giúp ứng dụng phản hồi gần như tức thì.

### 🔹 Cơ sở dữ liệu Đám mây (Firebase)
Dữ liệu được tổ chức theo cấu trúc NoSQL hiện đại, sử dụng cơ chế lắng nghe dữ liệu trực tiếp để mọi thành viên trong nhóm đều thấy sự thay đổi ngay lập tức mà không cần tải lại trang.

### 🔹 Thiết kế Linh hoạt (Responsive Design)
Ứng dụng được tối ưu hóa để hiển thị hoàn hảo trên mọi kích thước màn hình điện thoại và máy tính bảng, đảm bảo bảng Kanban không bao giờ bị tràn lề hay méo mó.

---

## 🔄 Luồng Hoạt Động Của Người Dùng

1.  **Khởi động**: Đăng nhập hệ thống -> Màn hình chính hiện ra với các ghi chú quan trọng nhất được ưu tiên hàng đầu.
2.  **Làm việc cá nhân**: Tạo ghi chú -> Thêm danh sách việc cần làm -> Đặt nhắc nhở -> Ghim lên đầu trang.
3.  **Cộng tác**: Tạo nhóm dự án -> Mời thành viên -> Chia sẻ ghi chú chung cho cả đội.
4.  **Triển khai**: Chuyển sang bảng Kanban -> Theo dõi nhiệm vụ được giao -> Cập nhật tiến độ mỗi ngày.
5.  **Tổng kết**: Xem biểu đồ Thống kê để đánh giá hiệu quả làm việc vào cuối tuần.

---

## 📂 Cấu Trúc Thư Mục Dự Án

```text
lib/
├── controllers/      # Xử lý Logic: Quản lý ghi chú, Kết nối Firebase, Trạng thái app
├── models/           # Cấu trúc dữ liệu: Ghi chú, Việc cần làm, Thành viên, Nhóm
├── views/            # Giao diện người dùng: Màn hình chính, Nhóm, Đăng nhập
├── widgets/          # Thành phần giao diện: Bảng Kanban, Thẻ ghi chú, Thành phần chat
├── utils/            # Tiện ích bổ trợ: Xử lý file, Định dạng ngày tháng, Xử lý ảnh
└── main.dart         # Điểm khởi chạy của ứng dụng
```

---

## 🛠️ Hướng Dẫn Cài Đặt

1.  **Yêu cầu**: Cài đặt Flutter SDK, Android Studio hoặc VS Code.
2.  **Tải mã nguồn**: `git clone [Link-du-an-cua-ban]`
3.  **Cài đặt thư viện**: Chạy lệnh `flutter pub get` trong thư mục dự án.
4.  **Cấu hình Firebase**: Đưa file cấu hình `google-services.json` vào dự án của bạn.
5.  **Khởi chạy**: Chạy lệnh `flutter run` để trải nghiệm ứng dụng.

---

## 👥 Đội Ngũ Phát Triển
Dự án được tâm huyết thực hiện bởi **Nhóm Vũ** - Mang công nghệ đến gần hơn với cuộc sống.

---
*SNote - Ghi lại ý tưởng, Hoàn thành mục tiêu!*
