import 'package:appwrite/appwrite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const appwriteEndpoint = 'https://appwrite.guardian-com.de/v1';
const appwriteProjectId = '6a02e4160023948ef257';
const appwriteMediaBucketId = '6a02e524000954c9f1de';

final appwriteClientProvider = Provider<Client>((ref) {
  return Client()
      .setEndpoint(appwriteEndpoint)
      .setProject(appwriteProjectId);
});

final appwriteRealtimeProvider = Provider<Realtime>((ref) {
  return Realtime(ref.watch(appwriteClientProvider));
});

final appwriteStorageProvider = Provider<Storage>((ref) {
  return Storage(ref.watch(appwriteClientProvider));
});
