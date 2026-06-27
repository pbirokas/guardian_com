import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:guardian_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/locale_provider.dart';
import '../../../core/providers/scale_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../core/widgets/help_sheet.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../core/providers/chat_font_size_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _saving = false;
  bool _pickingImage = false;
  bool _linkingGoogle = false;
  bool? _googleLinked;
  Uint8List? _pickedImageBytes;

  @override
  void initState() {
    super.initState();
    final displayName = ref.read(authStateProvider).value?.displayName ?? '';
    _nameController = TextEditingController(text: displayName);
    _loadIdentities();
  }

  Future<void> _loadIdentities() async {
    final linked = await ref.read(authServiceProvider).isGoogleLinked();
    if (mounted) setState(() => _googleLinked = linked);
  }

  Future<void> _linkGoogle() async {
    setState(() => _linkingGoogle = true);
    try {
      await ref.read(authStateProvider.notifier).linkGoogleAccount();
      if (mounted) {
        final l = AppLocalizations.of(context);
        setState(() => _googleLinked = true);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l.googleLinked)));
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _linkingGoogle = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        final bytes = await picked.readAsBytes();
        setState(() => _pickedImageBytes = bytes);
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final uid = ref.read(authStateProvider).value!.uid;
      String? photoUrl;
      if (_pickedImageBytes != null) {
        photoUrl = await ref
            .read(authServiceProvider)
            .uploadProfileImage(uid, _pickedImageBytes!);
      }
      await ref
          .read(authStateProvider.notifier)
          .updateProfile(uid, name, photoUrl: photoUrl);

      if (mounted) {
        setState(() => _pickedImageBytes = null);
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.profileSaved)),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l.errorMessage(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appUser = ref.watch(authStateProvider).value;

    final initials = ((appUser?.displayName.isNotEmpty == true
                ? appUser!.displayName
                : appUser?.email ?? '?')[0])
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(l.editProfile),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l.helpLabel,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => HelpSheet(
                screenTitle: l.helpProfileTitle,
                topics: [
                  HelpTopic(
                    icon: Icons.camera_alt_outlined,
                    title: l.helpProfilePhotoTitle,
                    body: l.helpProfilePhotoBody,
                  ),
                  HelpTopic(
                    icon: Icons.badge_outlined,
                    title: l.helpProfileNameTitle,
                    body: l.helpProfileNameBody,
                  ),
                  HelpTopic(
                    icon: Icons.palette_outlined,
                    title: l.helpProfileAppearanceTitle,
                    body: l.helpProfileAppearanceBody,
                  ),
                  HelpTopic(
                    icon: Icons.family_restroom_outlined,
                    title: l.helpProfileRelTitle,
                    body: l.helpProfileRelBody,
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: GestureDetector(
              onTap: _saving ? null : _pickImage,
              child: Stack(
                children: [
                  UserAvatar(
                    radius: 48,
                    photoUrl: appUser?.photoUrl,
                    overrideImage: _pickedImageBytes != null
                        ? MemoryImage(_pickedImageBytes!)
                        : null,
                    fallbackText: initials,
                    textStyle: const TextStyle(fontSize: 36),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_pickedImageBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Text(l.newImageSelected,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              appUser?.email ?? '',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l.displayName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _ThemeSetting(
            current: ref.watch(themeModeProvider),
            onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
          ),
          const SizedBox(height: 16),
          _LanguageSetting(
            current: ref.watch(localeProvider).value ?? const Locale('de'),
            onChanged: (locale) =>
                ref.read(localeProvider.notifier).setLocale(locale),
          ),
          const SizedBox(height: 16),
          _ChatFontSizeSetting(
            current: ref.watch(chatFontSizeProvider),
            onChanged: (size) =>
                ref.read(chatFontSizeProvider.notifier).set(size),
          ),
          if (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux) ...[
            const SizedBox(height: 16),
            _ScaleSetting(
              current: ref.watch(scaleFactorProvider),
              onChanged: (v) => ref.read(scaleFactorProvider.notifier).set(v),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_outline),
            title: Text(l.myRelationships),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/relationships'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l.privacyTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/privacy'),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(l.connectedAccounts,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: _googleLinked == true || _linkingGoogle ? null : _linkGoogle,
            leading: const Text('G',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
            title: const Text('Google'),
            subtitle: _googleLinked == null
                ? null
                : Text(_googleLinked! ? l.googleLinkedStatus : l.googleNotLinked,
                    style: TextStyle(
                        color: _googleLinked!
                            ? Colors.green
                            : Theme.of(context).colorScheme.outline)),
            trailing: _googleLinked == true
                ? const Icon(Icons.check_circle, color: Colors.green)
                : _linkingGoogle
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_link),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(l.signOut,
                style: const TextStyle(color: Colors.red)),
            onTap: () => ref.read(authStateProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _ThemeSetting extends StatelessWidget {
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSetting({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l.appearance,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(l.themeSystem),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(l.themeLight),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(l.themeDark),
            ),
          ],
          selected: {current},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _ScaleSetting extends StatelessWidget {
  final double current;
  final ValueChanged<double> onChanged;

  const _ScaleSetting({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l.uiScale,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<double>(
          segments: uiScaleSteps
              .map((s) => ButtonSegment(
                    value: s,
                    label: Text('${(s * 100).round()}%'),
                  ))
              .toList(),
          selected: {current},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _LanguageSetting extends StatelessWidget {
  final Locale current;
  final ValueChanged<Locale> onChanged;

  const _LanguageSetting({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l.language,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<Locale>(
          segments: [
            ButtonSegment(
              value: const Locale('de'),
              label: Text(l.languageGerman),
            ),
            ButtonSegment(
              value: const Locale('en'),
              label: Text(l.languageEnglish),
            ),
          ],
          selected: {current},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _ChatFontSizeSetting extends StatelessWidget {
  final double current;
  final ValueChanged<double> onChanged;

  const _ChatFontSizeSetting({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final labels = {
      13.0: l.fontSizeSmall,
      15.0: l.fontSizeMedium,
      17.0: l.fontSizeLarge,
      19.0: l.fontSizeXL,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(l.chatFontSize,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<double>(
          segments: chatFontSizeSteps
              .map((s) => ButtonSegment(
                    value: s,
                    label: Text(labels[s] ?? ''),
                  ))
              .toList(),
          selected: {current},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}
