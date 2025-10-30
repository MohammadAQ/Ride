import 'package:flutter/material.dart';

import 'auth_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(_createFadeRoute());
        });
      }
    });
  }

  PageRouteBuilder<void> _createFadeRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => const AuthWrapper(),
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final shortestSide = size.shortestSide;
    final maxDimension = (shortestSide * 0.45).clamp(140.0, 240.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF001F3F), Color(0xFF00BFA5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxDimension,
                maxHeight: maxDimension,
                minWidth: maxDimension * 0.6,
                minHeight: maxDimension * 0.6,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dimension = constraints.maxWidth.clamp(120, 260);
                  return Image.asset(
                    'assets/images/ride_logo.png',
                    width: dimension,
                    height: dimension,
                    filterQuality: FilterQuality.high,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
