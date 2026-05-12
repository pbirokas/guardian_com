import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/appwrite_client.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(appwriteClientProvider));
});

class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() {
    return ref.watch(authServiceProvider).getCurrentAppUser();
  }

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(authServiceProvider).signIn(email, password));
  }

  Future<void> register(String email, String password, String name) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(authServiceProvider).register(email, password, name));
  }

  Future<void> updateProfile(String uid, String displayName,
      {String? photoUrl}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref
        .read(authServiceProvider)
        .updateProfile(uid, displayName, photoUrl: photoUrl));
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    state = const AsyncValue.data(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
