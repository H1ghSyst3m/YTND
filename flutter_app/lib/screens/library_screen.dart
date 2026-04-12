import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/app_state.dart';
import 'download_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, Song song) async {
    final appState = context.read<AppState>();
    final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete song?'),
            content: Text('Delete "${song.title}" by ${song.artist} on server and local storage?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!yes) {
      return;
    }

    try {
      await appState.deleteSong(song);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted ${song.title}')),
        );
      }
    } catch (e, st) {
      debugPrint('Delete failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delete failed. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image(
                  image: AssetImage('assets/logo.png'),
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                ),
                SizedBox(width: 8),
                Text('YTND Library'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh songs',
                onPressed: () => appState.refreshSongs(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Downloads',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DownloadScreen()),
                  );
                },
                icon: const Icon(Icons.download),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings),
              ),
              IconButton(
                tooltip: 'Logout',
                onPressed: () => appState.logout(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(12),
                child: Text(
                  appState.statusMessage.isEmpty ? 'Ready' : appState.statusMessage,
                ),
              ),
              Expanded(
                child: appState.songs.isEmpty
                    ? const Center(child: Text('No songs synced yet.'))
                    : ListView.separated(
                        itemBuilder: (context, index) {
                          final song = appState.songs[index];
                          return ListTile(
                            leading: _SongCover(
                              coverUrl: appState.coverUrlFor(song),
                              cookieHeader: appState.settings.sessionCookie,
                            ),
                            title: Text(song.title),
                            subtitle: Text(song.artist),
                            trailing: IconButton(
                              tooltip: 'Delete from server',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _confirmDelete(context, song),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: appState.songs.length,
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: appState.isSyncing ? null : () => appState.syncNow(),
            label: Text(appState.isSyncing ? 'Syncing...' : 'Sync now'),
            icon: const Icon(Icons.sync),
          ),
        );
      },
    );
  }
}

class _SongCover extends StatelessWidget {
  const _SongCover({
    required this.coverUrl,
    required this.cookieHeader,
  });

  final String? coverUrl;
  final String cookieHeader;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null) {
      return const SizedBox(
        width: _size,
        height: _size,
        child: Icon(Icons.music_note),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: NetworkImage(coverUrl!, headers: {'Cookie': cookieHeader}),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: _size,
          height: _size,
          child: Icon(Icons.music_note),
        ),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: _size,
            height: _size,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      ),
    );
  }
}
