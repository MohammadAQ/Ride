import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:carpal_app/screens/login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final rawEmail = user?.email?.trim();
    final email = (rawEmail != null && rawEmail.isNotEmpty)
        ? rawEmail
        : 'No email available';
    final displayName = () {
      final rawName = user?.displayName?.trim();
      if (rawName != null && rawName.isNotEmpty) {
        return rawName;
      }
      if (rawEmail != null && rawEmail.isNotEmpty) {
        return rawEmail.split('@').first;
      }
      return 'Guest';
    }();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: 48,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!showAppBar) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: content,
    );
  }
}
