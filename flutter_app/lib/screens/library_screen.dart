import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../state/app_state.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete(BuildContext context, Song song) async {
    final appState = context.read<AppState>();
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete song?'),
            content: Text(
              'Delete "${song.title}" by ${song.artist} from the server and local storage?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!yes || !context.mounted) {
      return;
    }

    final deleted = await appState.deleteSong(song);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deleted ? 'Deleted ${song.title}' : appState.statusMessage,
          ),
        ),
      );
    }
  }

  Future<void> _redownload(BuildContext context, Song song) async {
    final appState = context.read<AppState>();
    final queued = await appState.redownloadSong(song);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued
                ? 'Queued ${song.title} for redownload'
                : appState.statusMessage,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        if (!appState.isAuthenticated) {
          return _LockedState(onOpenSettings: widget.onOpenSettings);
        }

        final songs = _filterSongs(appState.songs);
        return RefreshIndicator(
          onRefresh: appState.refreshSongs,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount:
                _headerItemCount(appState) + (songs.isEmpty ? 1 : songs.length),
            itemBuilder: (context, index) {
              final header = _headerItemAt(appState, songs, index);
              if (header != null) {
                return header;
              }

              if (songs.isEmpty) {
                return _EmptyLibrary(hasQuery: _query.isNotEmpty);
              }

              final song = songs[index - _headerItemCount(appState)];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SongTile(
                  song: song,
                  coverUrl: appState.coverUrlFor(song),
                  cookieHeader: appState.settings.sessionCookie,
                  onDelete: () => _confirmDelete(context, song),
                  onRedownload: () => _redownload(context, song),
                ),
              );
            },
          ),
        );
      },
    );
  }

  int _headerItemCount(AppState appState) {
    return 4 +
        (appState.isLibraryLoading ? 2 : 0) +
        (appState.lastErrorMessage != null ? 1 : 0);
  }

  Widget? _headerItemAt(AppState appState, List<Song> songs, int index) {
    final items = <Widget>[
      _LibraryHeader(
        songCount: appState.songs.length,
        visibleCount: songs.length,
        isSyncing: appState.isSyncing,
        isLoading: appState.isLibraryLoading,
        onRefresh: appState.refreshSongs,
        onSync: appState.syncNow,
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.close),
                ),
          labelText: 'Search library',
          hintText: 'Title or artist',
        ),
      ),
      const SizedBox(height: 16),
      if (appState.isLibraryLoading) const LinearProgressIndicator(),
      if (appState.isLibraryLoading) const SizedBox(height: 12),
      if (appState.lastErrorMessage != null)
        _InlineMessage(
          icon: Icons.warning_amber_outlined,
          title: 'Library needs attention',
          message: appState.lastErrorMessage!,
          actionLabel: 'Retry',
          onAction: appState.refreshSongs,
        ),
    ];

    if (index >= items.length) {
      return null;
    }
    return items[index];
  }

  List<Song> _filterSongs(List<Song> songs) {
    if (_query.isEmpty) {
      return songs;
    }
    return songs
        .where((song) {
          final title = song.title.toLowerCase();
          final artist = song.artist.toLowerCase();
          return title.contains(_query) || artist.contains(_query);
        })
        .toList(growable: false);
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.songCount,
    required this.visibleCount,
    required this.isSyncing,
    required this.isLoading,
    required this.onRefresh,
    required this.onSync,
  });

  final int songCount;
  final int visibleCount;
  final bool isSyncing;
  final bool isLoading;
  final Future<bool> Function() onRefresh;
  final Future<bool> Function() onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.library_music,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your synced library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      visibleCount == songCount
                          ? '$songCount songs'
                          : '$visibleCount of $songCount songs',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSyncing ? null : onSync,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(isSyncing ? 'Syncing' : 'Sync now'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.coverUrl,
    required this.cookieHeader,
    required this.onDelete,
    required this.onRedownload,
  });

  final Song song;
  final String? coverUrl;
  final String cookieHeader;
  final VoidCallback onDelete;
  final VoidCallback onRedownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: _SongCover(coverUrl: coverUrl, cookieHeader: cookieHeader),
        title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  song.fileAvailable
                      ? Icons.offline_pin_outlined
                      : Icons.hourglass_bottom,
                  size: 15,
                  color: song.fileAvailable
                      ? scheme.secondary
                      : scheme.tertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  song.fileAvailable
                      ? 'Available locally'
                      : 'Processing or missing file',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Song actions',
          onSelected: (value) {
            if (value == 'redownload') {
              onRedownload();
            } else if (value == 'delete') {
              onDelete();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'redownload',
              child: ListTile(
                leading: Icon(Icons.replay),
                title: Text('Redownload'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SongCover extends StatelessWidget {
  const _SongCover({required this.coverUrl, required this.cookieHeader});

  final String? coverUrl;
  final String cookieHeader;

  static const double _size = 56;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (coverUrl == null) {
      return _FallbackCover(
        color: scheme.primaryContainer,
        iconColor: scheme.onPrimaryContainer,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: NetworkImage(coverUrl!, headers: {'Cookie': cookieHeader}),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _FallbackCover(
          color: scheme.surfaceContainerHighest,
          iconColor: scheme.onSurfaceVariant,
        ),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: _size,
            height: _size,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.color, required this.iconColor});

  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SongCover._size,
      height: _SongCover._size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note, color: iconColor),
    );
  }
}

class _LockedState extends StatelessWidget {
  const _LockedState({required this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'Connect your YTND server',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Your library appears here after the server is reachable and you are signed in.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune),
              label: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.hasQuery});

  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.music_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(hasQuery ? 'No songs match your search' : 'No songs synced yet'),
          const SizedBox(height: 6),
          Text(
            hasQuery
                ? 'Try a different title or artist.'
                : 'Share a YouTube link to YTND or add one from Queue.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final Future<bool> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(message),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
