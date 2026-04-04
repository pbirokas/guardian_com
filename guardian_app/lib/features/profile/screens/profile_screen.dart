import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/organizations/providers/organizations_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _nameController;
  bool _saving = false;
  bool _pickingImage = false;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
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
        setState(() => _pickedImage = File(picked.path));
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
      final user = FirebaseAuth.instance.currentUser!;
      String? photoUrl;

      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('profileImages/${user.uid}');
        await ref.putFile(_pickedImage!);
        photoUrl = await ref.getDownloadURL();
        await user.updatePhotoURL(photoUrl);
      }

      await user.updateDisplayName(name);

      // Firestore user doc synchronisieren
      final updates = <String, dynamic>{'displayName': name};
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      // displayName (und ggf. photoUrl) in allen Org-Mitgliedsdokumenten aktualisieren
      await ref
          .read(organizationServiceProvider)
          .updateMyMemberProfile(name, photoUrl: photoUrl);

      if (mounted) {
        setState(() => _pickedImage = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil gespeichert.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    ImageProvider? avatarImage;
    if (_pickedImage != null) {
      avatarImage = FileImage(_pickedImage!);
    } else if (user?.photoURL != null) {
      avatarImage = NetworkImage(user!.photoURL!);
    }

    final initials = ((user?.displayName?.isNotEmpty == true
                ? user!.displayName!
                : user?.email ?? '?')[0])
        .toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil bearbeiten'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Speichern'),
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
                  CircleAvatar(
                    radius: 48,
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(initials,
                            style: const TextStyle(fontSize: 36))
                        : null,
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
          if (_pickedImage != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Text('Neues Bild ausgewählt — speichern um zu übernehmen',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              user?.email ?? '',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Anzeigename',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _ThemeSetting(
            current: ref.watch(themeModeProvider),
            onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Abmelden',
                style: TextStyle(color: Colors.red)),
            onTap: () => ref.read(authServiceProvider).signOut(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Erscheinungsbild',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('Hell'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('Dunkel'),
            ),
          ],
          selected: {current},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}
