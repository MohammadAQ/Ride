import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class AuthService {
  const AuthService._();

  static Future<UserCredential> signIn({
    required String email,
    required String password,
    int maxRetries = 3,
  }) async {
    return _runWithNetworkRetries(
      maxRetries: maxRetries,
      operation: () => FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  static Future<UserCredential> signUp({
    required String email,
    required String password,
    int maxRetries = 3,
  }) async {
    return _runWithNetworkRetries(
      maxRetries: maxRetries,
      operation: () => FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      ),
    );
  }

  static Future<T> _runWithNetworkRetries<T>({
    required int maxRetries,
    required Future<T> Function() operation,
  }) async {
    FirebaseAuthException? lastException;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } on FirebaseAuthException catch (e) {
        lastException = e;
        final isNetworkError = e.code == 'network-request-failed';
        if (!isNetworkError || attempt == maxRetries) {
          rethrow;
        }

        final backoffMilliseconds = 400 * (attempt + 1);
        final delay = backoffMilliseconds.clamp(400, 2000).toInt();
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }

    throw lastException ??
        FirebaseAuthException(
          code: 'network-request-failed',
          message: 'Network error. Check your connection and try again.',
        );
  }

  static Future<void> handleSuccessfulSignIn(BuildContext context) async {
    await _redirectToRoot(context);
  }

  @Deprecated('Use handleSuccessfulSignIn instead')
  static Future<void> navigateToAuthRoot(BuildContext context) async {
    await _redirectToRoot(context);
  }

  static Future<void> _redirectToRoot(BuildContext context) async {
    final navigator = _navigatorFor(context);
    if (navigator == null || !navigator.mounted) {
      return;
    }

    // Defer navigation changes to the next microtask so current UI work can
    // settle before we manipulate the stack. This avoids lifecycle exceptions
    // that can occur if we navigate synchronously while widgets are still
    // building.
    await Future<void>.delayed(Duration.zero);

    if (!navigator.mounted) return;
    navigator.pushNamedAndRemoveUntil('/', (route) => false);
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
