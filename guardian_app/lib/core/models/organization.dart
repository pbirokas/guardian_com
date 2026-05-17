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

class Organization {
  final String id;
  final String name;
  final String adminUid;
  final OrgTag tag;
  final List<String> memberUids;
  final DateTime createdAt;
  final bool isArchived;
  final List<String> keywords;
  final int messageRetentionDays;
  final int pendingReportsCount;

  static const int retentionMin = 30;
  static const int retentionMax = 365;
  static const int retentionDefault = 90;

  const Organization({
    required this.id,
    required this.name,
    required this.adminUid,
    required this.tag,
    required this.memberUids,
    required this.createdAt,
    this.isArchived = false,
    this.keywords = const [],
    this.messageRetentionDays = retentionDefault,
    this.pendingReportsCount = 0,
  });

  factory Organization.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Organization(
      id: doc.id,
      name: data['name'] as String,
      adminUid: data['adminUid'] as String,
      tag: OrgTag.values.byName(data['tag'] as String? ?? 'sonstiges'),
      memberUids: List<String>.from(data['memberUids'] as List? ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      isArchived: data['isArchived'] as bool? ?? false,
      keywords: List<String>.from(data['keywords'] as List? ?? []),
      messageRetentionDays:
          (data['messageRetentionDays'] as int? ?? retentionDefault)
              .clamp(retentionMin, retentionMax),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'adminUid': adminUid,
        'tag': tag.name,
        'memberUids': memberUids,
        'createdAt': Timestamp.fromDate(createdAt),
        'isArchived': isArchived,
        'keywords': keywords,
        'messageRetentionDays': messageRetentionDays,
      };

  factory Organization.fromAppwrite(Map<String, dynamic> data) => Organization(
        id: data[r'$id'] as String,
        name: data['name'] as String,
        adminUid: data['adminUid'] as String,
        tag: OrgTag.values.byName(data['tag'] as String? ?? 'sonstiges'),
        memberUids: List<String>.from(data['memberUids'] as List? ?? []),
        createdAt: DateTime.parse(data['createdAt'] as String),
        isArchived: data['isArchived'] as bool? ?? false,
        keywords: List<String>.from(data['keywords'] as List? ?? []),
        messageRetentionDays:
            (data['messageRetentionDays'] as int? ?? retentionDefault)
                .clamp(retentionMin, retentionMax),
        pendingReportsCount: data['pendingReportsCount'] as int? ?? 0,
      );

  Map<String, dynamic> toAppwrite() => {
        'name': name,
        'adminUid': adminUid,
        'tag': tag.name,
        'memberUids': memberUids,
        'createdAt': createdAt.toIso8601String(),
        'isArchived': isArchived,
        'keywords': keywords,
        'messageRetentionDays': messageRetentionDays,
      };
}
