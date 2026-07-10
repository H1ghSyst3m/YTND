class SyncSummary {
  const SyncSummary({
    required this.remoteCount,
    required this.downloaded,
    required this.deleted,
    required this.completedAt,
    required this.message,
    this.success = true,
  });

  final int remoteCount;
  final int downloaded;
  final int deleted;
  final DateTime completedAt;
  final String message;
  final bool success;
}
