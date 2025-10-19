import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  const AuthService._();

  static Future<void> signIn({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static String errorMessage(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'user-not-found':
        return 'No user found for that email.';
      case 'wrong-password':
        return 'Invalid password.';
      default:
        return exception.message ?? 'Authentication failed';
    }
  }
}
