import 'phone_launcher_stub.dart'
    if (dart.library.html) 'phone_launcher_web.dart'
    if (dart.library.io) 'phone_launcher_io.dart';

class PhoneLauncher {
  PhoneLauncher._();

  /// Attempts to open the platform dialer with the provided [phoneNumber].
  ///
  /// Returns `true` when the platform indicates the dialer could be opened,
  /// otherwise returns `false`.
  static Future<bool> launchDialer(String phoneNumber) async {
    final sanitized = phoneNumber.trim();
    if (sanitized.isEmpty) {
      return false;
    }

    return launchPhoneNumber(sanitized);
  }
}
