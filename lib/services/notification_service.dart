import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import '../main.dart';
import '../models/models.dart';
import '../screens/add_transaction_screen.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM] Background message received');
  debugPrint('[FCM] Title: ${message.notification?.title}');
  debugPrint('[FCM] Body: ${message.notification?.body}');
  debugPrint('[FCM] Data: ${message.data}');
  await NotificationService.instance.setupLocalNotifications();
  await NotificationService.instance.showNotification(message);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    await _requestPermission();
    await setupLocalNotifications();
    _setupMessageHandlers();

    final token = await _messaging.getToken();
    debugPrint('FCM Token: $token');

    if (token != null) {
      await _registerTokenWithServer(token);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed: $newToken');
      _registerTokenWithServer(newToken);
    });

    _isInitialized = true;
  }

  /// Register or update the FCM token on the backend
  Future<void> _registerTokenWithServer(String token) async {
    try {
      final deviceName = _getDeviceName();
      final uri = Uri.parse('${ApiService.baseUrl}/fcm-tokens');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceName': deviceName,
          'token': token,
        }),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('[FCM] Token registered for device: $deviceName');
      } else {
        debugPrint('[FCM] Failed to register token: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[FCM] Error registering token: $e');
    }
  }

  String _getDeviceName() {
    if (Platform.isAndroid) return 'Android Device';
    if (Platform.isIOS) return 'iOS Device';
    if (Platform.isMacOS) return 'macOS Device';
    return 'Unknown Device';
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('Notification permission: ${settings.authorizationStatus}');
  }

  Future<void> setupLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  void _setupMessageHandlers() {
    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message received');
      debugPrint('[FCM] Title: ${message.notification?.title}');
      debugPrint('[FCM] Body: ${message.notification?.body}');
      debugPrint('[FCM] Data: ${message.data}');
      showNotification(message);
    });

    // When app is opened from a notification (background state)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // When app is opened from a terminated state via notification
    _messaging.getInitialMessage().then((message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });
  }

  Future<void> showNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription:
              'This channel is used for important notifications.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('Notification tapped with data: $data');
      final tnxId = data['tnxId'] as String?;
      if (tnxId != null) {
        _navigateToTransaction(tnxId);
      }
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification opened app with data: ${message.data}');
    final tnxId = message.data['tnxId'] as String?;
    if (tnxId != null) {
      _navigateToTransaction(tnxId);
    }
  }

  void _navigateToTransaction(String tnxId) async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final context = nav.overlay?.context;
    if (context == null) return;

    // Show loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final data = await ApiService().getTransactionById(tnxId);
      final txJson = data['transaction'] ?? data;
      final tx = TransactionModel.fromJson(
        txJson is Map<String, dynamic> ? txJson : data,
      );
      // Dismiss loader
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => AddTransactionScreen(prefill: tx, isEdit: true, fromNotification: true),
        ),
      );
    } catch (e) {
      // Dismiss loader
      nav.pop();
      debugPrint('[FCM] Failed to fetch transaction $tnxId: $e');
    }
  }
}
