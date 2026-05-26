import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/appwrite_client.dart';
import '../../../core/models/app_user.dart';
import '../../../core/services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(appwriteClientProvider), ref.watch(appwriteRealtimeBroadcasterProvider));
});

class AuthNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() {
    return ref.watch(authServiceProvider).getCurrentAppUser();
  }

  Future<void> _authAction(Future<AppUser?> Function() action) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(action);
    if (state.hasError) Error.throwWithStackTrace(state.error!, state.stackTrace!);
  }

  Future<void> updateProfile(String uid, String displayName,
      {String? photoUrl}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => ref
        .read(authServiceProvider)
        .updateProfile(uid, displayName, photoUrl: photoUrl));
  }

  Future<void> signInWithGoogle() =>
      _authAction(() => ref.read(authServiceProvider).signInWithGoogle());

  Future<void> confirmMagicLink(String userId, String secret) =>
      _authAction(() => ref.read(authServiceProvider).confirmMagicLink(userId, secret));

  Future<void> linkGoogleAccount() async {
    await ref.read(authServiceProvider).linkGoogleAccount();
  }

  Future<void> signOut() async {
    await ref.read(authServiceProvider).signOut();
    state = const AsyncValue.data(null);
  }
}

final authStateProvider = AsyncNotifierProvider<AuthNotifier, AppUser?>(
  AuthNotifier.new,
);
