enum DownloadStatus {
  pending,
  downloading,
  processing,
  completed,
  error,
}

class DownloadQueueItem {
  const DownloadQueueItem({
    required this.url,
    this.status = DownloadStatus.pending,
    this.title,
    this.artist,
    this.id,
    this.percentage,
    this.downloadedBytes,
    this.totalBytes,
    this.error,
  });

  final String url;
  final DownloadStatus status;
  final String? title;
  final String? artist;
  final String? id;
  final double? percentage;
  final int? downloadedBytes;
  final int? totalBytes;
  final String? error;

  static const Object _unset = Object();

  DownloadQueueItem copyWith({
    DownloadStatus? status,
    Object? title = _unset,
    Object? artist = _unset,
    Object? id = _unset,
    Object? percentage = _unset,
    Object? downloadedBytes = _unset,
    Object? totalBytes = _unset,
    Object? error = _unset,
  }) {
    return DownloadQueueItem(
      url: url,
      status: status ?? this.status,
      title: identical(title, _unset) ? this.title : title as String?,
      artist: identical(artist, _unset) ? this.artist : artist as String?,
      id: identical(id, _unset) ? this.id : id as String?,
      percentage: identical(percentage, _unset)
          ? this.percentage
          : (percentage is num ? percentage.toDouble() : percentage as double?),
      downloadedBytes: identical(downloadedBytes, _unset)
          ? this.downloadedBytes
          : (downloadedBytes is num ? downloadedBytes.toInt() : downloadedBytes as int?),
      totalBytes: identical(totalBytes, _unset)
          ? this.totalBytes
          : (totalBytes is num ? totalBytes.toInt() : totalBytes as int?),
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}
