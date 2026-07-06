import 'package:flutter/services.dart';

import 'shared_url_parser.dart';

class ShareIntentService {
  static const MethodChannel _methodChannel = MethodChannel('ytnd/share_intent');
  static const EventChannel _eventChannel = EventChannel('ytnd/share_intent_events');

  late final Stream<List<String>> _sharedUrlStream = _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>()
      .map(SharedUrlParser.extractYoutubeUrls)
      .where((urls) => urls.isNotEmpty);

  Future<List<String>> getInitialSharedUrls() async {
    final value = await _methodChannel.invokeMethod<String>('getInitialSharedText');
    if (value == null || value.trim().isEmpty) {
      return const <String>[];
    }
    return SharedUrlParser.extractYoutubeUrls(value);
  }

  Stream<List<String>> get sharedUrlStream => _sharedUrlStream;
}
