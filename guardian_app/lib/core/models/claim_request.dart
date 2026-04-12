import 'package:cloud_firestore/cloud_firestore.dart';

enum ClaimRequestStatus { pending, confirmed, rejected, cancelled, expired }

class ClaimRequest {
  final String id;
  final String fromUid;    // Elternteil (Initiator)
  final String fromName;
  final String fromEmail;
  final String toUid;      // Kind
  final String toEmail;
  final ClaimRequestStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;

  const ClaimRequest({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromEmail,
    required this.toUid,
    required this.toEmail,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  });

  bool get isExpired =>
      status == ClaimRequestStatus.pending &&
      DateTime.now().isAfter(expiresAt);

  bool get isPending => status == ClaimRequestStatus.pending && !isExpired;

  factory ClaimRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ClaimRequest(
      id: doc.id,
      fromUid: d['fromUid'] as String,
      fromName: d['fromName'] as String? ?? '',
      fromEmail: d['fromEmail'] as String? ?? '',
      toUid: d['toUid'] as String,
      toEmail: d['toEmail'] as String? ?? '',
      status: ClaimRequestStatus.values.byName(
          d['status'] as String? ?? 'pending'),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
      expiresAt: (d['expiresAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'fromUid': fromUid,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'toUid': toUid,
        'toEmail': toEmail,
        'status': status.name,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
      };
}
