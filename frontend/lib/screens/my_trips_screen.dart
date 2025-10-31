import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/driver_trip_validation_service.dart';
import 'create_trip_screen.dart';
import 'ride_details_screen.dart';

class MyTripsScreen extends StatefulWidget {
  const MyTripsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  final ApiService _apiService = ApiService();
  final DriverTripValidationService _tripValidationService =
      DriverTripValidationService();
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
      final String languageCode =
          Localizations.localeOf(context).languageCode;

      // Validate driver-side deletion rules (completed trips, booked passengers)
      // before issuing the Firestore delete call.
      await _tripValidationService.ensureCanDeleteTrip(
        tripId: tripId,
        languageCode: languageCode,
      );

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
    } on TripValidationException catch (error) {
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
          content: Text(error.message),
          backgroundColor: Colors.redAccent,
        ),
      );
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
      const Color(0xFFEDE7F6),
      Theme.of(context).colorScheme.primary.withOpacity(0.08),
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
        final tripId = _resolveTripId(data, index);
        final fromCity = (data['fromCity'] ?? '').toString().trim();
        final toCity = (data['toCity'] ?? '').toString().trim();
        final dateText = _formatDate(data['date']);
        final timeText = _formatTime(data['time']);
        final driverId = _resolveTripDriverId(data) ?? '';
        final priceText = _formatPrice(data['price']);
        final driverName = _extractDriverName(data);
        final availableSeats = _parseSeatCount(data['availableSeats']);
        final carModel = _extractCarModel(data);
        final carColor = _extractCarColor(data);
        final createdAt = _extractCreatedAt(data);
        final textDirection = Directionality.of(context);

        final isProcessing = data['_isProcessing'] == true;
        final isDeleting = data['_isDeleting'] == true;

        final RideDetailsArguments detailsArgs = RideDetailsArguments(
          tripId: tripId,
          fromCity: fromCity,
          toCity: toCity,
          tripDate: dateText,
          tripTime: timeText,
          driverName: driverName,
          availableSeats: availableSeats,
          price: priceText,
          driverId: driverId,
          carModel: carModel,
          carColor: carColor,
          createdAt: createdAt,
        );

        Widget card = MyTripCard(
          fromCity: fromCity,
          toCity: toCity,
          tripDate: dateText,
          tripTime: timeText,
          driverName: driverName,
          availableSeats: availableSeats,
          price: priceText,
          carModel: carModel,
          carColor: carColor,
          createdAt: createdAt,
          textDirection: textDirection,
          onLongPress: isProcessing ? null : () => _showTripOptions(data),
          onTap: () => _handleViewTripDetails(detailsArgs),
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

  String _resolveTripId(Map<String, dynamic> trip, int fallbackIndex) {
    const List<String> possibleKeys = <String>[
      'id',
      'tripId',
      'trip_id',
      'documentId',
      'document_id',
    ];

    for (final String key in possibleKeys) {
      final String? value = _stringOrNull(trip[key]);
      if (value != null) {
        return value;
      }
    }

    final dynamic metadata = trip['metadata'];
    if (metadata is Map) {
      final Map<String, dynamic> metadataMap =
          metadata.map((key, value) => MapEntry(key.toString(), value));
      for (final String key in possibleKeys) {
        final String? value = _stringOrNull(metadataMap[key]);
        if (value != null) {
          return value;
        }
      }
    }

    return 'trip-$fallbackIndex';
  }

  String _extractDriverName(Map<String, dynamic> trip) {
    final directName = _stringOrNull(trip['driverName']) ??
        _stringOrNull(trip['driver_name']) ??
        _stringOrNull(trip['driverFullName']) ??
        _stringOrNull(trip['driver_full_name']);
    if (directName != null) {
      return directName;
    }

    final driverData = trip['driver'];
    if (driverData is Map) {
      final driverMap = driverData.map((key, value) => MapEntry(key.toString(), value));
      final nestedName = _stringOrNull(driverMap['name']) ??
          _stringOrNull(driverMap['fullName']) ??
          _stringOrNull(driverMap['full_name']) ??
          _stringOrNull(driverMap['displayName']) ??
          _stringOrNull(driverMap['display_name']);
      if (nestedName != null) {
        return nestedName;
      }

      final firstName = _stringOrNull(driverMap['firstName']) ??
          _stringOrNull(driverMap['first_name']);
      final lastName = _stringOrNull(driverMap['lastName']) ??
          _stringOrNull(driverMap['last_name']);
      final combined = [firstName, lastName].whereType<String>().join(' ').trim();
      if (combined.isNotEmpty) {
        return combined;
      }
    }

    if (driverData is String) {
      final driverString = driverData.trim();
      if (driverString.isNotEmpty) {
        return driverString;
      }
    }

    return '';
  }

  int _parseSeatCount(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final parsed = int.tryParse(value.toString());
    return parsed ?? 0;
  }

  String? _extractCarModel(Map<String, dynamic> trip) {
    final directModel = _stringOrNull(trip['carModel']) ??
        _stringOrNull(trip['car_model']) ??
        _stringOrNull(trip['vehicleModel']) ??
        _stringOrNull(trip['vehicle_model']);
    if (directModel != null) {
      return directModel;
    }

    final carData = trip['car'] ?? trip['vehicle'];
    if (carData is Map) {
      final carMap = carData.map((key, value) => MapEntry(key.toString(), value));
      final nestedModel = _stringOrNull(carMap['model']) ??
          _stringOrNull(carMap['name']) ??
          _stringOrNull(carMap['type']);
      if (nestedModel != null) {
        return nestedModel;
      }
    }

    if (carData is String) {
      final trimmed = carData.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  String? _extractCarColor(Map<String, dynamic> trip) {
    final directColor = _stringOrNull(trip['carColor']) ??
        _stringOrNull(trip['car_color']) ??
        _stringOrNull(trip['vehicleColor']) ??
        _stringOrNull(trip['vehicle_color']);
    if (directColor != null) {
      return directColor;
    }

    final carData = trip['car'] ?? trip['vehicle'];
    if (carData is Map) {
      final carMap = carData.map((key, value) => MapEntry(key.toString(), value));
      final nestedColor = _stringOrNull(carMap['color']) ??
          _stringOrNull(carMap['colour']);
      if (nestedColor != null) {
        return nestedColor;
      }
    }

    if (carData is String) {
      final trimmed = carData.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  DateTime? _extractCreatedAt(Map<String, dynamic> trip) {
    const possibleKeys = [
      'createdAt',
      'created_at',
      'createdOn',
      'created_on',
      'createdDate',
      'created_date',
      'created',
      'createdTime',
      'created_time',
    ];

    for (final key in possibleKeys) {
      if (!trip.containsKey(key)) {
        continue;
      }
      final parsed = _parseDateTimeValue(trip[key]);
      if (parsed != null) {
        return parsed;
      }
    }

    final metadata = trip['metadata'];
    if (metadata is Map) {
      final metaMap = metadata.map((key, value) => MapEntry(key.toString(), value));
      for (final key in possibleKeys) {
        if (!metaMap.containsKey(key)) {
          continue;
        }
        final parsed = _parseDateTimeValue(metaMap[key]);
        if (parsed != null) {
          return parsed;
        }
      }
    }

    return null;
  }

  DateTime? _parseDateTimeValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is num) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      if (value > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
      }
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return parsed;
      }
      final numeric = num.tryParse(trimmed);
      if (numeric != null) {
        return _parseDateTimeValue(numeric);
      }
    }
    try {
      final dynamic dynamicValue = value;
      final dynamic converted = dynamicValue.toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {
      // Ignore values that cannot be converted via toDate.
    }
    return null;
  }

  void _handleViewTripDetails(RideDetailsArguments arguments) {
    if (!mounted) {
      return;
    }

    if (arguments.tripId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Directionality.of(context) == TextDirection.rtl
                ? 'تعذر فتح لوحة الرحلة لعدم توفر معرّف صالح.'
                : 'Unable to open the trip dashboard without a valid trip ID.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RideDetailsScreen(arguments: arguments),
      ),
    );
  }
}

class MyTripCard extends StatelessWidget {
  const MyTripCard({
    super.key,
    required this.fromCity,
    required this.toCity,
    required this.tripDate,
    required this.tripTime,
    required this.driverName,
    required this.availableSeats,
    required this.price,
    this.carModel,
    this.carColor,
    this.createdAt,
    required this.textDirection,
    this.onLongPress,
    this.onTap,
  });

  final String fromCity;
  final String toCity;
  final String tripDate;
  final String tripTime;
  final String driverName;
  final int availableSeats;
  final String price;
  final String? carModel;
  final String? carColor;
  final DateTime? createdAt;
  final TextDirection textDirection;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isRtl = textDirection == TextDirection.rtl;

    final fromCityLabel = fromCity.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : fromCity;
    final toCityLabel = toCity.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : toCity;
    final dateLabel = tripDate.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : tripDate;
    final timeLabel = tripTime.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : tripTime;
    final driverLabel = driverName.isEmpty
        ? (isRtl ? 'غير متاح' : 'Not available')
        : driverName;
    final priceLabel = price.isEmpty
        ? (isRtl ? 'غير متاح' : 'Not available')
        : price;
    final carDescription = _buildCarDescription(isRtl);
    final createdAtLabel = _formatCreatedAt(isRtl);

    return Directionality(
      textDirection: textDirection,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        color: colorScheme.surface.withOpacity(0.96),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onLongPress: onLongPress,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment:
                  isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  textDirection: textDirection,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.directions_car,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                          children: [
                            TextSpan(text: isRtl ? 'من ' : 'From '),
                            TextSpan(
                              text: fromCityLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            TextSpan(text: isRtl ? ' إلى ' : ' to '),
                            TextSpan(
                              text: toCityLabel,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.event,
                  textDirection: textDirection,
                  iconColor: colorScheme.onSurface.withOpacity(0.7),
                  child: Text(
                    '$dateLabel • $timeLabel',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.person_outline,
                  textDirection: textDirection,
                  iconColor: colorScheme.onSurface.withOpacity(0.7),
                  child: Text.rich(
                    TextSpan(
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.85),
                      ),
                      children: [
                        TextSpan(text: isRtl ? 'السائق: ' : 'Driver: '),
                        TextSpan(
                          text: driverLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.event_seat,
                  textDirection: textDirection,
                  iconColor: colorScheme.primary,
                  child: Text(
                    (isRtl ? 'المقاعد المتاحة: ' : 'Available seats: ') +
                        availableSeats.toString(),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.attach_money,
                  textDirection: textDirection,
                  iconColor: colorScheme.onSurface.withOpacity(0.7),
                  child: Text(
                    (isRtl ? 'السعر: ' : 'Price: ') + priceLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.85),
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
                if (carDescription != null) ...[
                  const SizedBox(height: 12),
                  _InfoRow(
                    icon: Icons.directions_car_filled_outlined,
                    textDirection: textDirection,
                    iconColor: colorScheme.onSurface.withOpacity(0.7),
                    child: Text(
                      (isRtl ? 'المركبة: ' : 'Vehicle: ') + carDescription,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.schedule,
                  textDirection: textDirection,
                  iconColor: colorScheme.onSurface.withOpacity(0.6),
                  child: Text(
                    (isRtl ? 'تاريخ الإنشاء: ' : 'Created at: ') +
                        createdAtLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _buildCarDescription(bool isRtl) {
    final model = carModel?.trim();
    final color = carColor?.trim();

    if ((model == null || model.isEmpty) && (color == null || color.isEmpty)) {
      return null;
    }

    if (model != null && model.isNotEmpty && color != null && color.isNotEmpty) {
      return isRtl ? '$model - $color' : '$model • $color';
    }

    return (model != null && model.isNotEmpty) ? model : color;
  }

  String _formatCreatedAt(bool isRtl) {
    if (createdAt == null) {
      return isRtl ? 'غير متاح' : 'Not available';
    }

    final year = createdAt!.year.toString().padLeft(4, '0');
    final month = createdAt!.month.toString().padLeft(2, '0');
    final day = createdAt!.day.toString().padLeft(2, '0');
    final hour = createdAt!.hour.toString().padLeft(2, '0');
    final minute = createdAt!.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.child,
    required this.textDirection,
    this.iconColor,
  });

  final IconData icon;
  final Widget child;
  final TextDirection textDirection;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: textDirection,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.onSurface,
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(child: child),
      ],
    );
  }
}
