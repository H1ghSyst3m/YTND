import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ytnd/models/song.dart';
import 'package:ytnd/services/api_service.dart';
import 'package:ytnd/services/sync_service.dart';

class _FakeApiService extends ApiService {
  _FakeApiService(this._songs);

  final List<Song> _songs;
  int downloadCalls = 0;

  @override
  Future<List<Song>> fetchSongs({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
  }) async {
    return _songs;
  }

  @override
  Future<void> downloadSong({
    required String serverUrl,
    required String userId,
    required String filename,
    required String cookieHeader,
    required File targetFile,
  }) async {
    downloadCalls += 1;
    await targetFile.parent.create(recursive: true);
    await targetFile.writeAsString('audio');
  }
}

void main() {
  test('sync downloads missing files and deletes stale local files', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_sync_test');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final stale = File(p.join(temp.path, 'stale.mp3'));
    await stale.writeAsString('old');

    final api = _FakeApiService(const [
      Song(title: 'A', artist: 'B', filename: 'track.opus', fileAvailable: true),
    ]);

    final service = SyncService(api);
    final result = await service.sync(
      serverUrl: 'http://localhost:8080',
      userId: 'u1',
      cookieHeader: 'ytnd_uid=x; ytnd_sig=y',
      storagePath: temp.path,
    );

    expect(result.downloaded, 1);
    expect(api.downloadCalls, equals(1));
    expect(result.deleted, 1);
    expect(File(p.join(temp.path, 'track.opus')).existsSync(), isTrue);
    expect(stale.existsSync(), isFalse);
  });

  test('sync skips songs that are not available as files on server', () async {
    final temp = await Directory.systemTemp.createTemp('ytnd_sync_test_unavailable');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final api = _FakeApiService(const [
      Song(
        title: 'Unavailable',
        artist: 'Artist',
        filename: 'missing.opus',
        fileAvailable: false,
      ),
    ]);

    final service = SyncService(api);
    final result = await service.sync(
      serverUrl: 'http://localhost:8080',
      userId: 'u1',
      cookieHeader: 'ytnd_uid=x; ytnd_sig=y',
      storagePath: temp.path,
    );

    expect(result.downloaded, 0);
    expect(api.downloadCalls, 0);
    expect(File(p.join(temp.path, 'missing.opus')).existsSync(), isFalse);
  });
}
