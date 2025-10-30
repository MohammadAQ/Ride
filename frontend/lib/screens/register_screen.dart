import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ride/screens/main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    UserCredential? userCredential;
    DocumentReference<Map<String, dynamic>>? phoneNumberReservationRef;
    bool phoneNumberReserved = false;

    try {
      final String trimmedPhone = _phoneController.text.trim();

      // Check Firestore for an existing user with the same phone number to enforce uniqueness.
      final QuerySnapshot<Map<String, dynamic>> existingPhoneSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: trimmedPhone)
              .limit(1)
              .get();

      if (existingPhoneSnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This phone number is already registered.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await userCredential.user?.updateDisplayName(
        _fullNameController.text.trim(),
      );

      final User? user = userCredential.user;

      if (user != null) {
        final CollectionReference<Map<String, dynamic>> phoneNumbersCollection =
            FirebaseFirestore.instance.collection('phoneNumbers');
        phoneNumberReservationRef = phoneNumbersCollection.doc(trimmedPhone);

        // Reserve the phone number document before writing the user profile. Using
        // the phone number as the document ID makes the transaction fail if
        // another user claimed it first, preventing duplicates even under race
        // conditions.
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final DocumentSnapshot<Map<String, dynamic>> snapshot =
              await transaction.get(phoneNumberReservationRef!);
          if (snapshot.exists) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'already-exists',
              message: 'Phone number already reserved.',
            );
          }

          transaction.set(
            phoneNumberReservationRef!,
            <String, dynamic>{'userId': user.uid},
          );
        });
        phoneNumberReserved = true;

        // Save the newly registered user's profile, including the verified phone
        // number, to Firestore. Because the phone number is reserved in its own
        // collection, we have a durable guarantee that no two profiles share it.
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          <String, dynamic>{
            'displayName': _fullNameController.text.trim(),
            'name': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'phoneNumber': trimmedPhone,
            'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } on FirebaseException catch (e) {
      if (userCredential?.user != null) {
        await _rollbackFailedRegistration(
          userCredential!.user!,
          phoneNumberRef: phoneNumberReservationRef,
          phoneNumberReserved: phoneNumberReserved,
        );
      }

      String message = 'Something went wrong. Please try again later.';
      if (e.plugin == 'cloud_firestore' && e.code == 'already-exists') {
        message = 'This phone number is already registered.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      var message = 'Unable to register. Please try again.';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered.';
      } else if (e.code == 'invalid-email') {
        message = 'Please enter a valid email address.';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak. Please choose a stronger password.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (_) {
      if (userCredential?.user != null) {
        await _rollbackFailedRegistration(
          userCredential!.user!,
          phoneNumberRef: phoneNumberReservationRef,
          phoneNumberReserved: phoneNumberReserved,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again later.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required.';
    }
    // Enforce Palestinian phone numbers that start with 059/056 and contain exactly 10 digits.
    final RegExp phoneRegex = RegExp(r'^(059|056)[0-9]{7}$');
    if (!phoneRegex.hasMatch(value.trim())) {
      return 'Please enter a valid phone number (e.g., 0591234567 or 0569876543).';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required.';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }

  Future<void> _rollbackFailedRegistration(
    User user, {
    DocumentReference<Map<String, dynamic>>? phoneNumberRef,
    required bool phoneNumberReserved,
  }) async {
    if (phoneNumberReserved && phoneNumberRef != null) {
      try {
        await phoneNumberRef.delete();
      } catch (_) {
        // Ignore cleanup failures; the caller will surface the original error.
      }
    }
    try {
      await user.delete();
    } catch (_) {
      // The user might have already been deleted or require re-authentication.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text(
                  'Welcome to Share a Ride',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Create your account to start sharing journeys.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  textInputAction: TextInputAction.next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  textInputAction: TextInputAction.done,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password.';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isSubmitting ? null : _register,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Register',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

