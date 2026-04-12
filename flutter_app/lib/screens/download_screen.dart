import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/download_queue_item.dart';
import '../services/share_intent_service.dart';
import '../state/app_state.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  final TextEditingController _urlController = TextEditingController();
  final ShareIntentService _shareIntentService = ShareIntentService();
  StreamSubscription<String>? _shareSubscription;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final appState = context.read<AppState>();
      await appState.refreshQueue();
      if (!mounted) {
        return;
      }
      final initial = appState.consumePendingShareUrl();
      if (initial != null) {
        await _sendUrls([initial]);
      }
      if (!mounted) {
        return;
      }
      _shareSubscription = _shareIntentService.sharedTextStream.listen((sharedText) async {
        if (!mounted) {
          return;
        }
        await _sendUrls([sharedText]);
      });
    });
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _sendUrls(List<String> urls) async {
    final appState = context.read<AppState>();
    try {
      await appState.addUrlsToQueue(urls);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${urls.length} URL(s) to queue')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      debugPrint('Failed to add URL(s): $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add URL. Please try again.')),
      );
    }
  }

  Future<void> _submitCurrentInput() async {
    final value = _urlController.text
        .split('\n')
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList();
    if (value.isEmpty) {
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _sendUrls(value);
      if (mounted) {
        _urlController.clear();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _statusText(DownloadQueueItem item) {
    switch (item.status) {
      case DownloadStatus.pending:
        return 'Pending';
      case DownloadStatus.downloading:
        final percentage = item.percentage;
        if (percentage != null) {
          return 'Downloading ${percentage.toStringAsFixed(1)}%';
        }
        return 'Downloading...';
      case DownloadStatus.processing:
        return 'Processing...';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.error:
        return item.error == null ? 'Error' : 'Error: ${item.error}';
    }
  }

  Color _statusColor(BuildContext context, DownloadStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case DownloadStatus.pending:
        return scheme.onSurfaceVariant;
      case DownloadStatus.downloading:
        return scheme.primary;
      case DownloadStatus.processing:
        return scheme.tertiary;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.error:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Downloads')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'URL',
                        hintText: 'Paste one or more URLs (one per line)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSubmitting ? null : _submitCurrentInput,
                            icon: const Icon(Icons.add),
                            label: const Text('Add to queue'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: appState.downloadQueue.isEmpty || appState.isQueueProcessing
                                ? null
                                : () => appState.processQueue(),
                            icon: appState.isQueueProcessing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_arrow),
                            label: Text(appState.isQueueProcessing ? 'Processing' : 'Start'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: appState.downloadQueue.isEmpty ? null : () => appState.clearQueue(),
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear queue'),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: appState.downloadQueue.isEmpty
                    ? const Center(child: Text('Queue is empty'))
                    : ListView.separated(
                        itemCount: appState.downloadQueue.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = appState.downloadQueue[index];
                          return ListTile(
                            title: Text(item.title ?? item.url),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.title != null) Text(item.url),
                                Text(
                                  _statusText(item),
                                  style: TextStyle(
                                    color: _statusColor(context, item.status),
                                  ),
                                ),
                                if (item.status == DownloadStatus.downloading && item.percentage != null)
                                  LinearProgressIndicator(value: item.percentage! / 100),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove from queue',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => appState.removeUrlFromQueue(item.url),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
