import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AuthService {
  const AuthService._();

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static void handleSuccessfulSignIn(BuildContext context) {
    final navigator = _navigatorFor(context);
    if (navigator == null || !navigator.mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!navigator.mounted) return;
      navigator.popUntil((route) => route.isFirst);
    });
  }

  @Deprecated('Use handleSuccessfulSignIn instead')
  static void navigateToAuthRoot(BuildContext context) {
    handleSuccessfulSignIn(context);
  }

  static NavigatorState? _navigatorFor(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    if (navigator != null) {
      return navigator;
    }

    try {
      return Navigator.of(context, rootNavigator: true);
    } on FlutterError {
      return null;
    }
  }

  static String errorMessage(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Invalid password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'invalid-credential':
      case 'user-disabled':
        return 'Invalid email or password.';
      default:
        return exception.message ?? 'Authentication failed';
    }
  }
}
