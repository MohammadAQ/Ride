import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/services/user_profile_cache.dart';
import 'package:carpal_app/utils/profile_navigation.dart';

class UserProfilePreview extends StatefulWidget {
  const UserProfilePreview({
    super.key,
    required this.userId,
    required this.fallbackName,
    this.textStyle,
    this.avatarRadius = 20,
    this.textDirection = TextDirection.rtl,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String userId;
  final String fallbackName;
  final TextStyle? textStyle;
  final double avatarRadius;
  final TextDirection textDirection;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  State<UserProfilePreview> createState() => _UserProfilePreviewState();
}

class _UserProfilePreviewState extends State<UserProfilePreview> {
  UserProfile? _profile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final String trimmedId = widget.userId.trim();
    _profile = UserProfileCache.get(trimmedId);
    final bool hasCacheEntry = UserProfileCache.hasEntry(trimmedId);
    if (trimmedId.isEmpty || _profile != null || hasCacheEntry) {
      _isLoading = false;
    } else {
      _isLoading = true;
      _loadProfile(trimmedId);
    }
  }

  Future<void> _loadProfile(String userId) async {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final UserProfile? profile = await UserProfileCache.fetch(userId);
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _isLoading = false;
    });
  }

  UserProfile? _buildInitialProfile() {
    final String trimmedId = widget.userId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }
    if (_profile != null) {
      return _profile;
    }
    return UserProfile(
      id: trimmedId,
      displayName: UserProfile.sanitizeDisplayName(widget.fallbackName),
      email: null,
      phone: null,
      photoUrl: null,
      tripsCount: null,
      rating: null,
    );
  }

  void _openProfile() {
    final String trimmedId = widget.userId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    ProfileNavigation.pushProfile(
      context: context,
      userId: trimmedId,
      initialProfile: _buildInitialProfile(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextDirection direction = widget.textDirection;

    final String displayName = UserProfile.sanitizeDisplayName(
      _profile?.displayName ?? widget.fallbackName,
    );

    final String initial = _profile?.initial ??
        (displayName.isNotEmpty ? displayName.characters.first : '?');

    final String? photoUrl = _profile?.photoUrl;

    final Color backgroundColor = widget.backgroundColor ??
        (direction == TextDirection.rtl
            ? colorScheme.primaryContainer
            : colorScheme.secondaryContainer);
    final Color foregroundColor =
        widget.foregroundColor ?? colorScheme.onPrimaryContainer;

    final Widget avatar;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      avatar = CircleAvatar(
        radius: widget.avatarRadius,
        backgroundImage: NetworkImage(photoUrl),
      );
    } else if (_isLoading) {
      avatar = CircleAvatar(
        radius: widget.avatarRadius,
        backgroundColor: backgroundColor.withOpacity(0.6),
        child: SizedBox(
          height: widget.avatarRadius,
          width: widget.avatarRadius,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: widget.avatarRadius,
        backgroundColor: backgroundColor,
        child: Text(
          initial,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: foregroundColor,
          ),
        ),
      );
    }

    final TextStyle? textStyle = widget.textStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            );

    return Directionality(
      textDirection: direction,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.avatarRadius * 2),
          onTap: widget.userId.trim().isEmpty ? null : _openProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    style: textStyle,
                    textAlign: direction == TextDirection.rtl
                        ? TextAlign.right
                        : TextAlign.left,
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
