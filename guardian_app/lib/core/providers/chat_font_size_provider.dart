import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kKey = 'chat_font_size';

/// Available font size steps for chat messages.
const chatFontSizeSteps = [13.0, 15.0, 17.0, 19.0];

/// Default font size (medium).
const chatFontSizeDefault = 15.0;

Future<double> loadSavedChatFontSize() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble(_kKey) ?? chatFontSizeDefault;
}

class ChatFontSizeNotifier extends Notifier<double> {
  ChatFontSizeNotifier([this._initial = chatFontSizeDefault]);
  final double _initial;

  @override
  double build() => _initial;

  Future<void> set(double size) async {
    state = size;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kKey, size);
  }
}

final chatFontSizeProvider =
    NotifierProvider<ChatFontSizeNotifier, double>(ChatFontSizeNotifier.new);
