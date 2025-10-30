import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashTransitionPlaceholder();
        }

        if (snapshot.hasData) {
          final User? user = snapshot.data;
          if (user != null) {
            NotificationService.instance.saveToken(user.uid);
            NotificationService.instance.handlePendingNavigation();
          }
          return const HomeScreen();
        } else {
          return const AuthScreen();
        }
      },
    );
  }
}

class _SplashTransitionPlaceholder extends StatelessWidget {
  const _SplashTransitionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF001F3F), Color(0xFF00BFA5)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}
