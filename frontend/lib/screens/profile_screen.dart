import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/screens/login_screen.dart';
import 'package:carpal_app/services/user_profile_cache.dart';

class _ProfileStatistics {
  const _ProfileStatistics({
    this.tripCount,
    this.reviewsCount,
    this.rating,
    this.didFetchTrips = false,
    this.didFetchReviews = false,
    this.hasRatingSamples = false,
  });

  final int? tripCount;
  final int? reviewsCount;
  final double? rating;
  final bool didFetchTrips;
  final bool didFetchReviews;
  final bool hasRatingSamples;
}

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

  Future<_ProfileStatistics> _loadProfileStatistics(String userId) async {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    bool didFetchTrips = false;
    final Set<String> tripIds = <String>{};

    try {
      final QuerySnapshot<Map<String, dynamic>> driverSnapshot = await firestore
          .collection('trips')
          .where('driverId', isEqualTo: userId)
          .get();
      didFetchTrips = true;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in driverSnapshot.docs) {
        tripIds.add(doc.id);
      }
    } catch (_) {
      // Ignore and continue collecting data from other queries.
    }

    const List<String> membershipFields = <String>[
      'passengerIds',
      'passengersIds',
      'participants',
      'participantsIds',
      'joinedUserIds',
      'memberIds',
      'members',
    ];

    for (final String field in membershipFields) {
      final QuerySnapshot<Map<String, dynamic>>? snapshot =
          await _queryTripsByArrayField(firestore, field, userId);
      if (snapshot == null) {
        continue;
      }
      didFetchTrips = true;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        tripIds.add(doc.id);
      }
    }

    final int? tripCount = didFetchTrips ? tripIds.length : null;

    bool didFetchReviews = false;
    final Set<String> reviewIds = <String>{};
    final List<Map<String, dynamic>> reviewData = <Map<String, dynamic>>[];

    const List<String> reviewFields = <String>[
      'recipientId',
      'driverId',
      'userId',
      'targetUserId',
    ];

    for (final String field in reviewFields) {
      final QuerySnapshot<Map<String, dynamic>>? snapshot =
          await _queryReviewsByField(firestore, field, userId);
      if (snapshot == null) {
        continue;
      }
      didFetchReviews = true;
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        if (reviewIds.add(doc.id)) {
          reviewData.add(doc.data());
        }
      }
    }

    int? reviewsCount;
    double? rating;
    bool hasRatingSamples = false;

    if (didFetchReviews) {
      reviewsCount = reviewIds.length;
      double totalRating = 0;
      int ratingSamples = 0;

      for (final Map<String, dynamic> data in reviewData) {
        final double? value = _extractRatingValue(data);
        if (value != null) {
          totalRating += value;
          ratingSamples += 1;
        }
      }

      if (ratingSamples > 0) {
        hasRatingSamples = true;
        rating = totalRating / ratingSamples;
      }
    }

    return _ProfileStatistics(
      tripCount: tripCount,
      reviewsCount: reviewsCount,
      rating: rating,
      didFetchTrips: didFetchTrips,
      didFetchReviews: didFetchReviews,
      hasRatingSamples: hasRatingSamples,
    );
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _queryTripsByArrayField(
    FirebaseFirestore firestore,
    String field,
    String userId,
  ) async {
    try {
      return await firestore
          .collection('trips')
          .where(field, arrayContains: userId)
          .get();
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition' ||
          error.code == 'permission-denied' ||
          error.code == 'invalid-argument') {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>?> _queryReviewsByField(
    FirebaseFirestore firestore,
    String field,
    String userId,
  ) async {
    try {
      return await firestore
          .collection('reviews')
          .where(field, isEqualTo: userId)
          .get();
    } on FirebaseException catch (error) {
      if (error.code == 'failed-precondition' ||
          error.code == 'permission-denied' ||
          error.code == 'invalid-argument') {
        return null;
      }
      rethrow;
    } catch (_) {
      return null;
    }
  }

  double? _extractRatingValue(Map<String, dynamic> data) {
    const List<String> ratingKeys = <String>[
      'rating',
      'score',
      'stars',
      'value',
      'ratingValue',
      'rating_score',
    ];

    for (final String key in ratingKeys) {
      if (!data.containsKey(key)) {
        continue;
      }
      final double? parsed = _parseNumeric(data[key]);
      if (parsed != null) {
        return parsed;
      }
    }

    final dynamic nested = data['rating'];
    if (nested is Map<String, dynamic>) {
      for (final String key in ratingKeys) {
        if (!nested.containsKey(key)) {
          continue;
        }
        final double? parsed = _parseNumeric(nested[key]);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  double? _parseNumeric(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      return value.toDouble();
    }
    if (value is Map<String, dynamic>) {
      for (final String key in <String>['value', 'rating', 'score', 'stars']) {
        if (!value.containsKey(key)) {
          continue;
        }
        final double? parsed = _parseNumeric(value[key]);
        if (parsed != null) {
          return parsed;
        }
      }
      return null;
    }
    return double.tryParse(value.toString());
  }

  UserProfile _mergeProfileWithStats(
    UserProfile profile,
    _ProfileStatistics stats,
  ) {
    final int? tripCount =
        stats.didFetchTrips ? stats.tripCount : profile.tripCount;
    final int? reviewsCount =
        stats.didFetchReviews ? stats.reviewsCount : profile.reviewsCount;
    double? rating;
    if (stats.didFetchReviews) {
      rating = stats.hasRatingSamples ? stats.rating : null;
    } else {
      rating = profile.rating;
    }

    return UserProfile(
      id: profile.id,
      displayName: profile.displayName,
      email: _isCurrentUser ? profile.email : null,
      phone: profile.phone,
      photoUrl: profile.photoUrl,
      tripCount: tripCount,
      reviewsCount: reviewsCount,
      rating: rating,
    );
  }

  void _storeProfileInCache(UserProfile profile) {
    if (_isCurrentUser) {
      UserProfileCache.storeProfile(profile.copyWith(email: null));
    } else {
      UserProfileCache.storeProfile(profile);
    }
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

      UserProfile? profile;

      if (snapshot.exists) {
        profile = UserProfile.fromFirestoreSnapshot(snapshot);
        if (_isCurrentUser) {
          final User? authUser = FirebaseAuth.instance.currentUser;
          profile = profile.copyWith(
            email: UserProfile.sanitizeOptionalText(authUser?.email),
          );
        }
      } else {
        final User? authUser = FirebaseAuth.instance.currentUser;
        if (_isCurrentUser && authUser != null) {
          profile = UserProfile(
            id: authUser.uid,
            displayName: UserProfile.sanitizeDisplayName(authUser.displayName),
            email: UserProfile.sanitizeOptionalText(authUser.email),
            phone: null,
            photoUrl: UserProfile.sanitizePhotoUrl(authUser.photoURL),
            tripCount: null,
            reviewsCount: null,
            rating: null,
          );
        }
      }

      if (profile == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'لا توجد معلومات متاحة لهذا المستخدم';
        });
        UserProfileCache.markMissing(_targetUserId);
        return;
      }

      if (_isCurrentUser) {
        final User? authUser = FirebaseAuth.instance.currentUser;
        final String? authEmail =
            UserProfile.sanitizeOptionalText(authUser?.email);
        profile = UserProfile(
          id: profile.id,
          displayName: profile.displayName,
          email: authEmail,
          phone: profile.phone,
          photoUrl: profile.photoUrl,
          tripCount: profile.tripCount,
          reviewsCount: profile.reviewsCount,
          rating: profile.rating,
        );
      }

      final _ProfileStatistics stats = await _loadProfileStatistics(profile.id);
      final UserProfile enrichedProfile = _mergeProfileWithStats(profile, stats);

      if (!mounted) return;
      setState(() {
        _profile = enrichedProfile;
        _isLoading = false;
      });
      _storeProfileInCache(enrichedProfile);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'تعذّر تحميل الملف الشخصي.';
      });
    }
  }

  Future<void> _changePhoto({XFile? imageFile}) async {
    if (!_isCurrentUser || _profile == null || _isUpdatingPhoto) {
      return;
    }

    try {
      setState(() {
        _isUpdatingPhoto = true;
      });

      final XFile? image;
      if (imageFile != null) {
        image = imageFile;
      } else {
        final ImagePicker picker = ImagePicker();
        image = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxHeight: 1024,
          maxWidth: 1024,
        );
      }

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
      if (_profile != null) {
        _storeProfileInCache(_profile!);
      }
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

  void _handleEditProfile() {
    if (!_isCurrentUser || _profile == null) return;

    final UserProfile currentProfile = _profile!;
    final TextEditingController nameController =
        TextEditingController(text: currentProfile.displayName);
    final TextEditingController phoneController =
        TextEditingController(text: currentProfile.phone ?? '');
    XFile? pendingImage;
    Uint8List? previewBytes;
    bool isSaving = false;
    String? errorText;

    Future<void> pickImage(StateSetter setStateDialog) async {
      if (isSaving) return;
      final ImagePicker picker = ImagePicker();
      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxHeight: 1024,
        maxWidth: 1024,
      );
      if (selected == null) {
        return;
      }
      final Uint8List bytes = await selected.readAsBytes();
      setStateDialog(() {
        pendingImage = selected;
        previewBytes = bytes;
      });
    }

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            final ThemeData theme = Theme.of(context);
            final ColorScheme colorScheme = theme.colorScheme;

            final ImageProvider<Object>? avatarImage;
            if (previewBytes != null) {
              avatarImage = MemoryImage(previewBytes!);
            } else if (currentProfile.photoUrl != null) {
              avatarImage = NetworkImage(currentProfile.photoUrl!);
            } else {
              avatarImage = null;
            }

            return AlertDialog(
              title: const Text('تعديل الملف الشخصي'),
              content: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Center(
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: <Widget>[
                            CircleAvatar(
                              radius: 44,
                              backgroundImage: avatarImage,
                              backgroundColor:
                                  colorScheme.primaryContainer.withOpacity(0.35),
                              child: avatarImage == null
                                  ? Text(
                                      currentProfile.initial,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.primary,
                                      ),
                                    )
                                  : null,
                            ),
                            PositionedDirectional(
                              bottom: 0,
                              end: 0,
                              child: IconButton(
                                onPressed: isSaving
                                    ? null
                                    : () => pickImage(setStateDialog),
                                style: IconButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.camera_alt_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: nameController,
                        textDirection: TextDirection.rtl,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'الاسم',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: phoneController,
                        textDirection: TextDirection.rtl,
                        keyboardType: TextInputType.phone,
                        enabled: !isSaving,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                        ),
                      ),
                      if (errorText != null) ...<Widget>[
                        const SizedBox(height: 16),
                        Text(
                          errorText!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final String rawName = nameController.text.trim();
                          if (rawName.isEmpty) {
                            setStateDialog(() {
                              errorText = 'الاسم مطلوب.';
                            });
                            return;
                          }

                          final String sanitizedName =
                              UserProfile.sanitizeDisplayName(rawName);
                          final String? sanitizedPhone =
                              UserProfile.sanitizeOptionalText(
                                  phoneController.text);

                          setStateDialog(() {
                            isSaving = true;
                            errorText = null;
                          });

                          try {
                            final Map<String, dynamic> updates = <String, dynamic>{
                              'displayName': sanitizedName,
                            };
                            if (sanitizedPhone != null) {
                              updates['phone'] = sanitizedPhone;
                            } else {
                              updates['phone'] = FieldValue.delete();
                            }

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(currentProfile.id)
                                .set(updates, SetOptions(merge: true));

                            final User? authUser =
                                FirebaseAuth.instance.currentUser;
                            if (authUser != null &&
                                authUser.uid == currentProfile.id) {
                              await authUser.updateDisplayName(sanitizedName);
                            }

                            final UserProfile updatedProfile = UserProfile(
                              id: currentProfile.id,
                              displayName: sanitizedName,
                              email: currentProfile.email,
                              phone: sanitizedPhone,
                              photoUrl: currentProfile.photoUrl,
                              tripCount: currentProfile.tripCount,
                              reviewsCount: currentProfile.reviewsCount,
                              rating: currentProfile.rating,
                            );

                            if (mounted) {
                              setState(() {
                                _profile = updatedProfile;
                              });
                              _storeProfileInCache(updatedProfile);
                            }

                            if (pendingImage != null) {
                              await _changePhoto(imageFile: pendingImage);
                            }

                            if (!mounted) return;
                            Navigator.of(dialogContext).pop();
                          } catch (_) {
                            setStateDialog(() {
                              isSaving = false;
                              errorText =
                                  'تعذّر حفظ التعديلات، حاول مرة أخرى.';
                            });
                          }
                        },
                  child: isSaving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    final ColorScheme colorScheme = theme.colorScheme;

    final Widget avatarContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: CircleAvatar(
        key: ValueKey<String>(_profile?.photoUrl ?? 'initial_${_profile?.initial ?? '?'}'),
        radius: 56,
        backgroundImage:
            _profile?.photoUrl != null ? NetworkImage(_profile!.photoUrl!) : null,
        backgroundColor: colorScheme.primaryContainer.withOpacity(0.35),
        child: _profile?.photoUrl == null
            ? Text(
                (_profile?.initial ?? '?'),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              )
            : null,
      ),
    );

    final Widget decoratedAvatar = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.surface,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.2),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.surface,
        ),
        child: avatarContent,
      ),
    );

    if (!_isCurrentUser) {
      return decoratedAvatar;
    }

    final Widget interactiveAvatar = Stack(
      alignment: Alignment.center,
      children: <Widget>[
        decoratedAvatar,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isUpdatingPhoto ? 0.75 : 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surface.withOpacity(0.75),
                ),
                child: const Center(
                  child: SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 12,
          end: 12,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _isUpdatingPhoto ? 0 : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withOpacity(0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return MouseRegion(
      cursor: _isUpdatingPhoto ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isUpdatingPhoto ? null : () => _changePhoto(),
        onDoubleTap: _isUpdatingPhoto ? null : () => _changePhoto(),
        child: interactiveAvatar,
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    final ColorScheme colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    value,
                    key: ValueKey<String>(value),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required ThemeData theme,
  }) {
    final ColorScheme colorScheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  value,
                  key: ValueKey<String>('metric_$label$value'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

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
      final String email = _isCurrentUser
          ? (_profile!.email ?? 'غير متوفر')
          : 'غير متوفر';
      final String phone = _profile!.phone ?? 'غير متوفر';
      final int? tripCountValue = _profile!.tripCount;
      final int? reviewsCountValue = _profile!.reviewsCount;
      final double? ratingNumber = _profile!.rating;

      final String tripCountText =
          tripCountValue != null ? tripCountValue.toString() : 'غير متوفر';
      final String reviewsCountText = reviewsCountValue != null
          ? reviewsCountValue.toString()
          : 'غير متوفر';
      final String ratingValue = ratingNumber != null
          ? '${ratingNumber.toStringAsFixed(1)} ⭐'
          : 'غير متوفر';

      bodyContent = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool isWide = constraints.maxWidth >= 720;
          final EdgeInsetsGeometry padding = EdgeInsets.symmetric(
            horizontal: isWide ? 32 : 24,
            vertical: 32,
          );

          final Widget contactTiles = isWide
              ? Row(
                  children: <Widget>[
                    if (_isCurrentUser) ...[
                      Expanded(
                        child: _buildInfoTile(
                          icon: Icons.email_rounded,
                          label: 'البريد الإلكتروني',
                          value: email ?? 'غير متوفر',
                          theme: theme,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: _buildInfoTile(
                        icon: Icons.phone_rounded,
                        label: 'رقم الهاتف',
                        value: phone,
                        theme: theme,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: <Widget>[
                    if (_isCurrentUser) ...[
                      _buildInfoTile(
                        icon: Icons.email_rounded,
                        label: 'البريد الإلكتروني',
                        value: email ?? 'غير متوفر',
                        theme: theme,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildInfoTile(
                      icon: Icons.phone_rounded,
                      label: 'رقم الهاتف',
                      value: phone,
                      theme: theme,
                    ),
                  ],
                );

          final Widget statsGrid = isWide
              ? Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.directions_car_filled_rounded,
                        label: 'الرحلات',
                        value: tripCountText,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.people_alt_rounded,
                        label: 'التقييمات المستلمة',
                        value: reviewsCountText,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMetricTile(
                        icon: Icons.star_rate_rounded,
                        label: 'متوسط التقييم',
                        value: ratingValue,
                        theme: theme,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: <Widget>[
                    _buildMetricTile(
                      icon: Icons.directions_car_filled_rounded,
                      label: 'الرحلات',
                      value: tripCountText,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildMetricTile(
                      icon: Icons.people_alt_rounded,
                      label: 'التقييمات المستلمة',
                      value: reviewsCountText,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildMetricTile(
                      icon: Icons.star_rate_rounded,
                      label: 'متوسط التقييم',
                      value: ratingValue,
                      theme: theme,
                    ),
                  ],
                );

          return SingleChildScrollView(
            padding: padding,
            physics: const BouncingScrollPhysics(),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(isWide ? 32 : 24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.08),
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              SizedBox(
                                width: 168,
                                child: Center(child: _buildAvatar(theme)),
                              ),
                              const SizedBox(width: 32),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(
                                      _profile!.displayName,
                                      style: theme.textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      email,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    contactTiles,
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Center(child: _buildAvatar(theme)),
                              const SizedBox(height: 24),
                              Text(
                                _profile!.displayName,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                email,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodyMedium?.color
                                      ?.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 24),
                              contactTiles,
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'النشاط والإحصائيات',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.colorScheme.primary.withOpacity(0.1),
                        ),
                        const SizedBox(height: 20),
                        statsGrid,
                      ],
                    ),
                  ),
                  if (_isCurrentUser) ...<Widget>[
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.end,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: _handleEditProfile,
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('تعديل الملف الشخصي'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _signOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('تسجيل الخروج'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
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
