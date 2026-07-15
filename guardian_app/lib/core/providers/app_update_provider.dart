import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appwrite_client.dart';
import '../services/app_update_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService(ref.watch(appwriteClientProvider));
});

/// Lädt beim App-Start den Update-Status. Wird vom Router-Gate (erforderlich)
/// und vom Empfohlen-Hinweis in main.dart ausgewertet.
final appUpdateStatusProvider = FutureProvider<AppUpdateStatus>((ref) async {
  return ref.watch(appUpdateServiceProvider).check();
});
