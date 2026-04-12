import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/song.dart';
import 'api_service.dart';

class SyncResult {
  const SyncResult({
    required this.downloaded,
    required this.deleted,
    required this.remoteCount,
  });

  final int downloaded;
  final int deleted;
  final int remoteCount;
}

class SyncService {
  SyncService(this._apiService);

  final ApiService _apiService;

  static const Set<String> _audioExtensions = {
    '.opus',
    '.mp3',
    '.m4a',
    '.flac',
    '.ogg',
  };

  Future<SyncResult> sync({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    required String storagePath,
  }) async {
    final songs = await _apiService.fetchSongs(
      serverUrl: serverUrl,
      userId: userId,
      cookieHeader: cookieHeader,
    );

    final dir = Directory(storagePath);
    await dir.create(recursive: true);

    final remoteFilenames = songs
        .where((s) => s.fileAvailable)
        .map((s) => s.filename)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();

    // Build a set of basenames for efficient stale-file detection.  The local
    // listing is flat (non-recursive) so comparing against basenames is correct
    // for files that sit directly under storagePath. Files whose remote
    // relative path contains a separator (i.e. in a sub-directory) are
    // downloaded into the correct sub-path but intentionally excluded from the
    // flat cleanup pass to avoid false deletions.
    final remoteBasenames = remoteFilenames
        .where((f) => !f.contains('/') && !f.contains(Platform.pathSeparator))
        .map(p.basename)
        .toSet();

    final localAudioFiles = await _listLocalAudioFiles(dir);
    var downloaded = 0;
    var deleted = 0;

    for (final filename in remoteFilenames) {
      if (p.isAbsolute(filename) || filename.contains('..')) {
        continue;
      }
      final resolved = p.normalize(p.join(dir.path, filename));
      if (!p.isWithin(dir.path, resolved)) {
        continue;
      }
      final local = File(resolved);
      if (!await local.exists()) {
        await _apiService.downloadSong(
          serverUrl: serverUrl,
          userId: userId,
          filename: filename,
          cookieHeader: cookieHeader,
          targetFile: local,
        );
        downloaded++;
      }
    }

    for (final localPath in localAudioFiles) {
      final name = p.basename(localPath);
      if (!remoteBasenames.contains(name)) {
        await File(localPath).delete();
        deleted++;
      }
    }

    return SyncResult(
      downloaded: downloaded,
      deleted: deleted,
      remoteCount: songs.length,
    );
  }

  Future<void> deleteSongOnServerAndLocal({
    required String serverUrl,
    required String userId,
    required String cookieHeader,
    required String storagePath,
    required Song song,
  }) async {
    await _apiService.deleteSong(
      serverUrl: serverUrl,
      userId: userId,
      song: song,
      cookieHeader: cookieHeader,
    );

    final filename = song.filename;
    if (filename == null || filename.isEmpty) {
      return;
    }

    if (p.isAbsolute(filename) || filename.contains('..')) {
      return;
    }
    final resolved = p.normalize(p.join(storagePath, filename));
    if (!p.isWithin(storagePath, resolved)) {
      return;
    }

    final localFile = File(resolved);
    if (await localFile.exists()) {
      await localFile.delete();
    }
  }

  Future<List<String>> _listLocalAudioFiles(Directory dir) async {
    final entries = await dir.list(recursive: false, followLinks: false).toList();
    return entries
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => _audioExtensions.contains(p.extension(path).toLowerCase()))
        .toList();
  }
}
