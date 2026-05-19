import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';

import '../controllers/app_permission_service.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    // Yêu cầu quyền ngay khi vào app lần đầu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppPermissionService.requestStartupPermissions();
    });
  }

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Chào mừng đến với SNote',
      'desc':
          'Giải pháp ghi chú thông minh, giúp bạn quản lý ý tưởng và công việc một cách chuyên nghiệp.',
      'icon': Icons.note_alt_rounded,
      'color': Colors.indigo,
    },
    {
      'title': 'Phân công & Đính kèm',
      'desc':
          'Giao việc cho thành viên, đính kèm hình ảnh và tệp tin riêng cho từng công việc cụ thể trong nhóm.',
      'icon': Icons.assignment_turned_in_rounded,
      'color': Colors.deepOrange,
    },
    {
      'title': 'Cộng tác Nhóm',
      'desc':
          'Làm việc cùng đồng nghiệp, chia sẻ ghi chú và quản lý công việc nhóm thời gian thực.',
      'icon': Icons.groups_rounded,
      'color': Colors.teal,
    },
    {
      'title': 'Trợ lý AI Thông minh',
      'desc':
          'Chuyển giọng nói thành văn bản, tự động tạo danh sách công việc và nhận gợi ý thông minh từ AI.',
      'icon': Icons.psychology_rounded,
      'color': Colors.amber.shade800,
    },
    {
      'title': 'Bảo mật & Đồng bộ',
      'desc':
          'Dữ liệu của bạn luôn được an toàn trên đám mây và đồng bộ tức thì trên mọi thiết bị.',
      'icon': Icons.cloud_done_rounded,
      'color': Colors.blue,
    },
  ];

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: _slides.length,
            itemBuilder: (context, index) {
              final slide = _slides[index];
              return SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: slide['color'].withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          slide['icon'],
                          size: 100,
                          color: slide['color'],
                        ),
                      ),
                      const SizedBox(height: 48),
                      Text(
                        slide['title'],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: slide['color'],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        slide['desc'],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _slides.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 8,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? _slides[_currentPage]['color']
                            : colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _slides[_currentPage]['color'],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isLastPage
                          ? _finishOnboarding
                          : () {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                      child: Text(
                        isLastPage ? 'Bắt đầu ngay' : 'Tiếp theo',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label: 'start_button',
                  button: true,
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    child: Text(
                      'Bỏ qua',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




