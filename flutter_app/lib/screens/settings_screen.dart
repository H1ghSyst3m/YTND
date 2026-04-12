import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final folder = await FilePicker.platform.getDirectoryPath();
    if (folder != null && mounted) {
      setState(() {
        _storageController.text = folder;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final appState = context.read<AppState>();
    final existing = appState.settings;
    final next = existing.copyWith(
      serverUrl: _serverController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      syncIntervalHours: _syncInterval,
      syncWifiOnly: _syncWifiOnly,
      storagePath: _storageController.text.trim(),
    );

    try {
      await appState.saveSettings(next);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _serverController,
              decoration: const InputDecoration(labelText: 'Server URL'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Server URL is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Username is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Password is required'
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _syncInterval,
              decoration: const InputDecoration(labelText: 'Sync interval'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Manual only')),
                DropdownMenuItem(value: 1, child: Text('Every 1 hour')),
                DropdownMenuItem(value: 2, child: Text('Every 2 hours')),
                DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _syncInterval = value;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sync only on WiFi'),
              subtitle: _syncInterval == 0 ? const Text('Not applicable for manual sync') : null,
              value: _syncWifiOnly,
              onChanged: _syncInterval == 0
                  ? null
                  : (value) {
                      setState(() {
                        _syncWifiOnly = value;
                      });
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _storageController,
              decoration: const InputDecoration(
                labelText: 'Storage path',
                helperText: 'Default: /storage/emulated/0/Music/YTND',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Storage path is required'
                  : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _pickFolder,
              child: const Text('Choose storage folder'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}
