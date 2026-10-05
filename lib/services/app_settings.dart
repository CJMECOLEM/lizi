import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs);

  static late final AppSettings instance;

  static Future<void> load() async {
    instance = AppSettings._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _prefs;

  /// Keeps the torch on while the camera is scanning; it goes off with the
  /// camera whenever the scan tab is left or the app goes to the background.
  bool get torchWhileScanning => _prefs.getBool('torchWhileScanning') ?? true;
  set torchWhileScanning(bool v) {
    _prefs.setBool('torchWhileScanning', v);
    notifyListeners();
  }

  bool get vibrate => _prefs.getBool('vibrate') ?? true;
  set vibrate(bool v) {
    _prefs.setBool('vibrate', v);
    notifyListeners();
  }

  bool get beep => _prefs.getBool('beep') ?? true;
  set beep(bool v) {
    _prefs.setBool('beep', v);
    notifyListeners();
  }

  /// Whether shelf-life checks start by scanning the product barcode.
  bool get expiryScanBarcode => _prefs.getBool('expiryScanBarcode') ?? true;
  set expiryScanBarcode(bool v) {
    _prefs.setBool('expiryScanBarcode', v);
    notifyListeners();
  }

  /// The sheet new scans are counted into.
  int? get currentSheetId => _prefs.getInt('currentSheetId');
  set currentSheetId(int? v) {
    if (v == null) {
      _prefs.remove('currentSheetId');
    } else {
      _prefs.setInt('currentSheetId', v);
    }
    notifyListeners();
  }
}
