import 'package:flutter/services.dart';

class PdfAndroidRenderer {
  static const _channel = MethodChannel('meowo/pdf');

  static Future<List<Map<String, dynamic>>> render({
    required String path,
    required String outputDir,
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>('render', {
      'path': path,
      'outputDir': outputDir,
    });
    return [
      for (final item in result ?? const [])
        Map<String, dynamic>.from(item as Map),
    ];
  }
}
