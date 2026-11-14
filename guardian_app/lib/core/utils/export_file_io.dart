import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Schreibt [content] in eine Temp-Datei [fileName] und öffnet sie mit der
/// Standard-App (z. B. Kalender für .ics, Tabellenprogramm für .csv).
Future<void> exportTextFile(String fileName, String content) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(utf8.encode(content));
  await OpenFilex.open(file.path);
}
