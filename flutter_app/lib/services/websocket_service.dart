import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class WsEvent {
  const WsEvent(this.data);

  final Map<String, dynamic> data;

  String get type => (data['type'] as String?) ?? '';
  String? get userId => data['userId'] as String?;
  String? get url => data['url'] as String?;
}

class WebsocketService {
  final StreamController<WsEvent> _controller = StreamController<WsEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  String _serverUrl = '';
  String _cookieHeader = '';

  Stream<WsEvent> get events => _controller.stream;

  Future<void> connect({
    required String serverUrl,
    required String cookieHeader,
  }) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _serverUrl = serverUrl;
    _cookieHeader = cookieHeader;
    _shouldReconnect = true;
    await _open();
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
  }

  Future<void> _open() async {
    await _subscription?.cancel();
    _subscription = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _socket?.close();
    _socket = null;

    final base = Uri.parse(_serverUrl);
    final wsUrl = base
        .replace(
          scheme: base.scheme == 'https' ? 'wss' : 'ws',
          path: '/api/ws',
          query: null,
          fragment: null,
        )
        .toString();

    try {
      _socket = await WebSocket.connect(
        wsUrl,
        headers: {HttpHeaders.cookieHeader: _cookieHeader},
      );
      _subscription = _socket!.listen(
        (message) {
          if (message is! String) {
            return;
          }
          try {
            final decoded = jsonDecode(message);
            if (decoded is Map<String, dynamic>) {
              _controller.add(WsEvent(decoded));
            }
          } catch (e, st) {
            debugPrint('WebSocket message parse failed: $e\n$st');
            return;
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: false,
      );
      _pingTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) {
          final socket = _socket;
          if (socket == null || socket.readyState != WebSocket.open) {
            _pingTimer?.cancel();
            _pingTimer = null;
            return;
          }
          try {
            socket.add('ping');
          } catch (_) {
            _pingTimer?.cancel();
            _pingTimer = null;
          }
        },
      );
    } catch (e, st) {
      debugPrint('WebSocket connection failed: $e\n$st');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _pingTimer?.cancel();
    _pingTimer = null;
    if (!_shouldReconnect || _reconnectTimer != null) {
      return;
    }
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      _reconnectTimer = null;
      if (_shouldReconnect) {
        await _open();
      }
    });
  }
}
