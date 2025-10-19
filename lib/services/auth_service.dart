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

  static Future<void> handleSuccessfulSignIn(BuildContext context) async {
    final navigator = _navigatorFor(context);
    if (navigator == null || !navigator.mounted) {
      return;
    }

    // Defer navigation changes to the next microtask so current UI work can
    // settle before we manipulate the stack. This avoids lifecycle exceptions
    // that can occur if we pop synchronously while widgets are still building.
    await Future<void>.delayed(Duration.zero);

    if (!navigator.mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }

  @Deprecated('Use handleSuccessfulSignIn instead')
  static Future<void> navigateToAuthRoot(BuildContext context) {
    return handleSuccessfulSignIn(context);
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
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return exception.message ?? 'Authentication failed';
    }
  }
}
