import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint('https://appwrite.guardian-com.de/v1')
      .setProject('6a02e4160023948ef257');
});

final appwriteRealtimeProvider = Provider<Realtime>((ref) {
  return Realtime(ref.watch(appwriteClientProvider));
});

final appwriteStorageProvider = Provider<Storage>((ref) {
  return Storage(ref.watch(appwriteClientProvider));
});
