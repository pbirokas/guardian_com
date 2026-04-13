import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

enum OrgTag {
  familie,
  freunde,
  schule,
  vereine,
  sonstiges;

  String get label => switch (this) {
        OrgTag.familie => 'Familie',
        OrgTag.freunde => 'Freunde',
        OrgTag.schule => 'Schule',
        OrgTag.vereine => 'Vereine',
        OrgTag.sonstiges => 'Sonstiges',
      };

  String localizedLabel(AppLocalizations l) => switch (this) {
        OrgTag.familie => l.orgTagFamilie,
        OrgTag.freunde => l.orgTagFreunde,
        OrgTag.schule => l.orgTagSchule,
        OrgTag.vereine => l.orgTagVereine,
        OrgTag.sonstiges => l.orgTagSonstiges,
      };

  IconData get icon => switch (this) {
        OrgTag.familie => Icons.home_outlined,
        OrgTag.freunde => Icons.people_outlined,
        OrgTag.schule => Icons.school_outlined,
        OrgTag.vereine => Icons.sports_outlined,
        OrgTag.sonstiges => Icons.category_outlined,
      };

  Color get color => switch (this) {
        OrgTag.familie => Colors.green,
        OrgTag.freunde => Colors.blue,
        OrgTag.schule => Colors.orange,
        OrgTag.vereine => Colors.purple,
        OrgTag.sonstiges => Colors.grey,
      };
}

enum ChatMode {
  guardian,
  sheltered;

  String get label => switch (this) {
        ChatMode.guardian => 'Guardian',
        ChatMode.sheltered => 'Sheltered',
      };

  String get description => switch (this) {
        ChatMode.guardian =>
          'Mitglieder können einen Chat anfordern. Ein Admin oder Moderator genehmigt oder lehnt die Anfrage ab.',
        ChatMode.sheltered =>
          'Der Admin legt vorab fest, wer mit wem kommunizieren darf. Nur freigegebene Verbindungen sind erlaubt.',
      };

  IconData get icon => switch (this) {
        ChatMode.guardian => Icons.shield_outlined,
        ChatMode.sheltered => Icons.lock_outlined,
      };
}

class Organization {
  final String id;
  final String name;
  final String adminUid;
  final OrgTag tag;
  final ChatMode chatMode;
  final List<String> memberUids;
  final DateTime createdAt;
  final bool isArchived;
  final List<String> keywords;

  const Organization({
    required this.id,
    required this.name,
    required this.adminUid,
    required this.tag,
    required this.chatMode,
    required this.memberUids,
    required this.createdAt,
    this.isArchived = false,
    this.keywords = const [],
  });

  factory Organization.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Organization(
      id: doc.id,
      name: data['name'] as String,
      adminUid: data['adminUid'] as String,
      tag: OrgTag.values.byName(data['tag'] as String? ?? 'sonstiges'),
      chatMode:
          ChatMode.values.byName(data['chatMode'] as String? ?? 'guardian'),
      memberUids: List<String>.from(data['memberUids'] as List? ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isArchived: data['isArchived'] as bool? ?? false,
      keywords: List<String>.from(data['keywords'] as List? ?? []),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'adminUid': adminUid,
        'tag': tag.name,
        'chatMode': chatMode.name,
        'memberUids': memberUids,
        'createdAt': Timestamp.fromDate(createdAt),
        'isArchived': isArchived,
        'keywords': keywords,
      };
}
