import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../controllers/app_state.dart';
import '../utils/snack_utils.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  PermissionStatus? _notificationStatus;
  PermissionStatus? _cameraStatus;
  PermissionStatus? _microphoneStatus;
  PermissionStatus? _storageStatus;
  bool _isSavingSettings = false;
  late Stream<QuerySnapshot> _mutesStream;
  late Stream<QuerySnapshot> _blocksStream;

  @override
  void initState() {
    super.initState();
    _mutesStream = FirebaseService.getMyMutesStream();
    _blocksStream = FirebaseService.getMyBlocksStream();
    _loadStatuses();
  }

  Future<void> _loadStatuses() async {
    final notification = await Permission.notification.status;
    final camera = await Permission.camera.status;
    final microphone = await Permission.microphone.status;
    
    // Kiểm tra tổ hợp quyền tệp/ảnh
    PermissionStatus storage = await Permission.photos.status;
    if (!storage.isGranted) {
      final legacyStorage = await Permission.storage.status;
      if (legacyStorage.isGranted) storage = legacyStorage;
    }

    if (!mounted) return;
    setState(() {
      _notificationStatus = notification;
      _cameraStatus = camera;
      _microphoneStatus = microphone;
      _storageStatus = storage;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    PermissionStatus status;
    if (permission == Permission.photos) {
      // Thử xin quyền ảnh trước (Android 13+)
      status = await Permission.photos.request();
      if (!status.isGranted) {
        // Nếu không được, thử xin quyền storage cũ
        status = await Permission.storage.request();
      }
    } else {
      status = await permission.request();
    }

    if (!mounted) return;
    await _loadStatuses();
    if (!mounted) return;
    if (status.isPermanentlyDenied) {
      SnackUtils.show(
        context,
        'Bạn cần bật quyền này trong cài đặt hệ thống.',
        success: false,
        actionLabel: 'Mở',
        onActionPressed: openAppSettings,
      );
    }
  }

  String _label(PermissionStatus? status) {
    if (status == null) return 'Đang kiểm tra';
    if (status.isGranted) return 'Đã cấp quyền';
    if (status.isPermanentlyDenied) return 'Bị từ chối vĩnh viễn';
    if (status.isDenied) return 'Chưa cấp quyền';
    return 'Cần kiểm tra lại';
  }

  Color _statusColor(BuildContext context, PermissionStatus? status) {
    final colorScheme = Theme.of(context).colorScheme;
    if (status?.isGranted == true) return colorScheme.primary;
    if (status?.isPermanentlyDenied == true) return colorScheme.error;
    // Dùng màu xám trung tính cho trạng thái chưa cấp quyền để đỡ "lạc loài"
    return colorScheme.outline;
  }

  Future<void> _saveSettings({
    bool? darkMode,
    bool? notificationsEnabled,
  }) async {
    if (_isSavingSettings) return;
    setState(() => _isSavingSettings = true);
    final saved = await FirebaseService.updateUserSettings(
      darkMode: darkMode,
      notificationsEnabled: notificationsEnabled,
    );
    if (!mounted) return;
    setState(() => _isSavingSettings = false);
    if (saved == 'SUCCESS') {
      await _loadStatuses();
      return;
    }
    SnackUtils.show(context, 'Không thể lưu cài đặt. Vui lòng thử lại.', success: false);
  }

  bool _isMuteActive(Map<String, dynamic> data) {
    final muteUntil = data['muteUntil'];
    if (muteUntil is! Timestamp) return true;
    return muteUntil.toDate().isAfter(DateTime.now());
  }

  String _formatMuteSubtitle(Map<String, dynamic> data) {
    final base = data['type'] == 'group' ? 'Nhóm' : 'Người dùng';
    final muteUntil = data['muteUntil'];
    if (muteUntil is! Timestamp) return '$base • Tắt cho đến khi mở lại';
    final date = muteUntil.toDate();
    final formatted =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '$base • Tắt đến $formatted';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 28;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt ứng dụng')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: colorScheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Điều chỉnh SNote',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Giao diện, thông báo và quyền thiết bị được gom lại ở đây để bạn kiểm soát nhanh, gọn và dễ hiểu hơn.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Giao diện & thông báo',
              subtitle: 'Các tùy chọn bạn dùng thường xuyên nhất.',
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppState.themeModeNotifier,
                  builder: (context, themeMode, child) {
                    return _SettingsActionTile(
                      icon: Icons.dark_mode_outlined,
                      color: colorScheme.primary,
                      title: 'Giao diện tối',
                      subtitle: 'Chuyển nhanh giữa chế độ sáng và tối',
                      trailing: Switch(
                        value: AppState.isDarkModeActive,
                        onChanged: _isSavingSettings
                            ? null
                            : (value) => _saveSettings(darkMode: value),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: AppState.notificationsEnabledNotifier,
                  builder: (context, enabled, _) {
                    return _SettingsActionTile(
                      icon: Icons.notifications_outlined,
                      color: colorScheme.secondary,
                      title: 'Thông báo trong app',
                      subtitle: 'Bật hoặc tắt thông báo tự động của SNote',
                      trailing: Switch(
                        value: enabled,
                        onChanged: _isSavingSettings
                            ? null
                            : (value) =>
                                  _saveSettings(notificationsEnabled: value),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsSection(
              title: 'Quyền thiết bị',
              subtitle:
                  'Kiểm tra nhanh quyền cần cho camera, micro và nhắc việc.',
              children: [
                _SettingsActionTile(
                  icon: Icons.notifications_active_outlined,
                  color: _statusColor(context, _notificationStatus),
                  title: 'Thông báo nhắc nhở',
                  subtitle: _label(_notificationStatus),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _requestPermission(Permission.notification),
                ),
                _SettingsActionTile(
                  icon: Icons.camera_alt_outlined,
                  color: _statusColor(context, _cameraStatus),
                  title: 'Camera',
                  subtitle: _label(_cameraStatus),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _requestPermission(Permission.camera),
                ),
                _SettingsActionTile(
                  icon: Icons.mic_none_outlined,
                  color: _statusColor(context, _microphoneStatus),
                  title: 'Micro nhập giọng nói',
                  subtitle: _label(_microphoneStatus),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _requestPermission(Permission.microphone),
                ),
                _SettingsActionTile(
                  icon: Icons.folder_open_outlined,
                  color: _statusColor(context, _storageStatus),
                  title: 'Tệp và nội dung nghe nhìn',
                  subtitle: _label(_storageStatus),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _requestPermission(Permission.photos),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loadStatuses,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Kiểm tra lại'),
                    ),
                    FilledButton.icon(
                      onPressed: openAppSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Mở cài đặt hệ thống'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: _mutesStream,
              builder: (context, snapshot) {
                final activeDocs = (snapshot.data?.docs ?? []).where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return _isMuteActive(data);
                }).toList();

                return _SettingsSection(
                  title: 'Đang tắt thông báo',
                  subtitle: 'Những người hoặc nhóm đang được tạm ẩn thông báo.',
                  children: activeDocs.isEmpty
                      ? const [
                          _EmptyStateTile(
                            icon: Icons.notifications_active_outlined,
                            title: 'Không có mục nào đang bị tắt thông báo',
                          ),
                        ]
                      : activeDocs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return _SettingsActionTile(
                            icon: data['type'] == 'group'
                                ? Icons.groups_outlined
                                : Icons.person_outline,
                            color: colorScheme.primary,
                            title: (data['label'] ?? data['targetId'] ?? '')
                                .toString(),
                            subtitle: _formatMuteSubtitle(data),
                            trailing: IconButton(
                              tooltip: 'Mở lại thông báo',
                              icon: const Icon(Icons.volume_up_outlined),
                              onPressed: () => FirebaseService.unmuteTarget(
                                type: data['type'].toString(),
                                targetId: data['targetId'].toString(),
                              ),
                            ),
                          );
                        }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: _blocksStream,
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                return _SettingsSection(
                  title: 'Danh sách chặn',
                  subtitle: 'Bạn có thể bỏ chặn người dùng bất cứ lúc nào.',
                  children: docs.isEmpty
                      ? const [
                          _EmptyStateTile(
                            icon: Icons.block_outlined,
                            title: 'Bạn chưa chặn ai',
                          ),
                        ]
                      : docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final email = (data['targetEmail'] ?? '').toString();
                          return _SettingsActionTile(
                            icon: Icons.block,
                            color: colorScheme.error,
                            title: email,
                            subtitle: 'Người dùng đã bị chặn',
                            trailing: IconButton(
                              tooltip: 'Bỏ chặn',
                              icon: const Icon(Icons.lock_open_outlined),
                              onPressed: () =>
                                  FirebaseService.unblockUser(email),
                            ),
                          );
                        }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ..._withDividers(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context) {
    final widgets = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      widgets.add(children[index]);
      if (index != children.length - 1) {
        widgets.add(const Divider(height: 1));
      }
    }
    return widgets;
  }
}

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 16,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _EmptyStateTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _EmptyStateTile({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}




