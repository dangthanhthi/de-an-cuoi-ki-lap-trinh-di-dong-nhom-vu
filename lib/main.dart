import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Bộ nổ máy Firebase
import 'firebase_options.dart'; // File chứa chìa khoá dự án của bạn
import 'views/login_screen.dart'; // Đường dẫn tới màn hình đăng nhập

void main() async {
  // 1. Yêu cầu Flutter chuẩn bị sẵn sàng các nền tảng
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. KÍCH HOẠT FIREBASE TẠI ĐÂY (Đây chính là dòng dập tắt cái lỗi kia)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // 3. Khởi chạy App
  runApp(const SNoteApp());
}

class SNoteApp extends StatelessWidget {
  const SNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const LoginScreen(), // Mở màn hình Login đầu tiên
    );
  }
}