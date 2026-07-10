import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../services/cover_cache_service.dart';
import '../state/app_state.dart';

enum _LibrarySort { newest, title, artist, localStatus }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _LibrarySort _sort = _LibrarySort.newest;

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

        final songs = _sortSongs(_filterSongs(appState.songs), appState);
        final headerItems = _headerItems(appState, songs);
        return RefreshIndicator(
          onRefresh: appState.refreshSongs,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 96),
            itemCount: headerItems.length + (songs.isEmpty ? 1 : songs.length),
            itemBuilder: (context, index) {
              if (index < headerItems.length) {
                return headerItems[index];
              }

              if (songs.isEmpty) {
                return _EmptyLibrary(hasQuery: _query.isNotEmpty);
              }

              final song = songs[index - headerItems.length];
              return _SongRow(
                song: song,
                isAvailable: appState.isSongAvailable(song),
                isDownloaded: appState.isSongDownloaded(song),
                coverUrl: appState.coverUrlFor(song),
                cookieHeader: appState.settings.sessionCookie,
                onDelete: () => _confirmDelete(context, song),
                onRedownload: () => _redownload(context, song),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _headerItems(AppState appState, List<Song> songs) {
    return [
      _LibrarySummary(
        songCount: appState.songs.length,
        visibleCount: songs.length,
        isLoading: appState.isLibraryLoading,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
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
                  labelText: 'Search songs',
                  hintText: 'Title or artist',
                ),
              ),
            ),
            const SizedBox(width: 10),
            _SortMenu(
              sort: _sort,
              onChanged: (value) => setState(() => _sort = value),
            ),
          ],
        ),
      ),
      if (appState.isLibraryLoading) const LinearProgressIndicator(),
      if (appState.lastErrorMessage != null)
        _InlineMessage(
          icon: Icons.warning_amber_outlined,
          title: 'Library needs attention',
          message: appState.lastErrorMessage!,
          actionLabel: 'Retry',
          onAction: appState.refreshSongs,
        ),
    ];
  }

  List<Song> _filterSongs(List<Song> songs) {
    if (_query.isEmpty) {
      return List<Song>.of(songs);
    }
    return songs
        .where((song) {
          final title = song.title.toLowerCase();
          final artist = song.artist.toLowerCase();
          return title.contains(_query) || artist.contains(_query);
        })
        .toList(growable: false);
  }

  List<Song> _sortSongs(List<Song> songs, AppState appState) {
    final sorted = List<Song>.of(songs);
    sorted.sort((a, b) {
      switch (_sort) {
        case _LibrarySort.newest:
          return _compareNewest(a, b);
        case _LibrarySort.title:
          return _compareText(a.title, b.title);
        case _LibrarySort.artist:
          return _compareText(a.artist, b.artist);
        case _LibrarySort.localStatus:
          final downloaded =
              (appState.isSongDownloaded(b) ? 1 : 0) -
              (appState.isSongDownloaded(a) ? 1 : 0);
          if (downloaded != 0) {
            return downloaded;
          }
          final available =
              (appState.isSongAvailable(b) ? 1 : 0) -
              (appState.isSongAvailable(a) ? 1 : 0);
          return available == 0 ? _compareText(a.title, b.title) : available;
      }
    });
    return sorted;
  }

  int _compareNewest(Song a, Song b) {
    final aDate = a.parsedDownloadedAt;
    final bDate = b.parsedDownloadedAt;
    if (aDate == null && bDate == null) {
      return _compareText(a.title, b.title);
    }
    if (aDate == null) {
      return 1;
    }
    if (bDate == null) {
      return -1;
    }
    final date = bDate.compareTo(aDate);
    return date == 0 ? _compareText(a.title, b.title) : date;
  }

  int _compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}

class _LibrarySummary extends StatelessWidget {
  const _LibrarySummary({
    required this.songCount,
    required this.visibleCount,
    required this.isLoading,
  });

  final int songCount;
  final int visibleCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visibleCount == songCount
                      ? '$songCount songs'
                      : '$visibleCount of $songCount songs',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final _LibrarySort sort;
  final ValueChanged<_LibrarySort> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_LibrarySort>(
      tooltip: 'Sort songs',
      initialValue: sort,
      onSelected: onChanged,
      itemBuilder: (context) => _LibrarySort.values
          .map(
            (value) => PopupMenuItem(
              value: value,
              child: Text(_sortLabel(value)),
            ),
          )
          .toList(),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_sortLabel(sort)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  String _sortLabel(_LibrarySort value) {
    switch (value) {
      case _LibrarySort.newest:
        return 'Newest';
      case _LibrarySort.title:
        return 'Title';
      case _LibrarySort.artist:
        return 'Artist';
      case _LibrarySort.localStatus:
        return 'Status';
    }
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.song,
    required this.isAvailable,
    required this.isDownloaded,
    required this.coverUrl,
    required this.cookieHeader,
    required this.onDelete,
    required this.onRedownload,
  });

  final Song song;
  final bool isAvailable;
  final bool isDownloaded;
  final String? coverUrl;
  final String cookieHeader;
  final VoidCallback onDelete;
  final VoidCallback onRedownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = isDownloaded
        ? scheme.secondary
        : isAvailable
        ? scheme.primary
        : scheme.tertiary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
          child: Row(
            children: [
              _SongCover(coverUrl: coverUrl, cookieHeader: cookieHeader),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _dateLabel(song),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ..._statusWidgets(
                          context,
                          scheme,
                          statusColor: statusColor,
                          isAvailable: isAvailable,
                          isDownloaded: isDownloaded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                isDownloaded
                    ? Icons.check_circle_outline
                    : isAvailable
                    ? Icons.cloud_download_outlined
                    : Icons.error_outline,
                color: statusColor,
                size: 22,
              ),
              PopupMenuButton<String>(
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
            ],
          ),
        ),
        Divider(height: 1, indent: 76, color: scheme.outlineVariant),
      ],
    );
  }

  String _dateLabel(Song song) {
    final downloadedAt = song.parsedDownloadedAt;
    if (downloadedAt == null) {
      return 'No download date';
    }
    final date = downloadedAt.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  List<Widget> _statusWidgets(
    BuildContext context,
    ColorScheme scheme, {
    required Color statusColor,
    required bool isAvailable,
    required bool isDownloaded,
  }) {
    final labels = <String>[
      if (isAvailable) 'Available',
      if (isDownloaded) 'Downloaded',
      if (!isAvailable && !isDownloaded) 'Missing',
    ];
    final textStyle = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant);

    return [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) ...[
          const SizedBox(width: 5),
          Text('•', style: textStyle),
          const SizedBox(width: 5),
        ] else ...[
          const SizedBox(width: 6),
          Icon(Icons.circle, size: 5, color: statusColor),
          const SizedBox(width: 5),
        ],
        Text(labels[i], style: textStyle),
      ],
    ];
  }
}

class _SongCover extends StatefulWidget {
  const _SongCover({required this.coverUrl, required this.cookieHeader});

  final String? coverUrl;
  final String cookieHeader;

  static const double _size = 48;
  static const int _maxProviderCacheSize = 160;
  static final Map<String, ImageProvider> _providerCache = {};

  static ImageProvider? _cachedProviderFor(String coverUrl) {
    final provider = _providerCache.remove(coverUrl);
    if (provider == null) {
      return null;
    }
    if (provider is FileImage && !provider.file.existsSync()) {
      return null;
    }
    _providerCache[coverUrl] = provider;
    return provider;
  }

  static void _cacheProvider(String coverUrl, ImageProvider provider) {
    _providerCache.remove(coverUrl);
    _providerCache[coverUrl] = provider;
    while (_providerCache.length > _maxProviderCacheSize) {
      _providerCache.remove(_providerCache.keys.first);
    }
  }

  @override
  State<_SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<_SongCover> {
  ImageProvider? _provider;
  Future<ImageProvider?>? _providerFuture;

  @override
  void initState() {
    super.initState();
    _resolveProvider();
  }

  @override
  void didUpdateWidget(covariant _SongCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.cookieHeader != widget.cookieHeader) {
      _resolveProvider();
    }
  }

  void _resolveProvider() {
    final coverUrl = widget.coverUrl;
    if (coverUrl == null) {
      _provider = null;
      _providerFuture = null;
      return;
    }

    final cachedProvider = _SongCover._cachedProviderFor(coverUrl);
    if (cachedProvider != null) {
      _provider = cachedProvider;
      _providerFuture = null;
      return;
    }

    final memoryFile = CoverCacheService.instance.memoryFileFor(coverUrl);
    if (memoryFile != null) {
      final provider = FileImage(memoryFile);
      _SongCover._cacheProvider(coverUrl, provider);
      _provider = provider;
      _providerFuture = null;
      return;
    }

    _provider = null;
    _providerFuture = _loadProvider(coverUrl, widget.cookieHeader);
  }

  Future<ImageProvider?> _loadProvider(
    String coverUrl,
    String cookieHeader,
  ) async {
    final file = await CoverCacheService.instance.cachedFileFor(
      coverUrl: coverUrl,
      cookieHeader: cookieHeader,
    );
    if (file == null) {
      return null;
    }
    final provider = FileImage(file);
    _SongCover._cacheProvider(coverUrl, provider);
    return provider;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = _provider;
    if (provider != null) {
      return _CoverImage(provider: provider);
    }

    final future = _providerFuture;
    if (future == null) {
      return _FallbackCover(
        color: scheme.primaryContainer,
        iconColor: scheme.onPrimaryContainer,
      );
    }

    return FutureBuilder<ImageProvider?>(
      future: future,
      builder: (context, snapshot) {
        final provider = snapshot.data;
        if (provider != null) {
          return _CoverImage(provider: provider);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingCover();
        }
        return _FallbackCover(
          color: scheme.surfaceContainerHighest,
          iconColor: scheme.onSurfaceVariant,
        );
      },
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.provider});

  final ImageProvider provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image(
        image: provider,
        width: _SongCover._size,
        height: _SongCover._size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _FallbackCover(
          color: scheme.surfaceContainerHighest,
          iconColor: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LoadingCover extends StatelessWidget {
  const _LoadingCover();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: _SongCover._size,
      height: _SongCover._size,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
      child: Icon(Icons.music_note, color: iconColor, size: 22),
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
              'Songs appear here after the server is reachable and you are signed in.',
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
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.music_off_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(hasQuery ? 'No songs match your search' : 'No songs yet'),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: scheme.errorContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
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
        ),
      ),
    );
  }
}
