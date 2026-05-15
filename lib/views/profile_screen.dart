import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/app_state.dart';
import '../utils/media_utils.dart';
import 'activity_history_screen.dart';
import 'admin_manage_users_screen.dart';
import 'app_settings_screen.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUpdatingAvatar = false;

  void _showMessage(String message, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<bool> _requestGalleryPermission() async {
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      return status.isGranted || status.isLimited;
    }
    // Android 13+ (SDK 33+)
    if (await Permission.photos.status.isGranted) return true;
    final result = await Permission.photos.request();
    if (result.isGranted) return true;
    // Fallback Android < 13
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Xem ảnh đại diện'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showFullAvatar(AppState.currentUserAvatar, AppState.currentUserName);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Chụp ảnh mới'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(ImageSource source) async {
    if (_isUpdatingAvatar) return;

    if (source == ImageSource.camera) {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showMessage('Bạn cần cấp quyền camera để chụp ảnh.', success: false);
        return;
      }
    } else {
      if (!await _requestGalleryPermission()) {
        _showMessage('Bạn cần cấp quyền truy cập ảnh.', success: false);
        return;
      }
    }

    String? newAvatarUrl;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 30,
        maxWidth: 400,
      );
      if (image == null) return;

      final file = File(image.path);
      
      // Kiểm tra dung lượng file
      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        _showMessage('Ảnh quá lớn (>5MB). Vui lòng chọn ảnh khác.', success: false);
        return;
      }

      setState(() => _isUpdatingAvatar = true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeEmail = sanitizeFileName(AppState.currentUserEmail.replaceAll('@', '_at_'));
      final fileName = "avatar_${safeEmail}_$timestamp.jpg";
      
      newAvatarUrl = await FirebaseService.uploadUserAvatar(file, fileName);

      final oldAvatar = AppState.currentUserAvatar;
      await FirebaseService.updateUserProfile(avatar: newAvatarUrl);
      
      // Cập nhật AppState ngay lập tức để đồng bộ UI toàn app
      AppState.currentUserAvatar = newAvatarUrl;
      AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi ảnh đại diện');
      
      // Xóa ảnh cũ sau cùng (best-effort)
      if (oldAvatar.isNotEmpty) {
        FirebaseService.deleteAttachment(oldAvatar);
      }

      if (!mounted) return;
      _showMessage('Đã cập nhật ảnh đại diện!');
    } on FirebaseException catch (e) {
      // Rollback: Xóa ảnh mới vừa up nếu lưu profile thất bại
      if (newAvatarUrl != null) FirebaseService.deleteAttachment(newAvatarUrl);
      if (!mounted) return;
      _showMessage('Lỗi Firebase (${e.code}): ${e.message}', success: false);
    } catch (e) {
      if (newAvatarUrl != null) FirebaseService.deleteAttachment(newAvatarUrl);
      if (!mounted) return;
      _showMessage('Lỗi tải ảnh: $e', success: false);
    } finally {
      if (mounted) setState(() => _isUpdatingAvatar = false);
    }
  }

  Future<void> _editProfile(String currentName, String currentEmail) async {
    final nameController = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (isSaving || formKey.currentState?.validate() != true) return;
              setSheetState(() => isSaving = true);
              final saved = await _saveProfileName(nameController.text);
              if (!sheetContext.mounted) return;
              setSheetState(() => isSaving = false);
              if (saved && Navigator.of(sheetContext).canPop()) {
                Navigator.of(sheetContext).pop();
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chỉnh sửa thông tin',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        autofocus: true,
                        enabled: !isSaving,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Họ tên',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Họ tên không được để trống';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: currentEmail,
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSaving ? null : submit,
                          child: Text(
                            isSaving ? 'Đang lưu...' : 'Lưu thay đổi',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _saveProfileName(String name) async {
    try {
      await FirebaseService.updateUserProfile(name: name);
      AppState.logActivity('Cập nhật hồ sơ', 'Đã thay đổi thông tin cá nhân');
      if (!mounted) return false;
      _showMessage('Đã cập nhật thông tin!');
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showMessage('Lỗi cập nhật thông tin: $e', success: false);
      return false;
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final navigator = Navigator.of(context);

    await FirebaseService.goOffline();
    AppState.clearAllData();
    await FirebaseAuth.instance.signOut();

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseService.getUserProfileStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final name = (userData?['name'] ?? AppState.currentUserName).toString();
        final avatar = (userData?['avatar'] ?? AppState.currentUserAvatar)
            .toString();
        final role = (userData?['role'] ?? AppState.currentUserRole).toString();
        final email = AppState.currentUserEmail;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            AppState.currentUserName = name;
            AppState.currentUserAvatar = avatar;
            AppState.currentUserRole = role;
          }
        });
        final settings = userData?['settings'] is Map<String, dynamic>
            ? userData!['settings'] as Map<String, dynamic>
            : null;
        if (settings != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) AppState.applyUserSettings(settings);
          });
        }

        final isAdmin = role == 'Admin';
        final colorScheme = Theme.of(context).colorScheme;
        final mutedText = colorScheme.onSurfaceVariant;

        final bottomSpacing = MediaQuery.of(context).padding.bottom + 104;

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Hồ sơ cá nhân',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomSpacing),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _isUpdatingAvatar ? null : _showAvatarPicker,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: colorScheme.primaryContainer,
                              backgroundImage: avatar.toString().isNotEmpty
                                  ? avatarImageProvider(avatar, name: name)
                                  : null,
                              child: _isUpdatingAvatar
                                  ? const CircularProgressIndicator()
                                  : null,
                            ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                shape: BoxShape.circle,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.camera_alt_outlined,
                                size: 18,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: mutedText),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isAdmin
                              ? colorScheme.errorContainer
                              : colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isAdmin
                                ? colorScheme.error.withValues(alpha: 0.24)
                                : colorScheme.primary.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Text(
                          'Vai trò: $role',
                          style: TextStyle(
                            color: isAdmin
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Quản lý thông tin cá nhân, cài đặt và các thao tác quản trị từ một nơi gọn hơn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: mutedText, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: _menuIcon(
                          Icons.person_outline,
                          colorScheme.primary,
                          colorScheme.primaryContainer,
                        ),
                        title: const Text(
                          'Chỉnh sửa thông tin',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Đổi tên và cập nhật ảnh đại diện',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _editProfile(name, email),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: _menuIcon(
                          Icons.history,
                          colorScheme.secondary,
                          colorScheme.secondaryContainer,
                        ),
                        title: const Text(
                          'Lịch sử hoạt động',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text('Xem lại các thay đổi gần đây'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ActivityHistoryScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: _menuIcon(
                          Icons.settings_outlined,
                          colorScheme.primary,
                          colorScheme.primaryContainer,
                        ),
                        title: const Text(
                          'Cài đặt ứng dụng',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Thông báo, giao diện và các tùy chọn hệ thống',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AppSettingsScreen(),
                            ),
                          );
                        },
                      ),
                      if (isAdmin) ...[
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          leading: _menuIcon(
                            Icons.admin_panel_settings,
                            colorScheme.error,
                            colorScheme.errorContainer,
                          ),
                          title: const Text(
                            'Quản lý người dùng',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: const Text(
                            'Xem chi tiết tài khoản và quyền trong hệ thống',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const AdminManageUsersScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: _menuIcon(
                          Icons.alternate_email,
                          mutedText,
                          colorScheme.surfaceContainerHighest,
                        ),
                        title: const Text(
                          'Tài khoản đăng nhập',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: _menuIcon(
                          Icons.logout,
                          colorScheme.error,
                          colorScheme.errorContainer,
                        ),
                        title: Text(
                          'Đăng xuất',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text('Thoát tài khoản hiện tại'),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: colorScheme.error,
                        ),
                        onTap: () => _handleLogout(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuIcon(IconData icon, Color iconColor, Color backgroundColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? iconColor.withValues(alpha: 0.16) : backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: iconColor),
    );
  }

  void _showFullAvatar(String url, String name) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image(
                  image: avatarImageProvider(url, name: name),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}




