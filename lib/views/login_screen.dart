import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../controllers/app_state.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _selectedRole = 'User';
  bool _isLoading = false;
  bool _isLoginMode = true; 

  // --- HÀM KIỂM TRA ĐỊNH DẠNG MẬT KHẨU TIÊU CHUẨN ---
  bool _isStrongPassword(String password) {
    if (password.length < 8) return false; 
    if (!RegExp(r'(?=.*[A-Z])').hasMatch(password)) return false; 
    if (!RegExp(r'(?=.*[a-z])').hasMatch(password)) return false; 
    if (!RegExp(r'(?=.*[0-9])').hasMatch(password)) return false; 
    if (!RegExp(r'(?=.*[!@#$%^&*(),.?":{}|<>])').hasMatch(password)) return false; 
    return true;
  }

  void _submit() async {
    // Ép email về chữ thường tuyệt đối để không bị lỗi đồng bộ với Firebase
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Vui lòng nhập đầy đủ email và mật khẩu!");
      return;
    }

    if (!email.endsWith('@gmail.com')) {
      _showError("Email không hợp lệ! Vui lòng sử dụng định dạng @gmail.com");
      return;
    }

    if (!_isLoginMode) {
      if (!_isStrongPassword(password)) {
        _showError("Mật khẩu yếu! Cần ít nhất 8 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.");
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
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = userCredential.user;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          final data = userDoc.data()!;
          
          // --- KIỂM TRA XEM TÀI KHOẢN CÓ BỊ KHÓA KHÔNG ---
          bool isBanned = data['isBanned'] ?? false;
          if (isBanned) {
            await FirebaseAuth.instance.signOut();
            _showError("Tài khoản này đã bị khóa do vi phạm chính sách! Vui lòng liên hệ Admin.");
            setState(() => _isLoading = false);
            return; 
          }

          final actualRole = data['role'] ?? "User";

          // --- KIỂM TRA QUYỀN LÚC ĐĂNG NHẬP ---
          if (_isLoginMode && actualRole != _selectedRole) {
            await FirebaseAuth.instance.signOut();
            _showError("Lỗi truy cập: Tài khoản của bạn là $actualRole, không thể đăng nhập bằng quyền $_selectedRole!");
            setState(() => _isLoading = false);
            return; 
          }

          AppState.currentUserName = data['name'] ?? "User";
          AppState.currentUserAvatar = data['avatar'] ?? "https://ui-avatars.com/api/?name=User&background=random";
          AppState.currentUserRole = actualRole;
        } else {
          // Khởi tạo cho người dùng mới đăng ký
          AppState.currentUserName = user.email?.split('@')[0] ?? "User";
          AppState.currentUserRole = _selectedRole;
          AppState.currentUserAvatar = user.photoURL ?? "https://ui-avatars.com/api/?name=${AppState.currentUserName}&background=random";

          await FirebaseService.updateUserProfile(
            name: AppState.currentUserName,
            role: AppState.currentUserRole,
            avatar: AppState.currentUserAvatar,
          );
        }
        AppState.currentUserEmail = user.email ?? email;
      }

      AppState.logActivity(_isLoginMode ? 'Đăng nhập' : 'Đăng ký', 'Thành công với vai trò ${AppState.currentUserRole}');

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating, 
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.indigo.shade800, Colors.purple.shade500],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                        child: const Icon(Icons.edit_document, size: 60, color: Colors.indigo),
                      ),
                      const SizedBox(height: 16),
                      const Text('SNote', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.indigo)),
                      const SizedBox(height: 8),
                      Text(_isLoginMode ? 'Chào mừng trở lại' : 'Tạo tài khoản mới', style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 32),
                      
                      TextField(
                        controller: _emailController, 
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'ví dụ: abc@gmail.com',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      TextField(
                        controller: _passwordController, 
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Mật khẩu',
                          hintText: _isLoginMode ? 'Nhập mật khẩu' : 'Hoa, thường, số, ký tự đ.biệt',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: InputDecoration(
                          labelText: 'Vai trò',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        items: ['Admin', 'User'].map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
                        onChanged: (val) => setState(() => _selectedRole = val!),
                      ),
                      const SizedBox(height: 24),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _submit,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isLoading
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : Text(_isLoginMode ? 'Đăng nhập' : 'Đăng ký', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            _emailController.clear();
                            _passwordController.clear();
                          });
                        },
                        child: Text(_isLoginMode ? "Chưa có tài khoản? Đăng ký ngay" : "Đã có tài khoản? Đăng nhập"),
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