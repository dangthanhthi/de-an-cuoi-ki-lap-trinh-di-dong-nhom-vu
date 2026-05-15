import 'package:permission_handler/permission_handler.dart';

class AppPermissionService {
  static Future<void> requestStartupPermissions() async {
    await _requestIfNeeded(Permission.notification);
    await _requestIfNeeded(Permission.camera);
    await _requestIfNeeded(Permission.microphone);
    await _requestIfNeeded(Permission.photos);
  }

  static Future<void> _requestIfNeeded(Permission permission) async {
    final status = await permission.status;
    if (status.isDenied || status.isRestricted || status.isLimited) {
      await permission.request();
    }
  }
}


