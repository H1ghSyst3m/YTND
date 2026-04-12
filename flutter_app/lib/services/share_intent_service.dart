import 'package:flutter/services.dart';

class ShareIntentService {
  static const MethodChannel _methodChannel = MethodChannel('ytnd/share_intent');
  static const EventChannel _eventChannel = EventChannel('ytnd/share_intent_events');

  late final Stream<String> _sharedTextStream = _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>()
      .map((event) => event.trim())
      .where((event) => event.isNotEmpty);

  Future<String?> getInitialSharedText() async {
    final value = await _methodChannel.invokeMethod<String>('getInitialSharedText');
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  Stream<String> get sharedTextStream => _sharedTextStream;
}
