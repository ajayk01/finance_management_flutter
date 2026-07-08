import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Load environment variables (required first)
      await dotenv.load();

      // Start Firebase, Notifications, and Auth in background.
      unawaited(
        Future.wait([
          _initFirebase(),
          _initNotifications(),
          _initAuth(),
        ], eagerError: false).then((_) {
          NotificationService.instance.processPendingNotifications();
        }).catchError((Object e, StackTrace st) {
          debugPrint('Background initialization error: $e');
        }),
      );

      // Navigate to HomeScreen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      // Still navigate even if initialization fails
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp();
      debugPrint('Firebase initialized');
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
  }

  Future<void> _initNotifications() async {
    try {
      await NotificationService.instance.initialize();
      debugPrint('Notifications initialized');
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }

  Future<void> _initAuth() async {
    try {
      final api = ApiService();
      await api.loadCookie();
      debugPrint('Cookie loaded');

      bool isLoggedIn = false;
      try {
        final session = await api.checkSession();
        isLoggedIn = session['isLoggedIn'] == true;
        debugPrint('Session checked: isLoggedIn=$isLoggedIn');
      } catch (e) {
        debugPrint('Session check failed: $e');
      }

      // Only login if not already logged in
      if (!isLoggedIn) {
        try {
          await api.login('Ajay', '1q2w3e4r5t-');
          debugPrint('Auto-login successful');
        } catch (e) {
          debugPrint('Auto-login failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Auth init error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A6C),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo or App Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.trending_up,
                size: 50,
                color: Color(0xFF1A1A6C),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'Finance App',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading your data...',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            // Loading indicator
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withOpacity(0.8),
                ),
                strokeWidth: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
