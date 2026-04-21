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

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    if (!RegExp(r'(?=.*[A-Z])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[a-z])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[0-9])').hasMatch(password)) return false;
    if (!RegExp(r'(?=.*[!@#$%^&*(),.?":{}|<>])').hasMatch(password)) return false;
    return true;
  }

  void _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showError("Vui long nhap day du email va mat khau!");
      return;
    }

    if (!email.endsWith('@gmail.com')) {
      _showError("Email khong hop le! Vui long su dung dinh dang @gmail.com");
      return;
    }

    if (!_isLoginMode) {
      if (_selectedRole == 'Admin') {
        _showError("Khong the tao tai khoan voi quyen Admin!");
        return;
      }
      if (!_isStrongPassword(password)) {
        _showError("Mat khau yeu! Can it nhat 8 ky tu, gom chu hoa, chu thuong, so va ky tu dac biet.");
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

          bool isBanned = data['isBanned'] ?? false;
          if (isBanned) {
            await FirebaseAuth.instance.signOut();
            _showError("Tai khoan nay da bi khoa do vi pham chinh sach! Vui long lien he Admin.");
            setState(() => _isLoading = false);
            return;
          }

          final actualRole = data['role'] ?? "User";

          if (_isLoginMode && actualRole != _selectedRole) {
            await FirebaseAuth.instance.signOut();
            _showError("Loi truy cap: Tai khoan cua ban la $actualRole, khong the dang nhap bang quyen $_selectedRole!");
            setState(() => _isLoading = false);
            return;
          }

          AppState.currentUserName = data['name'] ?? "User";
          AppState.currentUserAvatar = data['avatar'] ?? "https://ui-avatars.com/api/?background=random";
          AppState.currentUserRole = actualRole;
        } else {
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

      AppState.logActivity(_isLoginMode ? 'Dang nhap' : 'Dang ky', 'Thanh cong voi vai tro ${AppState.currentUserRole}');

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } on FirebaseAuthException catch (e) {
      String message = "Da xay ra loi";
      if (e.code == 'user-not-found') {
        message = "Email nay chua duoc dang ky";
      } else if (e.code == 'wrong-password') {
        message = "Sai mat khau, vui long thu lai";
      } else if (e.code == 'invalid-credential') {
        message = "Tai khoan hoac mat khau khong chinh xac";
      } else if (e.code == 'email-already-in-use') {
        message = "Email nay da duoc dang ky! Vui long chon Dang nhap.";
      } else if (e.code == 'invalid-email') {
        message = "Dinh dang email khong hop le";
      }
      _showError(message);
    } catch (e) {
      _showError("Loi he thong: $e");
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
                      Text(_isLoginMode ? 'Chao mung tro lai' : 'Tao tai khoan moi', style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 32),

                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'vi du: abc@gmail.com',
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
                          labelText: 'Mat khau',
                          hintText: _isLoginMode ? 'Nhap mat khau' : 'Hoa, thuong, so, ky tu d.biet',
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
                          labelText: 'Vai tro',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                        items: (_isLoginMode ? ['Admin', 'User'] : ['User']).map((role) => DropdownMenuItem(value: role, child: Text(role))).toList(),
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
                              : Text(_isLoginMode ? 'Dang nhap' : 'Dang ky', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isLoginMode = !_isLoginMode;
                            _emailController.clear();
                            _passwordController.clear();
                            if (!_isLoginMode) _selectedRole = 'User';
                          });
                        },
                        child: Text(_isLoginMode ? "Chua co tai khoan? Dang ky ngay" : "Da co tai khoan? Dang nhap"),
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