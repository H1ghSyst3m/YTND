import 'package:flutter_test/flutter_test.dart';
import 'package:ytnd/models/song.dart';

void main() {
  test('parses optional song date from API JSON', () {
    final song = Song.fromJson(const {
      'title': 'Dreamscape',
      'artist': 'Aural Drift',
      'date': '2025-05-10',
      'downloaded_at': '2026-01-15T18:30:00Z',
    });

    expect(song.date, '2025-05-10');
    expect(song.parsedDate, DateTime(2025, 5, 10));
    expect(song.downloadedAt, '2026-01-15T18:30:00Z');
    expect(song.parsedDownloadedAt, DateTime.utc(2026, 1, 15, 18, 30));
  });
}
