import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// Deep link payload from push notification data
class PushDeepLink {
  final String scheme;   // e.g. "app"
  final String host;    // e.g. "owner" or "seeker"
  final String path;    // e.g. "job/123" or "applications"
  final Map<String, String> data; // jobId, applicationId, etc.

  PushDeepLink({
    required this.scheme,
    required this.host,
    required this.path,
    this.data = const {},
  });

  /// Parse deepLink string e.g. "app://owner/job/123" or "app://seeker/applications"
  static PushDeepLink? parse(String? deepLink) {
    if (deepLink == null || deepLink.isEmpty) return null;
    final uri = Uri.tryParse(deepLink);
    if (uri == null) return null;
    final data = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      if (v != null) data[k] = v;
    });
    return PushDeepLink(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
      data: data,
    );
  }
}

/// Handles FCM init, token registration, and deep link from notification taps.
/// Call [initialize] from main() after WidgetsFlutterBinding.ensureInitialized().
/// Call [registerTokenIfLoggedIn] after login or when app becomes active with a logged-in user.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final AuthService _auth = AuthService();
  final ApiService _api = ApiService();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  /// Stream of deep links when user opens a notification (background or terminated).
  static final StreamController<PushDeepLink> _deepLinkController =
      StreamController<PushDeepLink>.broadcast();
  static Stream<PushDeepLink> get onDeepLink => _deepLinkController.stream;

  /// Pending deep link from getInitialMessage (app was terminated).
  /// Home screens check this in initState and clear after handling.
  static PushDeepLink? _pendingDeepLink;
  static PushDeepLink? getAndClearPendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  bool _initialized = false;

  /// Initialize FCM handlers. Call once from main() after Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Firebase already initialized in main() with DefaultFirebaseOptions.currentPlatform
      _initialized = true;

      // Foreground: show in-app or silent
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // User tapped notification while app in background
      FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpenedApp);

      // User opened app from notification tap (app was terminated)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        final link = _parseDeepLink(initialMessage.data['deepLink'] as String?);
        if (link != null) {
          _pendingDeepLink = link;
          _deepLinkController.add(link);
        }
      }

      // Register token if user already logged in (e.g. app restarted)
      await registerTokenIfLoggedIn();
    } catch (e) {
      debugPrint('PushNotificationService init error: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    // Optional: show in-app banner or update UI
    debugPrint('Push foreground: ${message.notification?.title}');
    // You can also add a local notification here if desired
  }

  void _onNotificationOpenedApp(RemoteMessage message) {
    final link = _parseDeepLink(message.data['deepLink'] as String?);
    if (link != null) _deepLinkController.add(link);
  }

  static PushDeepLink? _parseDeepLink(String? s) => PushDeepLink.parse(s);

  /// Request permission (iOS) and get FCM token, then register with backend if user is logged in.
  Future<void> registerTokenIfLoggedIn() async {
    try {
      final token = await getAccessToken();
      if (token == null || token.isEmpty) return;

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final fcmToken = await _messaging.getToken();
      if (fcmToken == null || fcmToken.isEmpty) return;

      final platform = Platform.isIOS ? 'ios' : 'android';
      final res = await _api.registerFcmDevice(fcmToken: fcmToken, platform: platform);
      if (!res.success) {
        debugPrint('Push register failed: ${res.message}');
      }
    } catch (e) {
      debugPrint('Push registerTokenIfLoggedIn error: $e');
    }
  }

  /// Call on logout to deactivate token on server.
  Future<void> unregisterToken() async {
    try {
      final fcmToken = await _messaging.getToken();
      await _api.unregisterFcmDevice(fcmToken: fcmToken);
    } catch (e) {
      debugPrint('Push unregister error: $e');
    }
  }

  Future<String?> getAccessToken() => _auth.getAccessToken();
}

/// Required for background message handler (optional; use if you need to handle data-only in background).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Optional: handle data in background
}
