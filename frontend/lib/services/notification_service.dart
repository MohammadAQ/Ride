import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import '../screens/ride_details_screen.dart';

/// Wires Firebase Cloud Messaging with local notifications across the app.
///
/// Added behaviour:
/// * Requests notification permissions on iOS/macOS and configures foreground
///   presentation so alerts appear even while using the app.
/// * Shows a local notification when an FCM message arrives in the foreground
///   (Android/iOS) using `flutter_local_notifications`.
/// * Persists the device token in `users/{uid}.fcmTokens` so backend Cloud
///   Functions can fan-out messages.
/// * Handles taps from background/terminated notifications via the data payload
///   (`route`, `tripId`) and routes to the Ride Details screen.
///
/// Manual testing checklist:
/// 1. Sign in → token is stored in Firestore under the user document.
/// 2. Create a booking from another device/account → driver receives the push in
///    the background and as a heads-up if the app is open.
/// 3. Confirm the booking as the driver → passenger receives the notification.
/// 4. Cancel the booking → the other party receives a cancellation alert.
/// 5. Tap the notification (cold start & background) → app opens Trip Details
///    for the provided `tripId`.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _functionsRegion = 'us-central1';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _currentUserId;
  bool _initialized = false;
  Map<String, dynamic>? _pendingNavigationData;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'ride_high_importance',
    'Ride updates',
    description: 'Notifications about trip bookings and status changes.',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      provisional: false,
      criticalAlert: false,
    );

    await _requestAndroidNotificationPermission();

    if (kDebugMode) {
      debugPrint('Notification permission status: '
          '${settings.authorizationStatus.name}');
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
      // The permission dialog is handled by Firebase Messaging to avoid
      // duplicate prompts.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotificationsPlugin.initialize(
      const InitializationSettings(
        android: androidInitializationSettings,
        iOS: iosInitializationSettings,
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        handleNotificationTapPayload(response.payload);
      },
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      unawaited(_handleForegroundMessage(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(_handleRouteNavigation(message.data));
    });

    final RemoteMessage? initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _pendingNavigationData = Map<String, dynamic>.from(initialMessage.data);
    }
  }

  Future<void> handlePendingNavigation() async {
    if (_pendingNavigationData == null) {
      return;
    }
    final Map<String, dynamic> data = _pendingNavigationData!;
    _pendingNavigationData = null;
    await _handleRouteNavigation(data);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    if (notification == null) {
      return;
    }

    final String payload = jsonEncode(<String, String>{
      'route': message.data['route']?.toString() ?? '',
      'tripId': message.data['tripId']?.toString() ?? '',
    });

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_notification',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    await _localNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: payload,
    );
  }

  void handleNotificationTapPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final Map<String, dynamic> data =
          jsonDecode(payload) as Map<String, dynamic>;
      unawaited(_handleRouteNavigation(data));
    } on FormatException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Invalid notification payload: $error\n$stackTrace');
      }
    }
  }

  Future<void> _handleRouteNavigation(Map<String, dynamic> data) async {
    final String route = data['route']?.toString() ?? '';
    if (route.isEmpty) {
      return;
    }

    switch (route) {
      case 'trip_details':
        final String tripId = data['tripId']?.toString() ?? '';
        if (tripId.isEmpty) {
          return;
        }

        final NavigatorState? navigator = navigatorKey.currentState;
        if (navigator == null || !navigator.mounted) {
          _pendingNavigationData = Map<String, dynamic>.from(data);
          return;
        }

        await _openTripDetails(navigator, tripId);
        break;
      default:
        if (kDebugMode) {
          debugPrint('Unhandled notification route: $route');
        }
    }
  }

  Future<void> _openTripDetails(NavigatorState navigator, String tripId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('trips')
          .doc(tripId)
          .get();

      if (!snapshot.exists) {
        _showSnackBar(
          navigator,
          'تعذر العثور على تفاصيل الرحلة الحالية.',
        );
        return;
      }

      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};

      final RideDetailsArguments arguments = RideDetailsArguments(
        tripId: tripId,
        fromCity: _asString(data['fromCity']),
        toCity: _asString(data['toCity']),
        tripDate: _asString(data['date']),
        tripTime: _asString(data['time']),
        driverName: _asString(data['driverName']),
        availableSeats: _asInt(data['availableSeats']),
        price: _asString(data['price']),
        driverId: _stringOrNull(data['driverId']),
        carModel: _stringOrNull(data['carModel']),
        carColor: _stringOrNull(data['carColor']),
        createdAt: _asDateTime(data['createdAt']),
      );

      navigator.push(
        MaterialPageRoute<Widget>(
          builder: (BuildContext context) =>
              RideDetailsScreen(arguments: arguments),
        ),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to open trip details for $tripId: '
            '$error\n$stackTrace');
      }

      _showSnackBar(
        navigator,
        'حدث خطأ أثناء فتح تفاصيل الرحلة. حاول مرة أخرى.',
      );
    }
  }

  void _showSnackBar(NavigatorState navigator, String message) {
    final BuildContext context = navigator.context;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showGlobalSnackBar(String message) {
    final NavigatorState? navigator = navigatorKey.currentState;
    final BuildContext? context = navigator?.context;
    if (context == null) {
      if (kDebugMode) {
        debugPrint('Snackbar requested but context was null: $message');
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> saveToken(String uid) async {
    final String trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      return;
    }

    _currentUserId = trimmedUid;

    try {
      final String? token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistToken(trimmedUid, token);
        if (kDebugMode) {
          final String preview = token.length > 12 ? '${token.substring(0, 12)}…' : token;
          debugPrint('Saved FCM token for $trimmedUid ($preview)');
        }
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to fetch FCM token: $error\n$stackTrace');
      }
    }

    _tokenRefreshSubscription ??=
        _messaging.onTokenRefresh.listen((String refreshedToken) {
      final String? activeUserId = _currentUserId;
      if (activeUserId == null || activeUserId.isEmpty) {
        return;
      }
      unawaited(_persistToken(activeUserId, refreshedToken));
      if (kDebugMode) {
        final String preview =
            refreshedToken.length > 12 ? '${refreshedToken.substring(0, 12)}…' : refreshedToken;
        debugPrint('Refreshed FCM token for $activeUserId ($preview)');
      }
    });
  }

  Future<void> _persistToken(String uid, String token) async {
    final DocumentReference<Map<String, dynamic>> userDoc =
        _firestore.collection('users').doc(uid);

    try {
      await userDoc.set(
        <String, dynamic>{
          'fcmTokens': <String, dynamic>{token: true},
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to persist FCM token for $uid: '
            '$error\n$stackTrace');
      }
    }
  }

  Future<void> sendTestNotification() async {
    try {
      final String? token = await _messaging.getToken();
      if (token == null || token.isEmpty) {
        _showGlobalSnackBar('لم يتم العثور على رمز الإشعار لهذا الجهاز.');
        return;
      }

      final Map<String, dynamic> data = await _callHttpsCallable(
        'sendTestNotification',
        <String, dynamic>{'token': token},
      );
      final int targetCount = (data['targetCount'] as num?)?.toInt() ?? 0;
      final int successCount = (data['successCount'] as num?)?.toInt() ?? 0;
      final int failureCount = (data['failureCount'] as num?)?.toInt() ?? 0;

      _showGlobalSnackBar(
        'تم إرسال الإشعار التجريبي ($successCount من $targetCount، أخطاء: $failureCount).',
      );
    } on NotificationServiceException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('sendTestNotification failed: $error\n$stackTrace');
      }
      final String message = error.message.trim();
      _showGlobalSnackBar(
        message.isEmpty
            ? 'تعذّر إرسال الإشعار التجريبي.'
            : 'تعذّر إرسال الإشعار التجريبي: $message.',
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('sendTestNotification unexpected error: $error\n$stackTrace');
      }
      _showGlobalSnackBar('تعذّر إرسال الإشعار التجريبي. حاول مرة أخرى لاحقًا.');
    }
  }

  Future<Map<String, dynamic>> _callHttpsCallable(
    String functionName,
    Map<String, dynamic> payload,
  ) async {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw const NotificationServiceException(
        code: 'unauthenticated',
        message: 'يجب تسجيل الدخول أولًا.',
      );
    }

    final String? idToken = await user.getIdToken();
    if (idToken == null) {
      throw const NotificationServiceException(
        code: 'missing-id-token',
        message: 'فشل الحصول على رمز هوية المستخدم.',
      );
    }
    final FirebaseApp app = Firebase.app();
    final String projectId = app.options.projectId ?? '';
    if (projectId.isEmpty) {
      throw const NotificationServiceException(
        code: 'missing-project-id',
        message: 'معرّف مشروع Firebase غير مهيأ.',
      );
    }

    final Uri uri = Uri.https(
      '$_functionsRegion-$projectId.cloudfunctions.net',
      functionName,
    );

    final http.Response response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(<String, dynamic>{'data': payload}),
    );

    Map<String, dynamic> decodedBody;
    try {
      decodedBody = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw NotificationServiceException(
        code: response.statusCode.toString(),
        message: 'استجابة غير صالحة من الدالة السحابية.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Object? result = decodedBody['result'];
      if (result is Map<dynamic, dynamic>) {
        return result.map(
          (dynamic key, dynamic value) =>
              MapEntry<String, dynamic>(key.toString(), value),
        );
      }
      if (result is Map<String, dynamic>) {
        return result;
      }
      return <String, dynamic>{};
    }

    final Map<String, dynamic> error =
        _asStringKeyedMap(decodedBody['error']) ?? <String, dynamic>{};
    final String message = error['message']?.toString() ??
        'فشل استدعاء الدالة السحابية (HTTP ${response.statusCode}).';
    final String code = error['status']?.toString() ??
        response.statusCode.toString();
    throw NotificationServiceException(code: code, message: message);
  }

  Map<String, dynamic>? _asStringKeyedMap(Object? input) {
    if (input is Map<String, dynamic>) {
      return input;
    }
    if (input is Map) {
      return input.map(
        (dynamic key, dynamic value) =>
            MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return null;
  }

  Future<void> _requestAndroidNotificationPermission() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation == null) {
      return;
    }

    final bool? granted =
        await androidImplementation.requestNotificationsPermission();
    if (kDebugMode) {
      debugPrint('Android notification permission granted: $granted');
    }
  }

  String _asString(dynamic value) {
    if (value == null) {
      return 'غير متاح';
    }
    if (value is String) {
      final String trimmed = value.trim();
      return trimmed.isEmpty ? 'غير متاح' : trimmed;
    }
    return value.toString();
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class NotificationServiceException implements Exception {
  const NotificationServiceException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() =>
      'NotificationServiceException(code: $code, message: $message)';
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (kDebugMode) {
    debugPrint('Handling background message ${message.messageId}');
  }
}
