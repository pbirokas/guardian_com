import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _showOnlineStatus = true;
  bool _showLastSeen = true;
  bool _showProfilePhoto = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Datenschutz')),
      body: ListView(
        children: [
          const _SectionHeader('Sichtbarkeit'),
          SwitchListTile(
            title: const Text('Online-Status anzeigen'),
            subtitle: const Text('Andere Mitglieder sehen wann du online bist'),
            value: _showOnlineStatus,
            onChanged: (v) => setState(() => _showOnlineStatus = v),
          ),
          SwitchListTile(
            title: const Text('Zuletzt gesehen'),
            subtitle: const Text('Andere Mitglieder sehen wann du zuletzt aktiv warst'),
            value: _showLastSeen,
            onChanged: (v) => setState(() => _showLastSeen = v),
          ),
          SwitchListTile(
            title: const Text('Profilbild sichtbar'),
            subtitle: const Text('Mitglieder können dein Profilbild sehen'),
            value: _showProfilePhoto,
            onChanged: (v) => setState(() => _showProfilePhoto = v),
          ),
          const Divider(),
          const _SectionHeader('Rechtliches'),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Datenschutzerklärung'),
            subtitle: const Text('Im Browser öffnen'),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () => launchUrl(
              Uri.parse('https://pbirokas.github.io/guardian_com/privacy_policy.html'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const Divider(),
          const _SectionHeader('Daten'),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Konto löschen',
                style: TextStyle(color: Colors.red)),
            subtitle: const Text('Alle Daten werden unwiderruflich gelöscht'),
            onTap: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto löschen'),
        content: const Text(
            'Möchtest du dein Konto wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold)),
    );
  }
}
