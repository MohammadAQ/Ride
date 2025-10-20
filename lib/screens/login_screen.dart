import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:carpal_app/screens/main_screen.dart';

class LoginScreen extends StatefulWidget {
  final String initialEmail;

  const LoginScreen({super.key, this.initialEmail = ''});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // تسجيل الدخول
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        // إنشاء مستخدم جديد
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      // بعد النجاح → الذهاب إلى الصفحة الرئيسية
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Authentication failed';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already registered.';
      } else if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Invalid password.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', height: 90),
                  const SizedBox(height: 15),
                  const Text(
                    'Share a Ride',
                    style: TextStyle(
                      fontFamily: 'DancingScript',
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Email
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || !value.contains('@')) {
                        return 'Please enter a valid email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return 'Password must be at least 6 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  if (_isLoading)
                    const CircularProgressIndicator()
                  else
                    ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 60,
                        ),
                      ),
                      child: Text(_isLogin ? 'Login' : 'Create Account'),
                    ),

                  TextButton(
                    onPressed: () {
                      setState(() => _isLogin = !_isLogin);
                    },
                    child: Text(_isLogin
                        ? 'Create a new account'
                        : 'I already have an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
