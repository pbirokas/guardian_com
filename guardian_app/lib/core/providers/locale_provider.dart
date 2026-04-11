import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'appLocale';

class LocaleNotifier extends AsyncNotifier<Locale> {
  @override
  Future<Locale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    return switch (code) {
      'en' => const Locale('en'),
      _ => const Locale('de'),
    };
  }

  Future<void> setLocale(Locale locale) async {
    state = AsyncData(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLocaleKey, locale.languageCode);
  }
}

final localeProvider = AsyncNotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);
