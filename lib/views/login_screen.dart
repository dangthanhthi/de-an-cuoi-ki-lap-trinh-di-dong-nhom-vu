import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../controllers/notification_service.dart';
import '../utils/snack_utils.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? initialMessage;

  const LoginScreen({super.key, this.initialMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _toggleThemeMode() async {
    await AppState.setLocalThemeMode(!AppState.isDarkModeActive);
  }

  @override
  void initState() {
    super.initState();
    if ((widget.initialMessage ?? '').trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showError(widget.initialMessage!);
      });
    }
  }

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    if (!RegExp(r'(?=.*[A-Z])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[a-z])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[0-9])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[!@#$%^&*(),.?":{}|<>])').hasMatch(password)) {
      return false;
    }
    return true;
  }

  void _openMainScreen() {
    if (!mounted) return;
    NotificationService.checkAndNotifyPending();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Vui lòng nhập đầy đủ email và mật khẩu!");
      return;
    }

    if (!email.endsWith('@gmail.com')) {
      _showError("Email không hợp lệ! Vui lòng sử dụng định dạng @gmail.com");
      return;
    }

    if (!_isLoginMode) {
      if (confirmPassword.isEmpty) {
        _showError("Vui lòng nhập lại mật khẩu!");
        return;
      }
      if (password != confirmPassword) {
        _showError("Mật khẩu nhập lại không khớp!");
        return;
      }
      if (!_isStrongPassword(password)) {
        _showError(
          "Mật khẩu yếu! Cần ít nhất 8 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.",
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      UserCredential userCredential;

      if (_isLoginMode) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
      }

      final user = userCredential.user;
      if (user == null) {
        throw Exception('Không lấy được thông tin người dùng sau đăng nhập');
      }

      final hydrateError = await AppState.hydrateSignedInUser(
        user,
        fallbackEmail: email,
      );
      if (hydrateError != null) {
        _showError(hydrateError);
        return;
      }

      AppState.logActivity(
        _isLoginMode ? 'Đăng nhập' : 'Đăng ký',
        'Thành công với vai trò ${AppState.currentUserRole}',
      );

      _openMainScreen();
    } on FirebaseAuthException catch (e) {
      String message = "Đã xảy ra lỗi";
      if (e.code == 'user-not-found') {
        message = "Email này chưa được đăng ký";
      } else if (e.code == 'wrong-password') {
        message = "Sai mật khẩu, vui lòng thử lại";
      } else if (e.code == 'invalid-credential') {
        message = "Tài khoản hoặc mật khẩu không chính xác";
      } else if (e.code == 'email-already-in-use') {
        message = "Email này đã được đăng ký! Vui lòng chọn Đăng nhập.";
      } else if (e.code == 'invalid-email') {
        message = "Định dạng email không hợp lệ";
      }
      _showError(message);
    } catch (e) {
      _showError("Lỗi hệ thống: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    SnackUtils.show(context, message, success: false);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isDark ? const Color(0xFF0D1117) : colorScheme.primary,
              isDark
                  ? colorScheme.surfaceContainerHigh
                  : colorScheme.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 8,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton.filledTonal(
                          tooltip: AppState.isDarkModeActive
                              ? 'Chuyển sang giao diện sáng'
                              : 'Chuyển sang giao diện tối',
                          onPressed: _toggleThemeMode,
                          icon: Icon(
                            AppState.isDarkModeActive
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.edit_document,
                          size: 60,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SNote',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isLoginMode
                            ? 'Chào mừng trở lại'
                            : 'Tạo tài khoản mới',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'ví dụ: abc@gmail.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          hintText: _isLoginMode
                              ? 'Nhập mật khẩu'
                              : 'Hoa, thường, số, ký tự đặc biệt',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Hiện mật khẩu'
                                : 'Ẩn mật khẩu',
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (!_isLoginMode) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: InputDecoration(
                            labelText: 'Nhập lại mật khẩu',
                            hintText: 'Nhập lại mật khẩu vừa tạo',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmPassword
                                  ? 'Hiện mật khẩu'
                                  : 'Ẩn mật khẩu',
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isLoginMode
                                      ? '\u0110\u0103\u006E\u0067\u0020\u006E\u0068\u1EAD\u0070'
                                      : '\u0110\u0103\u006E\u0067\u0020\u006B\u00FD',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            _emailController.clear();
                            _passwordController.clear();
                            _confirmPasswordController.clear();
                            _obscurePassword = true;
                            _obscureConfirmPassword = true;
                          });
                        },
                        child: Text(
                          _isLoginMode
                              ? "Chưa có tài khoản? \u0110\u0103\u006E\u0067\u0020\u006B\u00FD ngay"
                              : "\u0110\u00E3 có tài khoản? \u0110\u0103\u006E\u0067\u0020\u006E\u0068\u1EAD\u0070",
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}




