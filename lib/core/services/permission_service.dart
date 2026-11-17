import 'package:flutter/services.dart';

/// Runtime permission helpers that need the platform rather than a plugin.
class PermissionService {
  PermissionService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('wings/permissions');

  final MethodChannel _channel;

  /// Asks the operating system to show the app's notification settings page,
  /// which is the only way back after a permanent denial.
  Future<bool> openNotificationSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Whether the OS currently allows this app to post notifications.
  Future<bool> notificationsEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('notificationsEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
