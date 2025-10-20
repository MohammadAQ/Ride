import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channelName = 'com.example.carpal_app/phone_launcher';
const MethodChannel _channel = MethodChannel(_channelName);

Future<bool> launchPhoneNumber(String phoneNumber) async {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return false;
  }

  try {
    final result = await _channel.invokeMethod<bool>(
      'openDialer',
      <String, dynamic>{'phoneNumber': phoneNumber},
    );
    return result ?? false;
  } on MissingPluginException catch (_) {
    return false;
  } on PlatformException {
    return false;
  }
}
