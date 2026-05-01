import 'dart:io';
import 'package:flutter/services.dart';

class ShareData {
  final String type; // 'text' | 'image' | 'file' | 'images' | 'files'
  final String? text;
  final List<String> uris;
  final List<String> fileNames;
  final String? mimeType;

  const ShareData({
    required this.type,
    this.text,
    required this.uris,
    required this.fileNames,
    this.mimeType,
  });

  bool get isText => type == 'text';
  bool get isImage => type == 'image' || type == 'images';
  bool get isMultiple => type == 'images' || type == 'files';
}

class ShareService {
  static const _channel = MethodChannel('com.guardianapp.guardian_app/share');

  Future<ShareData?> getSharedData() async {
    if (!Platform.isAndroid) return null;
    try {
      final data = await _channel.invokeMethod<Map<Object?, Object?>>('getSharedData');
      if (data == null) return null;
      return ShareData(
        type: data['type'] as String,
        text: data['text'] as String?,
        uris: List<String>.from(data['uris'] as List),
        fileNames: List<String>.from(data['fileNames'] as List),
        mimeType: data['mimeType'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> readUri(String uri) async {
    if (!Platform.isAndroid) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readUri', {'uri': uri});
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
