import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'create_trip_screen.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  final ApiService _apiService = ApiService();
  final List<Map<String, dynamic>> _trips = <Map<String, dynamic>>[];
  String? _nextCursor;
  bool _isLoading = false;
  bool _initialLoading = false;
  String? _errorMessage;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    _initialLoading = currentUser != null;
    if (currentUser != null) {
      unawaited(_loadTrips(reset: true));
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) {
        return;
      }

      if (user == null) {
        setState(() {
          _trips.clear();
          _nextCursor = null;
          _errorMessage = null;
          _initialLoading = false;
        });
      } else {
        setState(() {
          _initialLoading = true;
        });
        unawaited(_loadTrips(reset: true));
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTrips({required bool reset}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _trips.clear();
        _nextCursor = null;
        _errorMessage = null;
        _initialLoading = false;
        _isLoading = false;
      });
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
      if (reset) {
        if (_trips.isNotEmpty) {
          _trips.clear();
        }
        _nextCursor = null;
      }
    });

    try {
      final response = await _apiService.fetchMyTrips(
        limit: 20,
        cursor: reset ? null : _nextCursor,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (reset) {
          _trips
            ..clear()
            ..addAll(response.trips);
        } else {
          _trips.addAll(response.trips);
        }
        _nextCursor = response.nextCursor;
        _initialLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'حدث خطأ غير متوقع. حاول مرة أخرى لاحقًا.';
        _initialLoading = false;
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshTrips() => _loadTrips(reset: true);

  void _loadMoreTrips() {
    if (_isLoading || _nextCursor == null) {
      return;
    }
    unawaited(_loadTrips(reset: false));
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    final stringValue = value.toString().trim();
    if (stringValue.isEmpty) {
      return null;
    }
    return stringValue;
  }

  String? _resolveTripDriverId(Map<String, dynamic> trip) {
    final directId = _stringOrNull(trip['driverId']);
    if (directId != null) {
      return directId;
    }

    final snakeCaseId = _stringOrNull(trip['driver_id']);
    if (snakeCaseId != null) {
      return snakeCaseId;
    }

    final upperCamelCaseId = _stringOrNull(trip['driverID']);
    if (upperCamelCaseId != null) {
      return upperCamelCaseId;
    }

    final driverData = trip['driver'];
    if (driverData is Map) {
      final driverMap = driverData.map((key, value) => MapEntry(key.toString(), value));
      final nestedId = _stringOrNull(driverMap['id']) ??
          _stringOrNull(driverMap['uid']) ??
          _stringOrNull(driverMap['userId']) ??
          _stringOrNull(driverMap['user_id']);
      if (nestedId != null) {
        return nestedId;
      }
    }

    return _stringOrNull(driverData);
  }

  DateTime? _parseTripDateTime(Map<String, dynamic> trip) {
    final dateString = _stringOrNull(trip['date']);
    if (dateString == null) {
      return null;
    }

    DateTime? date = DateTime.tryParse(dateString);
    if (date == null) {
      return null;
    }

    final timeString = _stringOrNull(trip['time']);
    if (timeString == null) {
      return date;
    }

    final parts = timeString.split(':');
    if (parts.length < 2) {
      return date;
    }

    final hour = int.tryParse(parts[0]) ?? date.hour;
    final minute = int.tryParse(parts[1]) ?? date.minute;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  bool _canEditTrip(Map<String, dynamic> trip) {
    final scheduled = _parseTripDateTime(trip);
    if (scheduled == null) {
      return true;
    }

    final now = DateTime.now();
    return scheduled.isAfter(now);
  }

  int _indexForTripId(String id) {
    return _trips.indexWhere(
      (trip) => _stringOrNull(trip['id']) == id,
    );
  }

  Future<void> _handleEditTrip(Map<String, dynamic> trip) async {
    final sanitizedTrip = Map<String, dynamic>.from(trip)
      ..remove('_isProcessing')
      ..remove('_isDeleting');

    final updatedTrip = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => CreateTripScreen(
          initialTripData: sanitizedTrip,
        ),
      ),
    );

    if (!mounted || updatedTrip == null) {
      return;
    }

    final updatedId = _stringOrNull(updatedTrip['id']) ?? _stringOrNull(trip['id']);
    if (updatedId == null) {
      unawaited(_loadTrips(reset: true));
      return;
    }

    final index = _indexForTripId(updatedId);
    if (index == -1) {
      unawaited(_loadTrips(reset: true));
      return;
    }

    setState(() {
      final merged = Map<String, dynamic>.from(_trips[index])
        ..addAll(updatedTrip)
        ..remove('_isProcessing')
        ..remove('_isDeleting');
      _trips[index] = merged;
    });

    unawaited(_loadTrips(reset: true));
  }

  Future<void> _handleDeleteTrip(Map<String, dynamic> trip) async {
    final tripId = _stringOrNull(trip['id']);
    if (tripId == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد الرحلة لحذفها.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الرحلة'),
          content: const Text('هل أنت متأكد أنك تريد حذف هذه الرحلة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      final index = _indexForTripId(tripId);
      if (index != -1) {
        _trips[index]['_isProcessing'] = true;
      }
    });

    try {
      await _apiService.deleteTrip(tripId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الرحلة بنجاح'),
        ),
      );

      setState(() {
        final index = _indexForTripId(tripId);
        if (index != -1) {
          _trips[index]['_isProcessing'] = false;
          _trips[index]['_isDeleting'] = true;
        }
      });

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) {
        return;
      }

      setState(() {
        final index = _indexForTripId(tripId);
        if (index != -1) {
          _trips.removeAt(index);
        }
      });

      unawaited(_loadTrips(reset: true));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        final index = _indexForTripId(tripId);
        if (index != -1) {
          _trips[index]['_isProcessing'] = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حذف الرحلة: ${error.message}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        final index = _indexForTripId(tripId);
        if (index != -1) {
          _trips[index]['_isProcessing'] = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل حذف الرحلة: حدث خطأ غير متوقع'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showTripOptions(Map<String, dynamic> trip) {
    final user = FirebaseAuth.instance.currentUser;
    final driverId = _resolveTripDriverId(trip);

    if (user == null || driverId == null || driverId != user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكنك إدارة رحلات لا تخصك.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final canEdit = _canEditTrip(trip);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  ListTile(
                    leading: const Text('✏️', style: TextStyle(fontSize: 20)),
                    title: const Text('تعديل الرحلة'),
                    subtitle: canEdit
                        ? null
                        : const Text('لا يمكنك تعديل الرحلات التي بدأت أو انتهت.'),
                    enabled: canEdit,
                    onTap: canEdit
                        ? () {
                            Navigator.of(context).pop();
                            _handleEditTrip(trip);
                          }
                        : null,
                  ),
                  ListTile(
                    leading: const Text('🗑️', style: TextStyle(fontSize: 20)),
                    title: Text(
                      'حذف الرحلة',
                      style: TextStyle(color: colorScheme.error),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _handleDeleteTrip(trip);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = [
      const Color(0xFFF3E5F5),
      const Color(0xFFEDE7F6),
      const Color(0xFFE8EAF6),
      const Color(0xFFD1C4E9),
    ];

    final user = FirebaseAuth.instance.currentUser;

    final body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: user == null
            ? _buildSignInPrompt(context)
            : RefreshIndicator(
                onRefresh: _refreshTrips,
                color: Theme.of(context).colorScheme.primary,
                child: _buildTripList(context),
              ),
      ),
    );

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Trips'),
        centerTitle: false,
      ),
      body: body,
    );
  }

  Widget _buildSignInPrompt(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          child: Center(
            child: Text(
              'الرجاء تسجيل الدخول لعرض رحلاتك.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onBackground
                        .withOpacity(0.7),
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTripList(BuildContext context) {
    if (_initialLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(
            height: 280,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Text(
                _errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onBackground
                          .withOpacity(0.7),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _loadTrips(reset: true),
            child: const Text('إعادة المحاولة'),
          ),
        ],
      );
    }

    if (_trips.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Center(
              child: Text(
                'لم تقم بإنشاء أي رحلات بعد',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onBackground
                          .withOpacity(0.7),
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      itemCount: _trips.length + (_nextCursor != null ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        if (index >= _trips.length) {
          return _buildLoadMoreTile(context);
        }

        final data = _trips[index];
        final tripId = _stringOrNull(data['id']) ?? 'trip-$index';
        final fromCity = (data['fromCity'] ?? '').toString().trim();
        final toCity = (data['toCity'] ?? '').toString().trim();
        final dateText = _formatDate(data['date']);
        final timeText = _formatTime(data['time']);
        final priceText = _formatPrice(data['price']);

        final isProcessing = data['_isProcessing'] == true;
        final isDeleting = data['_isDeleting'] == true;

        Widget card = MyTripCard(
          fromCity: fromCity.isEmpty ? 'غير متوفر' : fromCity,
          toCity: toCity.isEmpty ? 'غير متوفر' : toCity,
          date: dateText.isEmpty ? 'غير متوفر' : dateText,
          time: timeText.isEmpty ? 'غير متوفر' : timeText,
          price: priceText,
          onLongPress: isProcessing ? null : () => _showTripOptions(data),
        );

        if (isProcessing) {
          card = Stack(
            children: [
              Opacity(
                opacity: 0.6,
                child: card,
              ),
              const Positioned.fill(
                child: Center(
                  child: SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            ],
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: child,
            ),
          ),
          child: isDeleting
              ? SizedBox.shrink(key: ValueKey('deleted-$tripId'))
              : KeyedSubtree(
                  key: ValueKey('trip-$tripId'),
                  child: card,
                ),
        );
      },
    );
  }

  Widget _buildLoadMoreTile(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: OutlinedButton.icon(
        onPressed: _loadMoreTrips,
        icon: const Icon(Icons.expand_more),
        label: const Text('تحميل المزيد'),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      final trimmed = date.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    if (date is DateTime) {
      return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
    }

    return '';
  }

  String _formatTime(dynamic time) {
    if (time is String) {
      final trimmed = time.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    if (time is DateTime) {
      return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
    }

    return '';
  }

  String _formatPrice(dynamic price) {
    if (price is num) {
      return '\$${price.toStringAsFixed(2)}';
    }

    if (price is String) {
      final trimmed = price.trim();
      if (trimmed.isEmpty) {
        return '';
      }
      if (trimmed.startsWith('\$')) {
        return trimmed;
      }
      final numericValue = double.tryParse(trimmed);
      if (numericValue != null) {
        return '\$${numericValue.toStringAsFixed(2)}';
      }
      return trimmed;
    }

    return '';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class MyTripCard extends StatelessWidget {
  const MyTripCard({
    super.key,
    required this.fromCity,
    required this.toCity,
    required this.date,
    required this.time,
    required this.price,
    this.onLongPress,
  });

  final String fromCity;
  final String toCity;
  final String date;
  final String time;
  final String price;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      color: colorScheme.surface.withOpacity(0.95),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.directions_car,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'من: $fromCity  →  إلى: $toCity',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$date  •  $time',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.8),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Text(
                      price,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
