import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _serverController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _storageController;
  late int _syncInterval;
  late bool _syncWifiOnly;
  bool _obscurePassword = true;

  static const List<int> _syncIntervals = [0, 1, 2, 6, 12];

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppState>().settings;
    _serverController = TextEditingController(text: settings.serverUrl);
    _usernameController = TextEditingController(text: settings.username);
    _passwordController = TextEditingController(text: settings.password);
    _storageController = TextEditingController(text: settings.storagePath);
    _syncInterval = _syncIntervals.contains(settings.syncIntervalHours)
        ? settings.syncIntervalHours
        : _syncIntervals.first;
    _syncWifiOnly = settings.syncWifiOnly;
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _storageController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final folder = await FilePicker.getDirectoryPath();
    if (folder != null && mounted) {
      setState(() => _storageController.text = folder);
    }
  }

  AppSettings _buildSettings(AppState appState) {
    return appState.settings.copyWith(
      serverUrl: _serverController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      syncIntervalHours: _syncInterval,
      syncWifiOnly: _syncWifiOnly,
      storagePath: _storageController.text.trim(),
    );
  }

  Future<bool> _confirmHttpServerIfNeeded() async {
    late final String normalizedServerUrl;
    try {
      normalizedServerUrl = normalizeServerUrl(_serverController.text);
    } on ApiException {
      return true;
    }

    if (Uri.parse(normalizedServerUrl).scheme != 'http') {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use HTTP server?'),
        content: const Text(
          'HTTP is not encrypted. Your username and password may be visible '
          'on the network. Only continue for a trusted local server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _confirmHttpServerIfNeeded()) return;
    if (!mounted) return;
    final appState = context.read<AppState>();
    try {
      final saved = await appState.saveSettings(_buildSettings(appState));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saved ? 'Settings saved' : appState.statusMessage),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appState.statusMessage)));
      }
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    if (!await _confirmHttpServerIfNeeded()) return;
    if (!mounted) return;
    final appState = context.read<AppState>();
    try {
      final signedIn = await appState.login(
        serverUrl: _serverController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              signedIn ? 'Connected to YTND' : appState.statusMessage,
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appState.statusMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _ConnectionCard(appState: appState),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Server account',
                icon: Icons.dns_outlined,
                children: [
                  TextFormField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://ytnd.example.com',
                      prefixIcon: Icon(Icons.public),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Server URL is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Username is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Password is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: appState.isAuthenticating ? null : _signIn,
                          icon: appState.isAuthenticating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            appState.isAuthenticated ? 'Reconnect' : 'Sign in',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.outlined(
                        tooltip: 'Save without connecting',
                        onPressed: appState.isSavingSettings ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SettingsSection(
                title: 'Sync and storage',
                icon: Icons.sync_outlined,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _syncInterval,
                    decoration: const InputDecoration(
                      labelText: 'Background sync interval',
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Manual only')),
                      DropdownMenuItem(value: 1, child: Text('Every 1 hour')),
                      DropdownMenuItem(value: 2, child: Text('Every 2 hours')),
                      DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                      DropdownMenuItem(
                        value: 12,
                        child: Text('Every 12 hours'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _syncInterval = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sync only on WiFi'),
                    subtitle: _syncInterval == 0
                        ? const Text('Not used for manual sync')
                        : null,
                    value: _syncWifiOnly,
                    onChanged: _syncInterval == 0
                        ? null
                        : (value) => setState(() => _syncWifiOnly = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storageController,
                    decoration: const InputDecoration(
                      labelText: 'Storage path',
                      helperText: 'Default: /storage/emulated/0/Music/YTND',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Storage path is required'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                          label: const Text('Choose folder'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: appState.isSavingSettings ? null : _save,
                          icon: appState.isSavingSettings
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (appState.pendingShareCount > 0) ...[
                const SizedBox(height: 12),
                _SettingsSection(
                  title: 'Pending shared links',
                  icon: Icons.pending_actions,
                  children: [
                    Text(
                      '${appState.pendingShareCount} link(s) will be added after sign-in.',
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed:
                          appState.isAuthenticated && !appState.isAddingToQueue
                          ? appState.retryPendingShareUrls
                          : null,
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Add pending links'),
                    ),
                  ],
                ),
              ],
              if (appState.isAuthenticated) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: appState.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colorForStatus(scheme, appState.connectionStatus);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconForStatus(appState.connectionStatus), color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appState.connectionTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  appState.connectionMessage,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (appState.connectionStatus == ConnectionStatus.unreachable)
            TextButton.icon(
              onPressed: appState.retryConnection,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  IconData _iconForStatus(ConnectionStatus status) {
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

  Color _colorForStatus(ColorScheme scheme, ConnectionStatus status) {
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

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

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
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
