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

  factory ClaimRequest.fromAppwrite(Map<String, dynamic> data) =>
      ClaimRequest(
        id: data[r'$id'] as String,
        fromUid: data['fromUid'] as String,
        fromName: data['fromName'] as String? ?? '',
        fromEmail: data['fromEmail'] as String? ?? '',
        toUid: data['toUid'] as String,
        toEmail: data['toEmail'] as String? ?? '',
        status: ClaimRequestStatus.values
            .byName(data['status'] as String? ?? 'pending'),
        createdAt: DateTime.parse(data['createdAt'] as String).toLocal(),
        expiresAt: DateTime.parse(data['expiresAt'] as String).toLocal(),
      );

  Map<String, dynamic> toAppwrite() => {
        'fromUid': fromUid,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'toUid': toUid,
        'toEmail': toEmail,
        'status': status.name,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
      };
}
