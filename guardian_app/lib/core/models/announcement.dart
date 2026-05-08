import 'package:cloud_firestore/cloud_firestore.dart';

enum AnnouncementType { announcement, event }

enum RsvpStatus { yes, no, maybe }

extension RsvpStatusX on RsvpStatus {
  String toFirestore() => switch (this) {
        RsvpStatus.yes => 'yes',
        RsvpStatus.no => 'no',
        RsvpStatus.maybe => 'maybe',
      };

  static RsvpStatus? fromString(String? value) => switch (value) {
        'yes' => RsvpStatus.yes,
        'no' => RsvpStatus.no,
        'maybe' => RsvpStatus.maybe,
        _ => null,
      };
}

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
  final AnnouncementType type;
  final DateTime? eventDate;
  final DateTime? eventEndDate;
  final String? location;
  final Map<String, String> rsvp;
  final bool rsvpPublic;

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
    this.type = AnnouncementType.announcement,
    this.eventDate,
    this.eventEndDate,
    this.location,
    this.rsvp = const {},
    this.rsvpPublic = false,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isEvent => type == AnnouncementType.event;

  bool get isPastEvent =>
      isEvent && eventDate != null && DateTime.now().isAfter(eventDate!);

  int get rsvpYesCount => rsvp.values.where((v) => v == 'yes').length;
  int get rsvpNoCount => rsvp.values.where((v) => v == 'no').length;
  int get rsvpMaybeCount => rsvp.values.where((v) => v == 'maybe').length;

  RsvpStatus? rsvpStatusFor(String uid) => RsvpStatusX.fromString(rsvp[uid]);

  factory Announcement.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String? ?? 'announcement';
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
      type: typeStr == 'event'
          ? AnnouncementType.event
          : AnnouncementType.announcement,
      eventDate: data['eventDate'] != null
          ? (data['eventDate'] as Timestamp).toDate()
          : null,
      eventEndDate: data['eventEndDate'] != null
          ? (data['eventEndDate'] as Timestamp).toDate()
          : null,
      location: data['location'] as String?,
      rsvp: (data['rsvp'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v as String)),
      rsvpPublic: data['rsvpPublic'] as bool? ?? false,
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
        'type': type == AnnouncementType.event ? 'event' : 'announcement',
        if (eventDate != null) 'eventDate': Timestamp.fromDate(eventDate!),
        if (eventEndDate != null)
          'eventEndDate': Timestamp.fromDate(eventEndDate!),
        if (location != null && location!.isNotEmpty) 'location': location,
        if (rsvpPublic) 'rsvpPublic': true,
      };
}
