import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static late final AppSettings instance;

  static Future<void> load() async {
    instance = AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  bool get autoTorch => _prefs.getBool('autoTorch') ?? true;
  set autoTorch(bool v) {
    _prefs.setBool('autoTorch', v);
    notifyListeners();
  }

  bool get vibrate => _prefs.getBool('vibrate') ?? true;
  set vibrate(bool v) {
    _prefs.setBool('vibrate', v);
    notifyListeners();
  }
}
