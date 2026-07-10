import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/sync_summary.dart';
import '../state/app_state.dart';
import 'library_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _lastQueueFocusVersion = 0;

  void _selectTab(int index) {
    if (_selectedIndex == index) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        if (!appState.initialized) {
          return const _SplashScreen();
        }

        if (appState.queueFocusVersion != _lastQueueFocusVersion) {
          _lastQueueFocusVersion = appState.queueFocusVersion;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _selectTab(1);
            }
          });
        }

        const titles = <String>['Library', 'Queue', 'Settings'];
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: _AppTitle(sectionTitle: titles[_selectedIndex]),
            actions: _actionsFor(context, appState),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (appState.shouldShowConnectionNotice)
                  _ConnectionNotice(onOpenSettings: () => _selectTab(2)),
                if (appState.isSyncing || appState.latestSyncSummary != null)
                  _SyncStatusStrip(
                    onOpenDetails: appState.latestSyncSummary == null
                        ? null
                        : () => _showSyncDetails(
                            context,
                            appState.latestSyncSummary!,
                          ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      LibraryScreen(onOpenSettings: () => _selectTab(2)),
                      QueueScreen(onOpenSettings: () => _selectTab(2)),
                      const SettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Library',
              ),
              NavigationDestination(
                icon: appState.pendingShareCount > 0
                    ? Badge(
                        label: Text('${appState.pendingShareCount}'),
                        child: const Icon(Icons.format_list_bulleted),
                      )
                    : const Icon(Icons.format_list_bulleted),
                selectedIcon: const Icon(Icons.format_list_bulleted),
                label: 'Queue',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _actionsFor(BuildContext context, AppState appState) {
    final actions = <Widget>[];
    if (appState.latestSyncSummary != null) {
      actions.add(
        IconButton(
          tooltip: 'Sync details',
          onPressed: () => _showSyncDetails(context, appState.latestSyncSummary!),
          icon: const Icon(Icons.receipt_long_outlined),
        ),
      );
    }

    if (_selectedIndex == 0) {
      actions.addAll([
        IconButton(
          tooltip: 'Refresh songs',
          onPressed: appState.isLibraryLoading ? null : appState.refreshSongs,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: appState.isSyncing ? 'Syncing' : 'Sync now',
          onPressed: appState.isSyncing ? null : appState.syncNow,
          icon: appState.isSyncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
        ),
      ]);
    } else if (_selectedIndex == 1) {
      actions.addAll([
        IconButton(
          tooltip: 'Refresh queue',
          onPressed: appState.isQueueLoading ? null : appState.refreshQueue,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Start downloads',
          onPressed: !appState.isAuthenticated ||
                  appState.queuedQueue.isEmpty ||
                  appState.isQueueProcessing
              ? null
              : appState.processQueue,
          icon: appState.isQueueProcessing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
        ),
      ]);
    }

    return actions;
  }

  Future<void> _showSyncDetails(
    BuildContext context,
    SyncSummary summary,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => _SyncDetailsSheet(summary: summary),
    );
  }
}

class _AppTitle extends StatelessWidget {
  const _AppTitle({required this.sectionTitle});

  final String sectionTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const Image(
            image: AssetImage('assets/logo.png'),
            width: 30,
            height: 30,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        const Text('YTND'),
        const SizedBox(width: 18),
        Text(
          sectionTitle,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: const Image(
                image: AssetImage('assets/logo.png'),
                width: 88,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Starting YTND...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(appState.connectionStatus, scheme);
    final showSettings = appState.connectionStatus != ConnectionStatus.connected;
    final message = appState.lastErrorMessage ?? appState.connectionMessage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIcon(appState.connectionStatus), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appState.connectionTitle,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _noticeMessage(appState, message),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (appState.connectionStatus == ConnectionStatus.unreachable)
                IconButton(
                  tooltip: 'Retry',
                  visualDensity: VisualDensity.compact,
                  onPressed: appState.retryConnection,
                  icon: const Icon(Icons.refresh),
                ),
              if (showSettings)
                IconButton(
                  tooltip: 'Open Settings',
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune),
                ),
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: appState.dismissConnectionNotice,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _noticeMessage(AppState appState, String message) {
    final pending = appState.pendingShareCount;
    if (pending == 0) {
      return message;
    }
    return '$message $pending shared link(s) waiting.';
  }
}

class _SyncStatusStrip extends StatelessWidget {
  const _SyncStatusStrip({this.onOpenDetails});

  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final summary = appState.latestSyncSummary;
    final title = appState.isSyncing
        ? 'Syncing songs'
        : summary?.message ?? 'Sync details';
    final subtitle = summary == null
        ? 'Comparing server and local files'
        : '${summary.remoteCount} server songs, ${summary.downloaded} downloaded, ${summary.deleted} removed';

    return InkWell(
      onTap: onOpenDetails,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            appState.isSyncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    summary?.success == false
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color: summary?.success == false
                        ? scheme.error
                        : scheme.secondary,
                    size: 20,
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (summary != null) const Icon(Icons.keyboard_arrow_up),
          ],
        ),
      ),
    );
  }
}

class _SyncDetailsSheet extends StatelessWidget {
  const _SyncDetailsSheet({required this.summary});

  final SyncSummary summary;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  summary.success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: summary.success ? scheme.secondary : scheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    summary.message,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () {
                    appState.clearLatestSyncSummary();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _SyncDetailRow(label: 'Server songs', value: summary.remoteCount),
            _SyncDetailRow(label: 'Downloaded', value: summary.downloaded),
            _SyncDetailRow(label: 'Removed locally', value: summary.deleted),
            const SizedBox(height: 8),
            Text(
              _completedText(summary.completedAt),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _completedText(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return 'Completed at $hour:$minute';
  }
}

class _SyncDetailRow extends StatelessWidget {
  const _SyncDetailRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

IconData _statusIcon(ConnectionStatus status) {
  switch (status) {
    case ConnectionStatus.setupRequired:
      return Icons.settings_suggest_outlined;
    case ConnectionStatus.signedOut:
      return Icons.lock_outline;
    case ConnectionStatus.checking:
      return Icons.sync;
    case ConnectionStatus.connected:
      return Icons.cloud_done_outlined;
    case ConnectionStatus.unreachable:
      return Icons.cloud_off_outlined;
    case ConnectionStatus.unauthorized:
      return Icons.key_off_outlined;
    case ConnectionStatus.invalidCredentials:
      return Icons.lock_person_outlined;
  }
}

Color _statusColor(ConnectionStatus status, ColorScheme scheme) {
  switch (status) {
    case ConnectionStatus.setupRequired:
    case ConnectionStatus.signedOut:
      return scheme.tertiary;
    case ConnectionStatus.checking:
      return scheme.primary;
    case ConnectionStatus.connected:
      return scheme.secondary;
    case ConnectionStatus.unreachable:
    case ConnectionStatus.unauthorized:
    case ConnectionStatus.invalidCredentials:
      return scheme.error;
  }
}
