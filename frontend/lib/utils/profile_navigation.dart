import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ride/models/user_profile.dart';
import 'package:ride/screens/profile_screen.dart';

class ProfileNavigation {
  const ProfileNavigation._();

  static Future<void> pushProfile({
    required BuildContext context,
    required String? userId,
    UserProfile? initialProfile,
  }) {
    final String? trimmedId = userId?.trim();
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if ((trimmedId == null || trimmedId.isEmpty) && currentUser == null) {
      return Future<void>.value();
    }

    final bool isCurrentUser =
        currentUser != null && trimmedId != null && trimmedId == currentUser.uid;

    final Route<void> route = PageRouteBuilder<void>(
      pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        return ProfileScreen(
          userId: isCurrentUser ? null : trimmedId,
          initialProfile: initialProfile,
        );
      },
      transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget child,
      ) {
        final Animation<Offset> offsetAnimation = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
        );
        return SlideTransition(
          position: offsetAnimation,
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 280),
    );

    return Navigator.of(context).push(route);
  }
}
