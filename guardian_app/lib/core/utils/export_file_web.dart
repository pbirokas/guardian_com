import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Web: löst einen Browser-Download von [fileName] aus.
Future<void> exportTextFile(String fileName, String content) async {
  await FilePicker.saveFile(
    fileName: fileName,
    bytes: Uint8List.fromList(utf8.encode(content)),
  );
}
