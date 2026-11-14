import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chat_service.dart';

/// Share-Target gibt es nur in der Android-App (Intent-Filter), nicht im Web.
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    if (!_isAndroid) return null;
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
    if (!_isAndroid) return null;
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('readUri', {'uri': uri});
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Sendet geteilte Inhalte in den Chat [convId]. Bilder gehen gebündelt als
  /// eine Nachricht raus (eine Benachrichtigung). Gelesen wird blockweise,
  /// damit nie mehr als [ChatService.maxImagesPerMessage] Originalbilder
  /// gleichzeitig im Speicher liegen.
  Future<void> sendTo(ChatService chat, String convId, ShareData data) async {
    if (data.isText) {
      await chat.sendMessage(convId, data.text!);
      return;
    }
    var images = <Uint8List>[];
    for (var i = 0; i < data.uris.length; i++) {
      final bytes = await readUri(data.uris[i]);
      if (bytes == null) continue;
      if (!data.isImage) {
        final fileName = data.fileNames.length > i ? data.fileNames[i] : 'file';
        await chat.sendFile(convId, bytes, fileName, bytes.length);
        continue;
      }
      images.add(bytes);
      if (images.length == ChatService.maxImagesPerMessage) {
        await chat.sendImages(convId, images);
        images = <Uint8List>[];
      }
    }
    await chat.sendImages(convId, images);
  }
}
