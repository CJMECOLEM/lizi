/// Barcode scanning (mobile_scanner) and text recognition (camera) use two
/// different plugins for the same physical camera. A view that opens the
/// camera first waits until the previous view has finished releasing it, so
/// switching modes never has two sessions fighting over the device.
class CameraGate {
  CameraGate._();

  static Future<void> _released = Future.value();

  static Future<void> get released => _released;

  static void releasing(Future<void> done) {
    final previous = _released;
    _released = Future.wait([previous, done.catchError((Object _) {})]);
  }
}
