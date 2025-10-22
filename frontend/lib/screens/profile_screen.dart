import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/screens/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.showAppBar = true,
    this.userId,
    this.initialProfile,
  });

  final bool showAppBar;
  final String? userId;
  final UserProfile? initialProfile;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _isLoading = true;
  bool _isUpdatingPhoto = false;
  String? _errorMessage;
  late final String _targetUserId;

  bool get _isCurrentUser {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;
    return widget.userId == null || widget.userId == currentUser.uid;
  }

  @override
  void initState() {
    super.initState();
    final User? currentUser = FirebaseAuth.instance.currentUser;
    _targetUserId = widget.userId ?? currentUser?.uid ?? '';
    _profile = widget.initialProfile;
    _isLoading = _profile == null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
    });
  }

  Future<void> _refreshProfile() async {
    if (_targetUserId.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذّر العثور على المستخدم.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
          .instance
          .collection('users')
          .doc(_targetUserId)
          .get();

      if (snapshot.exists) {
        final UserProfile profile = UserProfile.fromFirestoreSnapshot(snapshot);
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
        return;
      }

      final User? authUser = FirebaseAuth.instance.currentUser;
      if (_isCurrentUser && authUser != null) {
        final UserProfile profile = UserProfile(
          id: authUser.uid,
          displayName: UserProfile.sanitizeDisplayName(authUser.displayName),
          email: UserProfile.sanitizeOptionalText(authUser.email),
          phone: null,
          photoUrl: UserProfile.sanitizePhotoUrl(authUser.photoURL),
          tripsCount: null,
          rating: null,
        );
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لا توجد معلومات متاحة لهذا المستخدم.';
        });
      }
    } catch (_) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذّر تحميل الملف الشخصي.';
      });
    }
  }

  Future<void> _changePhoto() async {
    if (!_isCurrentUser || _profile == null || _isUpdatingPhoto) {
      return;
    }

    try {
      setState(() {
        _isUpdatingPhoto = true;
      });

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxHeight: 1024,
        maxWidth: 1024,
      );

      if (image == null) {
        setState(() {
          _isUpdatingPhoto = false;
        });
        return;
      }

      final String path =
          'profile_pictures/${_profile!.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(path);

      final Uint8List data = await image.readAsBytes();
      final TaskSnapshot snapshot = await ref.putData(
        data,
        SettableMetadata(
          contentType: image.mimeType ?? 'image/jpeg',
        ),
      );
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_profile!.id)
          .set({'photoUrl': downloadUrl}, SetOptions(merge: true));

      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == _profile!.id) {
        await currentUser.updatePhotoURL(downloadUrl);
      }

      if (!mounted) return;
      setState(() {
        _profile = _profile!.copyWith(photoUrl: downloadUrl);
        _isUpdatingPhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isUpdatingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر تحديث الصورة، حاول مرة أخرى لاحقًا.'),
        ),
      );
    }
  }

  Widget _buildAvatar(ColorScheme colorScheme) {
    final Widget avatar;
    if (_profile?.photoUrl != null) {
      avatar = CircleAvatar(
        radius: 50,
        backgroundImage: NetworkImage(_profile!.photoUrl!),
      );
    } else {
      avatar = CircleAvatar(
        radius: 50,
        backgroundColor: colorScheme.primaryContainer,
        child: Text(
          (_profile?.initial ?? '?'),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      );
    }

    if (!_isCurrentUser) {
      return avatar;
    }

    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        avatar,
        Positioned(
          bottom: 0,
          right: 0,
          child: Material(
            color: colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _isUpdatingPhoto ? null : _changePhoto,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _isUpdatingPhoto
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.onPrimary,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: colorScheme.onPrimary,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: Colors.deepPurple.shade400),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    final Widget bodyContent;
    if (_isLoading) {
      bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_errorMessage != null) {
      bodyContent = Center(
        child: Text(
          _errorMessage!,
          textAlign: TextAlign.center,
        ),
      );
    } else if (_profile == null) {
      bodyContent = const Center(
        child: Text('لا توجد معلومات لعرضها.'),
      );
    } else {
      final String email = _profile!.email ?? 'لا يوجد بريد إلكتروني';
      final String phone = _profile!.phone ?? 'لا يوجد رقم هاتف';
      final String trips = _profile!.tripsCount != null
          ? _profile!.tripsCount.toString()
          : 'غير متوفر';
      final String rating = _profile!.rating != null
          ? _profile!.rating!.toStringAsFixed(1)
          : 'غير متوفر';

      bodyContent = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _buildAvatar(colorScheme),
            const SizedBox(height: 24),
            Text(
              _profile!.displayName,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 32),
            _buildInfoTile(
              icon: Icons.phone_rounded,
              label: 'رقم الهاتف',
              value: phone,
            ),
            const SizedBox(height: 16),
            _buildInfoTile(
              icon: Icons.directions_car_filled,
              label: 'عدد الرحلات',
              value: trips,
            ),
            const SizedBox(height: 16),
            _buildInfoTile(
              icon: Icons.star_rate_rounded,
              label: 'التقييم',
              value: rating,
            ),
            if (_isCurrentUser) ...<Widget>[
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (!widget.showAppBar) {
      return SafeArea(child: bodyContent);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        actions: <Widget>[
          if (_isCurrentUser)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _isLoading ? null : _refreshProfile,
            ),
        ],
      ),
      body: SafeArea(child: bodyContent),
    );
  }
}
