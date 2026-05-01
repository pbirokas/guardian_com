import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/share_service.dart';

final shareServiceProvider = Provider<ShareService>((ref) => ShareService());

final pendingShareProvider = NotifierProvider<PendingShareNotifier, ShareData?>(() {
  return PendingShareNotifier();
});

class PendingShareNotifier extends Notifier<ShareData?> {
  @override
  ShareData? build() => null;

  void set(ShareData data) => state = data;
  void clear() => state = null;
}
