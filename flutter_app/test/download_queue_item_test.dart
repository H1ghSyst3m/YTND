import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/models/download_queue_item.dart';

void main() {
  test('copyWith keeps URL and applies progress fields', () {
    const item = DownloadQueueItem(url: 'https://example.com/watch?v=1');

    final updated = item.copyWith(
      status: DownloadStatus.downloading,
      percentage: 37.5,
      downloadedBytes: 1024,
      totalBytes: 4096,
    );

    expect(updated.url, item.url);
    expect(updated.status, DownloadStatus.downloading);
    expect(updated.percentage, 37.5);
    expect(updated.downloadedBytes, 1024);
    expect(updated.totalBytes, 4096);

    final cleared = updated.copyWith(percentage: null);
    expect(cleared.percentage, isNull);
  });
}
