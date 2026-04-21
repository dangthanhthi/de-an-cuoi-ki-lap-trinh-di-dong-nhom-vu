import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'views/login_screen.dart';
import 'controllers/notification_service.dart'; // <-- THÊM DÒNG NÀY

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // <-- THÊM DÒNG NÀY ĐỂ KÍCH HOẠT BÁO THỨC -->
  await NotificationService.init();

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
      home: const LoginScreen(),
    );
  }
}