import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kScaleKey = 'ui_scale_factor';

/// Available UI scale steps shown in the settings UI.
const uiScaleSteps = [1.0, 1.25, 1.5, 1.75, 2.0];

/// Loads the persisted scale factor from SharedPreferences.
/// Returns 1.0 if nothing was saved yet.
Future<double> loadSavedScaleFactor() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getDouble(_kScaleKey) ?? 1.0;
}

class ScaleFactorNotifier extends Notifier<double> {
  ScaleFactorNotifier([this._initial = 1.0]);
  final double _initial;

  @override
  double build() => _initial;

  Future<void> set(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kScaleKey, scale);
  }
}

final scaleFactorProvider =
    NotifierProvider<ScaleFactorNotifier, double>(ScaleFactorNotifier.new);
