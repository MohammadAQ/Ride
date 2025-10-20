// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> launchPhoneNumber(String phoneNumber) async {
  final telUrl = 'tel:$phoneNumber';
  try {
    html.window.location.href = telUrl;
    return true;
  } catch (_) {
    return false;
  }
}
