import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_queue_item.dart';
import '../services/shared_url_parser.dart';
import '../state/app_state.dart';

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submitCurrentInput() async {
    final appState = context.read<AppState>();
    final urls = SharedUrlParser.extractYoutubeUrls(_urlController.text);
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid YouTube links found.')),
      );
      return;
    }

    final result = await appState.addUrlsToQueue(urls);
    if (!mounted) return;
    final accepted = result != QueueAddResult.failed;
    if (accepted) _urlController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == QueueAddResult.added
              ? 'Added ${urls.length} link(s) to the queue'
              : appState.statusMessage,
        ),
      ),
    );
  }

  Future<void> _confirmClearQueue() async {
    final appState = context.read<AppState>();
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear queue?'),
            content: const Text(
              'Remove every waiting link from the server queue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes) await appState.clearQueue();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final inProgress = appState.inProgressQueue;
        final queued = appState.queuedQueue;
        final failed = appState.failedQueue;
        final hasQueueItems =
            inProgress.isNotEmpty || queued.isNotEmpty || failed.isNotEmpty;

        return RefreshIndicator(
          onRefresh: appState.refreshQueue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 96),
            children: [
              _QueueComposer(
                controller: _urlController,
                isAdding: appState.isAddingToQueue,
                isAuthenticated: appState.isAuthenticated,
                onSubmit: _submitCurrentInput,
                onOpenSettings: widget.onOpenSettings,
              ),
              if (appState.pendingShareUrls.isNotEmpty)
                _PendingSharePanel(
                  urls: appState.pendingShareUrls,
                  isAuthenticated: appState.isAuthenticated,
                  isAdding: appState.isAddingToQueue,
                  onAddPending: appState.retryPendingShareUrls,
                  onOpenSettings: widget.onOpenSettings,
                ),
              _QueueActions(
                queuedCount: queued.length,
                inProgressCount: inProgress.length,
                failedCount: failed.length,
                isProcessing: appState.isQueueProcessing,
                isLoading: appState.isQueueLoading,
                isAuthenticated: appState.isAuthenticated,
                onRefresh: appState.refreshQueue,
                onStart: appState.processQueue,
                onClear: _confirmClearQueue,
              ),
              if (appState.isQueueLoading) const LinearProgressIndicator(),
              if (!hasQueueItems)
                _EmptyQueue(isAuthenticated: appState.isAuthenticated)
              else ...[
                if (inProgress.isNotEmpty)
                  _QueueSection(
                    title: 'In progress',
                    items: inProgress,
                    emptyText: '',
                  ),
                if (queued.isNotEmpty)
                  _QueueSection(
                    title: 'Queued',
                    items: queued,
                    emptyText: '',
                  ),
                if (failed.isNotEmpty)
                  _QueueSection(
                    title: 'Failed',
                    items: failed,
                    emptyText: '',
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QueueComposer extends StatelessWidget {
  const _QueueComposer({
    required this.controller,
    required this.isAdding,
    required this.isAuthenticated,
    required this.onSubmit,
    required this.onOpenSettings,
  });

  final TextEditingController controller;
  final bool isAdding;
  final bool isAuthenticated;
  final Future<void> Function() onSubmit;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add YouTube links',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton.filled(
                tooltip: isAuthenticated ? 'Add to queue' : 'Save for sign-in',
                onPressed: isAdding ? null : onSubmit,
                icon: isAdding
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
              if (!isAuthenticated) ...[
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: 'Open Settings',
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              labelText: 'YouTube URL',
              hintText: isAuthenticated
                  ? 'Paste one or more links'
                  : 'Links are saved until you sign in',
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAuthenticated
                ? 'Paste links here or share directly from YouTube.'
                : 'Sign in later and pending links will be added automatically.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingSharePanel extends StatelessWidget {
  const _PendingSharePanel({
    required this.urls,
    required this.isAuthenticated,
    required this.isAdding,
    required this.onAddPending,
    required this.onOpenSettings,
  });

  final List<String> urls;
  final bool isAuthenticated;
  final bool isAdding;
  final Future<bool> Function() onAddPending;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: scheme.tertiaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.pending_actions, color: scheme.tertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${urls.length} shared link(s) waiting',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: isAuthenticated
                    ? (isAdding ? null : onAddPending)
                    : onOpenSettings,
                icon: Icon(isAuthenticated ? Icons.playlist_add : Icons.tune),
                label: Text(isAuthenticated ? 'Add' : 'Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueActions extends StatelessWidget {
  const _QueueActions({
    required this.queuedCount,
    required this.inProgressCount,
    required this.failedCount,
    required this.isProcessing,
    required this.isLoading,
    required this.isAuthenticated,
    required this.onRefresh,
    required this.onStart,
    required this.onClear,
  });

  final int queuedCount;
  final int inProgressCount;
  final int failedCount;
  final bool isProcessing;
  final bool isLoading;
  final bool isAuthenticated;
  final Future<bool> Function() onRefresh;
  final Future<bool> Function() onStart;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$queuedCount queued'
              '${inProgressCount > 0 ? ' · $inProgressCount active' : ''}'
              '${failedCount > 0 ? ' · $failedCount failed' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh queue',
            onPressed: isLoading || !isAuthenticated ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton.filled(
            tooltip: isProcessing ? 'Processing' : 'Start downloads',
            onPressed: !isAuthenticated || queuedCount == 0 || isProcessing
                ? null
                : onStart,
            icon: isProcessing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 4),
          IconButton.outlined(
            tooltip: 'Clear queued links',
            onPressed: !isAuthenticated || queuedCount == 0 ? null : onClear,
            icon: const Icon(Icons.clear_all),
          ),
        ],
      ),
    );
  }
}

class _QueueSection extends StatelessWidget {
  const _QueueSection({
    required this.title,
    required this.items,
    required this.emptyText,
  });

  final String title;
  final List<DownloadQueueItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(emptyText),
          )
        else
          ...items.map((item) => _QueueItemRow(item: item)),
      ],
    );
  }
}

class _QueueItemRow extends StatelessWidget {
  const _QueueItemRow({required this.item});

  final DownloadQueueItem item;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(scheme, item.status);
    final isFailed = item.status == DownloadStatus.error;
    final isPending = item.status == DownloadStatus.pending;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_statusIcon(item.status), color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? item.url,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: isFailed ? scheme.error : null,
                      ),
                    ),
                    if (item.artist != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _statusText(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.status == DownloadStatus.downloading &&
                        item.percentage != null) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (item.percentage! / 100).clamp(0.0, 1.0),
                      ),
                    ],
                    if (item.title != null && !isFailed) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isFailed) ...[
                IconButton(
                  tooltip: 'Retry',
                  onPressed: () => appState.retryFailedDownload(item),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: 'Dismiss failed item',
                  onPressed: () => appState.dismissLocalQueueItem(item.url),
                  icon: const Icon(Icons.close),
                ),
              ] else if (isPending)
                IconButton(
                  tooltip: 'Remove from queue',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => appState.removeUrlFromQueue(item.url),
                ),
            ],
          ),
        ),
        Divider(height: 1, indent: 72, color: scheme.outlineVariant),
      ],
    );
  }

  String _statusText(DownloadQueueItem item) {
    switch (item.status) {
      case DownloadStatus.pending:
        return 'Waiting for download';
      case DownloadStatus.downloading:
        final percentage = item.percentage;
        final bytes = _bytesText(item);
        final progress = percentage == null
            ? 'Downloading'
            : 'Downloading ${percentage.toStringAsFixed(1)}%';
        return bytes == null ? progress : '$progress · $bytes';
      case DownloadStatus.processing:
        return 'Processing';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.error:
        return item.error == null ? 'Failed to download' : item.error!;
    }
  }

  String? _bytesText(DownloadQueueItem item) {
    final downloaded = item.downloadedBytes;
    final total = item.totalBytes;
    if (downloaded == null || total == null || total <= 0) {
      return null;
    }
    return '${_formatBytes(downloaded)} of ${_formatBytes(total)}';
  }

  String _formatBytes(int value) {
    final mb = value / (1024 * 1024);
    if (mb >= 1) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final kb = value / 1024;
    return '${kb.toStringAsFixed(0)} KB';
  }

  IconData _statusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return Icons.drag_handle;
      case DownloadStatus.downloading:
        return Icons.downloading;
      case DownloadStatus.processing:
        return Icons.auto_awesome;
      case DownloadStatus.completed:
        return Icons.check_circle_outline;
      case DownloadStatus.error:
        return Icons.error_outline;
    }
  }

  Color _statusColor(ColorScheme scheme, DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return scheme.onSurfaceVariant;
      case DownloadStatus.downloading:
        return scheme.primary;
      case DownloadStatus.processing:
        return scheme.tertiary;
      case DownloadStatus.completed:
        return scheme.secondary;
      case DownloadStatus.error:
        return scheme.error;
    }
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.isAuthenticated});

  final bool isAuthenticated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.playlist_add_check,
            size: 52,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(isAuthenticated ? 'Queue is empty' : 'Queue is offline'),
          const SizedBox(height: 6),
          Text(
            isAuthenticated
                ? 'Paste a link above or share from YouTube to start a download.'
                : 'Sign in from Settings and pending links will be added automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
