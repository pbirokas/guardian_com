import 'package:cloud_firestore/cloud_firestore.dart';

class Announcement {
  final String id;
  final String title;
  final String content;
  final String authorUid;
  final String authorName;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
  final Map<String, String> reactions;

  const Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.authorUid,
    required this.authorName,
    required this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.reactions = const {},
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory Announcement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Announcement(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      authorUid: data['authorUid'] as String? ?? '',
      authorName: data['authorName'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
      reactions: (data['reactions'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'content': content,
        'authorUid': authorUid,
        'authorName': authorName,
        'createdAt': Timestamp.fromDate(createdAt),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      };
}
