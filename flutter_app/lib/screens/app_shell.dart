import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

        final titles = <String>['Library', 'Queue', 'Settings'];
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const Image(
                    image: AssetImage('assets/logo.png'),
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('YTND'),
                    Text(
                      titles[_selectedIndex],
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                _StatusBanner(onOpenSettings: () => _selectTab(2)),
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
                        child: const Icon(Icons.download_outlined),
                      )
                    : const Icon(Icons.download_outlined),
                selectedIcon: const Icon(Icons.download),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final color = _statusColor(appState.connectionStatus, scheme);
    final icon = _statusIcon(appState.connectionStatus);
    final pendingCount = appState.pendingShareCount;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(
          top: BorderSide(color: color.withValues(alpha: 0.16)),
          bottom: BorderSide(color: color.withValues(alpha: 0.24)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appState.connectionTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _bannerMessage(appState),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              if (appState.connectionStatus == ConnectionStatus.unreachable)
                TextButton.icon(
                  onPressed: appState.retryConnection,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              if (pendingCount > 0 && appState.isAuthenticated)
                TextButton.icon(
                  onPressed: appState.isAddingToQueue
                      ? null
                      : appState.retryPendingShareUrls,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Add'),
                ),
              if (appState.connectionStatus != ConnectionStatus.connected)
                TextButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Settings'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _bannerMessage(AppState appState) {
    final pending = appState.pendingShareCount;
    final parts = <String>[appState.connectionMessage];
    if (pending > 0) {
      parts.add('$pending shared link(s) waiting.');
    } else if (appState.statusMessage.isNotEmpty &&
        appState.connectionStatus == ConnectionStatus.connected) {
      parts.add(appState.statusMessage);
    }
    return parts.join(' ');
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
}
