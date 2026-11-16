import 'package:flutter/services.dart';

/// Bridge to the platform's MediaStore so finished downloads are visible in the
/// device's Downloads folder and can be opened by any external player.
class StorageService {
  StorageService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('wings/storage');

  final MethodChannel _channel;

  Future<String?> saveToDownloads({
    required String path,
    required String fileName,
  }) async {
    try {
      return await _channel.invokeMethod<String>(
        'saveToDownloads',
        <String, String>{'path': path, 'fileName': fileName},
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> openFile(String uri) async {
    try {
      return await _channel.invokeMethod<bool>('openFile', <String, String>{
            'uri': uri,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
