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

    final added = await appState.addUrlsToQueue(urls);
    if (!mounted) return;
    if (added) _urlController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? 'Added ${urls.length} link(s) to the queue' : appState.statusMessage)),
    );
  }

  Future<void> _confirmClearQueue() async {
    final appState = context.read<AppState>();
    final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear queue?'),
            content: const Text('Remove every waiting link from the server queue?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
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
        return RefreshIndicator(
          onRefresh: appState.refreshQueue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _QueueComposer(
                controller: _urlController,
                isAdding: appState.isAddingToQueue,
                isAuthenticated: appState.isAuthenticated,
                onSubmit: _submitCurrentInput,
                onOpenSettings: widget.onOpenSettings,
              ),
              if (appState.pendingShareUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                _PendingSharePanel(
                  urls: appState.pendingShareUrls,
                  isAuthenticated: appState.isAuthenticated,
                  isAdding: appState.isAddingToQueue,
                  onAddPending: appState.retryPendingShareUrls,
                  onOpenSettings: widget.onOpenSettings,
                ),
              ],
              const SizedBox(height: 16),
              _QueueActions(
                itemCount: appState.downloadQueue.length,
                isProcessing: appState.isQueueProcessing,
                isLoading: appState.isQueueLoading,
                isAuthenticated: appState.isAuthenticated,
                onRefresh: appState.refreshQueue,
                onStart: appState.processQueue,
                onClear: _confirmClearQueue,
              ),
              const SizedBox(height: 12),
              if (appState.isQueueLoading) const LinearProgressIndicator(),
              if (appState.isQueueLoading) const SizedBox(height: 12),
              if (appState.downloadQueue.isEmpty)
                _EmptyQueue(isAuthenticated: appState.isAuthenticated)
              else
                ...appState.downloadQueue.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QueueItemTile(item: item),
                  ),
                ),
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
    return Container(
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
              Icon(Icons.ios_share, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add YouTube links', style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      isAuthenticated
                          ? 'Paste links here or share directly from YouTube.'
                          : 'Links are saved until you sign in.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              labelText: 'YouTube URL',
              hintText: 'Paste one or more links, one per line',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: isAdding ? null : onSubmit,
                  icon: isAdding
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.playlist_add),
                  label: Text(isAuthenticated ? 'Add to queue' : 'Save for sign-in'),
                ),
              ),
              if (!isAuthenticated) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Open Settings',
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                ),
              ],
            ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pending_actions, color: scheme.tertiary),
              const SizedBox(width: 8),
              Expanded(child: Text('${urls.length} shared link(s) waiting', style: Theme.of(context).textTheme.titleSmall)),
              TextButton.icon(
                onPressed: isAuthenticated ? (isAdding ? null : onAddPending) : onOpenSettings,
                icon: Icon(isAuthenticated ? Icons.playlist_add : Icons.tune),
                label: Text(isAuthenticated ? 'Add now' : 'Settings'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...urls.take(3).map(
                (url) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
          if (urls.length > 3)
            Text(
              '+${urls.length - 3} more',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _QueueActions extends StatelessWidget {
  const _QueueActions({
    required this.itemCount,
    required this.isProcessing,
    required this.isLoading,
    required this.isAuthenticated,
    required this.onRefresh,
    required this.onStart,
    required this.onClear,
  });

  final int itemCount;
  final bool isProcessing;
  final bool isLoading;
  final bool isAuthenticated;
  final Future<bool> Function() onRefresh;
  final Future<bool> Function() onStart;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isLoading || !isAuthenticated ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text('$itemCount queued'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: !isAuthenticated || itemCount == 0 || isProcessing ? null : onStart,
            icon: isProcessing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(isProcessing ? 'Processing' : 'Start'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Clear queue',
          onPressed: !isAuthenticated || itemCount == 0 ? null : onClear,
          icon: const Icon(Icons.clear_all),
        ),
      ],
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  const _QueueItemTile({required this.item});

  final DownloadQueueItem item;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(scheme, item.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Icon(_statusIcon(item.status), color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title ?? item.url, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                  if (item.title != null) ...[
                    const SizedBox(height: 2),
                    Text(item.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 6),
                  Text(_statusText(item), style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
                  if (item.status == DownloadStatus.downloading && item.percentage != null) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: (item.percentage! / 100).clamp(0, 1)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove from queue',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => appState.removeUrlFromQueue(item.url),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(DownloadQueueItem item) {
    switch (item.status) {
      case DownloadStatus.pending:
        return 'Pending';
      case DownloadStatus.downloading:
        final percentage = item.percentage;
        return percentage == null ? 'Downloading...' : 'Downloading ${percentage.toStringAsFixed(1)}%';
      case DownloadStatus.processing:
        return 'Processing...';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.error:
        return item.error == null ? 'Error' : 'Error: ${item.error}';
    }
  }

  IconData _statusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return Icons.schedule;
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
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.playlist_add_check, size: 52, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(isAuthenticated ? 'Queue is empty' : 'Queue is offline'),
          const SizedBox(height: 6),
          Text(
            isAuthenticated
                ? 'Paste a link above or share from YouTube to start a download.'
                : 'Sign in from Settings and pending links will be added automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

