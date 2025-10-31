import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ride/models/ride_request.dart';
import 'package:ride/models/user_profile.dart';
import 'package:ride/widgets/user_profile_preview.dart';

import '../services/api_service.dart';
import '../services/ride_request_service.dart';

const MethodChannel _phoneLauncherChannel =
    MethodChannel('com.example.carpal_app/phone_launcher');

const Set<String> _rtlLanguageCodes = <String>{
  'ar', // Arabic
  'fa', // Persian
  'he', // Hebrew
  'ps', // Pashto
  'ur', // Urdu
  'ug', // Uyghur
  'dv', // Divehi
  'ku', // Kurdish
  'sd', // Sindhi
  'syr', // Syriac
  'yi', // Yiddish
};

bool _isRtlLanguage(String languageCode) {
  if (languageCode.isEmpty) {
    return false;
  }

  final String normalized = languageCode.toLowerCase();
  final String baseCode = normalized.split(RegExp('[-_]')).first;
  return _rtlLanguageCodes.contains(baseCode);
}

const List<String> westBankCities = [
  'رام الله',
  'البيرة',
  'نابلس',
  'جنين',
  'طولكرم',
  'قلقيلية',
  'طوباس',
  'سلفيت',
  'أريحا',
  'بيت لحم',
  'الخليل',
];

class SearchTripsScreen extends StatefulWidget {
  const SearchTripsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<SearchTripsScreen> createState() => _SearchTripsScreenState();
}

class _SearchTripsScreenState extends State<SearchTripsScreen> {
  final ApiService _apiService = ApiService();
  final RideRequestService _rideRequestService = RideRequestService();
  final List<Map<String, dynamic>> _trips = <Map<String, dynamic>>[];
  String? _selectedFromCity;
  String? _selectedToCity;
  String? _appliedFromCity;
  String? _appliedToCity;
  String? _nextCursor;
  bool _isLoading = false;
  bool _initialLoading = true;
  String? _errorMessage;
  final Set<String> _bookingInProgress = <String>{};
  final Set<String> _cancellationInProgress = <String>{};
  User? _currentUser;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<RideRequest>>? _rideRequestsSubscription;
  Map<String, RideRequest> _passengerRequests = <String, RideRequest>{};

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _subscribeToRideRequests(_currentUser?.uid);
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUser = user;
      });
      _subscribeToRideRequests(user?.uid);
    });
    unawaited(_fetchTrips(reset: true));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _rideRequestsSubscription?.cancel();
    super.dispose();
  }

  TextDirection _effectiveTextDirection(BuildContext context) {
    final Locale? locale = Localizations.maybeLocaleOf(context);
    if (locale == null) {
      return Directionality.of(context);
    }

    final String languageCode = locale.toLanguageTag();
    return _isRtlLanguage(languageCode)
        ? TextDirection.rtl
        : TextDirection.ltr;
  }

  Future<void> _fetchTrips({required bool reset}) async {
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
      final response = await _apiService.fetchTrips(
        fromCity: _appliedFromCity,
        toCity: _appliedToCity,
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

  Future<void> _onRefresh() => _fetchTrips(reset: true);

  void _subscribeToRideRequests(String? passengerId) {
    _rideRequestsSubscription?.cancel();

    final String? trimmedId = passengerId?.trim();
    if (trimmedId == null || trimmedId.isEmpty) {
      if (mounted) {
        setState(() {
          _passengerRequests = <String, RideRequest>{};
          _cancellationInProgress.clear();
        });
      } else {
        _passengerRequests = <String, RideRequest>{};
        _cancellationInProgress.clear();
      }
      return;
    }

    _rideRequestsSubscription = _rideRequestService
        .passengerRequestsStream(trimmedId)
        .listen((List<RideRequest> requests) {
      if (!mounted) {
        return;
      }

      final Map<String, RideRequest> grouped = <String, RideRequest>{};
      for (final RideRequest request in requests) {
        grouped.putIfAbsent(request.rideId, () => request);
      }

      setState(() {
        _passengerRequests = grouped;
      });
    }, onError: (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _passengerRequests = <String, RideRequest>{};
        _cancellationInProgress.clear();
      });
    });
  }

  Future<void> _submitRideRequest({
    required String tripId,
    required String driverId,
  }) async {
    final User? user = _currentUser ?? FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تسجيل الدخول للحجز.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (tripId.isEmpty || _bookingInProgress.contains(tripId)) {
      return;
    }

    if (driverId.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد السائق لهذه الرحلة.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final RideRequest? existingRequest = _passengerRequests[tripId];
    if (existingRequest != null &&
        existingRequest.status == RideRequestStatus.pending) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لديك طلب قيد الانتظار لهذه الرحلة.'),
        ),
      );
      return;
    }

    setState(() {
      _bookingInProgress.add(tripId);
    });

    try {
      final RideRequest request = await _rideRequestService.createRideRequest(
        rideId: tripId,
        driverId: driverId,
        passengerId: user.uid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final Map<String, RideRequest> updated =
            Map<String, RideRequest>.from(_passengerRequests);
        updated[tripId] = request;
        _passengerRequests = updated;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إرسال طلبك للسائق… بانتظار الموافقة'),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      final String errorMessage =
          (error.message?.isNotEmpty ?? false)
              ? error.message!
              : 'تعذر إرسال الطلب. حاول مرة أخرى لاحقًا.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إرسال الطلب. حاول مرة أخرى لاحقًا.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _bookingInProgress.remove(tripId);
      });
    }
  }

  Future<void> _cancelRideRequest({
    required String tripId,
  }) async {
    final User? user = _currentUser ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تسجيل الدخول لإدارة الطلبات.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (tripId.isEmpty || _cancellationInProgress.contains(tripId)) {
      return;
    }

    setState(() {
      _cancellationInProgress.add(tripId);
    });

    try {
      await _rideRequestService.cancelPendingRequest(
        rideId: tripId,
        passengerId: user.uid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final RideRequest? existing = _passengerRequests[tripId];
        if (existing != null) {
          final Map<String, RideRequest> updated =
              Map<String, RideRequest>.from(_passengerRequests);
          updated[tripId] = existing.copyWith(
            status: RideRequestStatus.canceledByPassenger,
            reason: 'Canceled by passenger',
          );
          _passengerRequests = updated;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء الطلب بنجاح.'),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) {
        return;
      }
      final String errorMessage =
          (error.message?.isNotEmpty ?? false)
              ? error.message!
              : 'تعذر إلغاء الطلب. حاول مرة أخرى لاحقًا.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إلغاء الطلب. حاول مرة أخرى لاحقًا.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _cancellationInProgress.remove(tripId);
      });
    }
  }

  void _showTripDetails(
    BuildContext context,
    Map<String, dynamic> data,
    String tripId,
  ) {
    final _SeatAvailability initialAvailability = _extractSeatAvailability(data);
    final DocumentReference<Map<String, dynamic>>? tripRef = tripId.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('trips').doc(tripId);

    final fromCity = (data['fromCity'] ?? data['from'] ?? '').toString();
    final toCity = (data['toCity'] ?? data['to'] ?? '').toString();
    final trimmedFromCity = fromCity.trim();
    final trimmedToCity = toCity.trim();
    final displayFromCity =
        trimmedFromCity.isEmpty ? 'غير متوفر' : trimmedFromCity;
    final displayToCity = trimmedToCity.isEmpty ? 'غير متوفر' : trimmedToCity;
    final TextDirection baseDirection = _effectiveTextDirection(context);
    final bool isRtl = baseDirection == TextDirection.rtl;
    final routeText = isRtl
        ? 'من: $displayFromCity → إلى: $displayToCity'
        : 'From: $displayFromCity → To: $displayToCity';
    final dateText = _formatDate(data['date']);
    final timeText = (data['time'] ?? '').toString();
    final priceText = _formatPrice(data['price']);
    final notesValue = data['notes'];
    final notes = notesValue == null ? null : notesValue.toString().trim();
    final String driverId = _resolveDriverId(data) ?? '';
    final String driverName = _resolveDriverName(data);
    final carModel = (data['carModel'] ?? '').toString();
    final carColor = (data['carColor'] ?? '').toString();
    final phoneNumber = (data['phoneNumber'] ?? '').toString();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: colorScheme.primary,
    );
    final valueStyle = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
    );

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        final bottomPadding = MediaQuery.of(modalContext).viewInsets.bottom;

        Future<void> launchCall() async {
          final sanitizedNumber = phoneNumber.trim();

          if (sanitizedNumber.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('رقم الهاتف غير متاح لهذه الرحلة.'),
              ),
            );
            return;
          }

          try {
            final bool? launched = await _phoneLauncherChannel.invokeMethod<bool>(
              'openDialer',
              {'phoneNumber': sanitizedNumber},
            );

            if (launched != true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تعذّر فتح تطبيق الاتصال.'),
                ),
              );
            }
          } on PlatformException catch (error) {
            debugPrint('Failed to launch dialer: $error');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تعذّر فتح تطبيق الاتصال.'),
              ),
            );
          }
        }

        void copyNumberToClipboard() {
          final sanitizedNumber = phoneNumber.trim();

          if (sanitizedNumber.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('رقم الهاتف غير متاح لهذه الرحلة.'),
              ),
            );
            return;
          }

          Clipboard.setData(ClipboardData(text: sanitizedNumber));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم نسخ رقم الهاتف إلى الحافظة.'),
            ),
          );
        }

        Widget buildDetailRow({
          required Widget leading,
          required String label,
          required String value,
          required TextDirection textDirection,
          bool isLink = false,
          VoidCallback? onTap,
        }) {
          final displayValue = value.trim().isEmpty ? 'غير متوفر' : value.trim();
          final bool isRtl = textDirection == TextDirection.rtl;
          final rowContent = Row(
            textDirection: textDirection,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: labelStyle,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayValue,
                      style: isLink
                          ? valueStyle?.copyWith(color: colorScheme.secondary)
                          : valueStyle,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                    ),
                  ],
                ),
              ),
              if (isLink)
                Icon(
                  Icons.call,
                  color: colorScheme.secondary,
                ),
            ],
          );

          final paddedRow = Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: rowContent,
          );

          if (!isLink || onTap == null) {
            return paddedRow;
          }

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            onLongPress: () {
              if (isLink) {
                copyNumberToClipboard();
              }
            },
            child: paddedRow,
          );
        }

        final bool isDriver =
            _currentUser != null && driverId == _currentUser!.uid;
        Widget seatSection;
        if (tripRef == null) {
          final bool isBooked = _currentUser != null &&
              initialAvailability.bookedUsers.contains(_currentUser!.uid);
          seatSection = _buildSeatInfoSection(
            context: modalContext,
            availability: initialAvailability,
            isDriver: isDriver,
            isBooked: isBooked,
            requiresLogin: _currentUser == null,
            isBooking: false,
            onBook: null,
          );
        } else {
          seatSection = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: tripRef.snapshots(),
            builder: (
              BuildContext context,
              AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
            ) {
              final Map<String, dynamic>? snapshotData = snapshot.data?.data();
              final _SeatAvailability availability = snapshotData != null
                  ? _extractSeatAvailability(snapshotData)
                  : initialAvailability;
              final RideRequest? request = _passengerRequests[tripId];
              final RideRequestStatus? requestStatus = request?.status;
              final bool isPendingRequest =
                  requestStatus == RideRequestStatus.pending;
              final bool isRequestAccepted =
                  requestStatus == RideRequestStatus.accepted;
              bool isBooked = false;
              if (_currentUser != null) {
                final bool isInBookedList =
                    availability.bookedUsers.contains(_currentUser!.uid);
                isBooked = isInBookedList || isRequestAccepted;
              }
              final bool requiresLogin = _currentUser == null;
              final bool isSoldOut = availability.availableSeats <= 0;
              final bool canBook =
                  !isDriver &&
                  !isBooked &&
                  !isSoldOut &&
                  !requiresLogin &&
                  !isPendingRequest;
              final bool isCancelling =
                  _cancellationInProgress.contains(tripId);

              return _buildSeatInfoSection(
                context: modalContext,
                availability: availability,
                isDriver: isDriver,
                isBooked: isBooked,
                requiresLogin: requiresLogin,
                isBooking: _bookingInProgress.contains(tripId),
                onBook: canBook
                    ? () async {
                        Navigator.of(modalContext).pop();
                        await _submitRideRequest(
                          tripId: tripId,
                          driverId: driverId,
                        );
                      }
                    : null,
                requestStatus: requestStatus,
                requestReason: request?.reason,
                onCancelRequest: isPendingRequest
                    ? () => _cancelRideRequest(tripId: tripId)
                    : null,
                isCancellingRequest: isCancelling,
              );
            },
          );
        }

        return Directionality(
          textDirection: baseDirection,
          child: SingleChildScrollView(
            padding: EdgeInsetsDirectional.only(
          start: 24,
          end: 24,
          top: 16,
          bottom: 16 + bottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    textDirection: baseDirection,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.directions_car,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          routeText,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '📅',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'التاريخ',
                  value: dateText,
                  textDirection: baseDirection,
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Icon(
                    Icons.schedule,
                    color: colorScheme.primary,
                  ),
                  label: 'الوقت',
                  value: timeText,
                  textDirection: baseDirection,
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '💰',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'السعر',
                  value: priceText,
                  textDirection: baseDirection,
                ),
                const SizedBox(height: 16),
                Directionality(
                  textDirection: baseDirection,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      textDirection: baseDirection,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '👤',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: isRtl
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'السائق',
                                style: labelStyle,
                                textAlign:
                                    isRtl ? TextAlign.right : TextAlign.left,
                              ),
                              const SizedBox(height: 8),
                              UserProfilePreview(
                                userId: driverId,
                                fallbackName: driverName,
                                avatarRadius: 26,
                                textDirection: baseDirection,
                                textStyle: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '🚙',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'موديل السيارة',
                  value: carModel,
                  textDirection: baseDirection,
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '🎨',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'لون السيارة',
                  value: carColor,
                  textDirection: baseDirection,
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Icon(
                    Icons.phone,
                    color: colorScheme.primary,
                  ),
                  label: 'رقم الهاتف',
                  value: phoneNumber,
                  isLink: true,
                  onTap: launchCall,
                  textDirection: baseDirection,
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  buildDetailRow(
                    leading: Text(
                      '📝',
                      style: theme.textTheme.titleLarge,
                    ),
                    label: 'ملاحظات',
                    value: notes,
                    textDirection: baseDirection,
                  ),
                ],
                const SizedBox(height: 16),
                seatSection,
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(modalContext).pop(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onSearchPressed() {
    final fromCity = (_selectedFromCity ?? '').trim();
    final toCity = (_selectedToCity ?? '').trim();

    setState(() {
      _appliedFromCity = fromCity.isEmpty ? null : fromCity;
      _appliedToCity = toCity.isEmpty ? null : toCity;
    });

    unawaited(_fetchTrips(reset: true));
  }

  void _loadAllTrips() {
    setState(() {
      _appliedFromCity = null;
      _appliedToCity = null;
    });

    unawaited(_fetchTrips(reset: true));
  }

  void _resetFilters() {
    setState(() {
      _selectedFromCity = null;
      _selectedToCity = null;
    });

    _loadAllTrips();
  }

  void _loadMoreTrips() {
    if (_isLoading || _nextCursor == null) {
      return;
    }

    unawaited(_fetchTrips(reset: false));
  }

  Widget _buildFilters(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final TextDirection textDirection = Directionality.of(context);
    final bool isRtl = textDirection == TextDirection.rtl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: colorScheme.surface.withOpacity(0.95),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment:
                    isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  'البحث عن الرحلات',
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                textDirection: textDirection,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedFromCity,
                      alignment: AlignmentDirectional.centerStart,
                      decoration: const InputDecoration(
                        labelText: 'من',
                        border: OutlineInputBorder(),
                        floatingLabelAlignment: FloatingLabelAlignment.start,
                      ),
                      items: westBankCities
                          .map(
                            (city) => DropdownMenuItem<String>(
                              value: city,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                city,
                                textAlign:
                                    isRtl ? TextAlign.right : TextAlign.left,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedFromCity = value;
                        });
                      },
                      isExpanded: true,
                      hint: Align(
                        alignment:
                            isRtl ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          'اختر مدينة الانطلاق',
                          textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedToCity,
                      alignment: AlignmentDirectional.centerStart,
                      decoration: const InputDecoration(
                        labelText: 'إلى',
                        border: OutlineInputBorder(),
                        floatingLabelAlignment: FloatingLabelAlignment.start,
                      ),
                      items: westBankCities
                          .map(
                            (city) => DropdownMenuItem<String>(
                              value: city,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                city,
                                textAlign:
                                    isRtl ? TextAlign.right : TextAlign.left,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedToCity = value;
                        });
                      },
                      isExpanded: true,
                      hint: Align(
                        alignment:
                            isRtl ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          'اختر مدينة الوصول',
                          textAlign: isRtl ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _onSearchPressed,
                  child: const Text('بحث'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة التعيين'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.deepPurple,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = [
      const Color(0xFFEDE7F6),
      Theme.of(context).colorScheme.primary.withOpacity(0.08),
      const Color(0xFFD1C4E9),
    ];

    final TextDirection effectiveDirection =
        _effectiveTextDirection(context);
    final bool isRtl = effectiveDirection == TextDirection.rtl;

    final body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: Theme.of(context).colorScheme.primary,
          child: _buildTripList(context),
        ),
      ),
    );

    final Widget content = widget.showAppBar
        ? Scaffold(
            appBar: AppBar(
              leading:
                  Navigator.of(context).canPop() ? const BackButton() : null,
              titleSpacing: 0,
              title: Align(
                alignment:
                    isRtl ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  'البحث عن الرحلات',
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
              ),
              centerTitle: false,
            ),
            body: body,
          )
        : body;

    return Directionality(
      textDirection: effectiveDirection,
      child: content,
    );
  }

  Widget _buildTripList(BuildContext context) {
    final List<Widget> children = <Widget>[_buildFilters(context)];

    if (_initialLoading) {
      children.add(
        const SizedBox(
          height: 280,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    } else if (_errorMessage != null) {
      children.addAll([
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.25,
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
          onPressed: () => _fetchTrips(reset: true),
          child: const Text('إعادة المحاولة'),
        ),
      ]);
    } else if (_trips.isEmpty) {
      children.add(
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.3,
          child: Center(
            child: Text(
              'لا توجد رحلات مطابقة حاليًا.',
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
      );
    } else {
      for (final Map<String, dynamic> data in _trips) {
        final String fromCity = (data['fromCity'] ?? '').toString().trim();
        final String toCity = (data['toCity'] ?? '').toString().trim();
        final String dateText = _formatDate(data['date']);
        final String priceText = _formatPrice(data['price']);
        final String driverId = _resolveDriverId(data) ?? '';
        final String driverName = _resolveDriverName(data);
        final String tripId = (data['id'] ?? data['tripId'] ?? '').toString();
        final _SeatAvailability initialAvailability = _extractSeatAvailability(data);
        final bool isDriver =
            _currentUser != null && driverId.isNotEmpty && driverId == _currentUser!.uid;

        Widget cardContent;

        if (tripId.isEmpty) {
          final bool isBooked = _currentUser != null &&
              initialAvailability.bookedUsers.contains(_currentUser!.uid);
          final bool isSoldOut = initialAvailability.availableSeats <= 0;
          cardContent = TripCard(
            fromCity: fromCity.isEmpty ? 'غير متوفر' : fromCity,
            toCity: toCity.isEmpty ? 'غير متوفر' : toCity,
            date: dateText.isEmpty ? 'غير متوفر' : dateText,
            price: priceText,
            driverId: driverId,
            driverName: driverName,
            availableSeats: initialAvailability.availableSeats,
            totalSeats: initialAvailability.totalSeats,
            isBooked: isBooked,
            isSoldOut: isSoldOut,
            isOwnTrip: isDriver,
            requiresLogin: _currentUser == null,
            isBooking: false,
            notes: (data['notes'] ?? '').toString().trim().isEmpty
                ? null
                : (data['notes'] ?? '').toString(),
            onTap: () => _showTripDetails(context, data, tripId),
            onBook: null,
          );
        } else {
          cardContent = StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('trips').doc(tripId).snapshots(),
            builder: (
              BuildContext context,
              AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
            ) {
              final Map<String, dynamic>? snapshotData = snapshot.data?.data();
              final _SeatAvailability availability = snapshotData != null
                  ? _extractSeatAvailability(snapshotData)
                  : initialAvailability;
              final RideRequest? request = _passengerRequests[tripId];
              final RideRequestStatus? requestStatus = request?.status;
              final bool isPendingRequest =
                  requestStatus == RideRequestStatus.pending;
              final bool isRequestAccepted =
                  requestStatus == RideRequestStatus.accepted;
              bool isBooked = false;
              if (_currentUser != null) {
                final bool isInBookedList =
                    availability.bookedUsers.contains(_currentUser!.uid);
                isBooked = isInBookedList || isRequestAccepted;
              }
              final bool isSoldOut = availability.availableSeats <= 0;
              final bool requiresLogin = _currentUser == null;
              final bool canBook =
                  !isDriver &&
                  !isBooked &&
                  !isSoldOut &&
                  !requiresLogin &&
                  !isPendingRequest;
              final bool isCancelling =
                  _cancellationInProgress.contains(tripId);

              return TripCard(
                fromCity: fromCity.isEmpty ? 'غير متوفر' : fromCity,
                toCity: toCity.isEmpty ? 'غير متوفر' : toCity,
                date: dateText.isEmpty ? 'غير متوفر' : dateText,
                price: priceText,
                driverId: driverId,
                driverName: driverName,
                availableSeats: availability.availableSeats,
                totalSeats: availability.totalSeats,
                isBooked: isBooked,
                isSoldOut: isSoldOut,
                isOwnTrip: isDriver,
                requiresLogin: requiresLogin,
                isBooking: _bookingInProgress.contains(tripId),
                notes: (data['notes'] ?? '').toString().trim().isEmpty
                    ? null
                    : (data['notes'] ?? '').toString(),
                onTap: () => _showTripDetails(context, data, tripId),
                onBook: canBook
                    ? () => _submitRideRequest(
                          tripId: tripId,
                          driverId: driverId,
                        )
                    : null,
                requestStatus: requestStatus,
                requestReason: request?.reason,
                onCancelRequest: isPendingRequest
                    ? () => _cancelRideRequest(tripId: tripId)
                    : null,
                isCancellingRequest: isCancelling,
              );
            },
          );
        }

        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: cardContent,
          ),
        );
      }
    }

    if (_nextCursor != null) {
      children.add(
        _isLoading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton.icon(
                  onPressed: _loadMoreTrips,
                  icon: const Icon(Icons.expand_more),
                  label: const Text('تحميل المزيد'),
                ),
              ),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
      children: children,
    );
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    final String text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }
    return text;
  }

  int _parseSeatCount(dynamic value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }
    if (value is num) {
      final int parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }
    final int? parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) {
      return 0;
    }
    return parsed;
  }

  List<String> _parseBookedUsers(dynamic value) {
    if (value is List) {
      return value
          .map((dynamic item) => item?.toString() ?? '')
          .map((String userId) => userId.trim())
          .where((String userId) => userId.isNotEmpty)
          .toList(growable: false);
    }
    return <String>[];
  }

  _SeatAvailability _extractSeatAvailability(Map<String, dynamic>? data) {
    if (data == null) {
      return const _SeatAvailability(
        totalSeats: 0,
        availableSeats: 0,
        bookedUsers: <String>[],
      );
    }

    final List<String> bookedUsers = _parseBookedUsers(data['bookedUsers']);
    final int availableSeats = _parseSeatCount(data['availableSeats']);
    final int totalSeats = _parseSeatCount(data['totalSeats']);
    final int computedTotal = totalSeats > 0
        ? totalSeats
        : bookedUsers.length + availableSeats;
    final int ensuredTotal = computedTotal < bookedUsers.length
        ? bookedUsers.length
        : computedTotal;
    final int remainingCapacity = ensuredTotal - bookedUsers.length;
    final int sanitizedAvailable = availableSeats > remainingCapacity
        ? remainingCapacity
        : availableSeats;

    return _SeatAvailability(
      totalSeats: ensuredTotal,
      availableSeats: sanitizedAvailable < 0 ? 0 : sanitizedAvailable,
      bookedUsers: bookedUsers,
    );
  }

  Widget _buildSeatInfoSection({
    required BuildContext context,
    required _SeatAvailability availability,
    required bool isDriver,
    required bool isBooked,
    required bool requiresLogin,
    required bool isBooking,
    required VoidCallback? onBook,
    RideRequestStatus? requestStatus,
    String? requestReason,
    VoidCallback? onCancelRequest,
    bool isCancellingRequest = false,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextDirection direction = Directionality.of(context);
    final bool isRtl = direction == TextDirection.rtl;
    final bool isSoldOut = availability.availableSeats <= 0;
    final bool bookingUnavailable =
        onBook == null && !isDriver && !isBooked && !requiresLogin && !isSoldOut;
    final RideRequestStatus? status = requestStatus;
    final bool isPendingRequest = status == RideRequestStatus.pending;
    final bool isAcceptedRequest = status == RideRequestStatus.accepted;
    final bool isRejectedRequest = status == RideRequestStatus.rejected;

    final ButtonStyle purpleButtonStyle = FilledButton.styleFrom(
      backgroundColor: const Color(0xFF6A1B9A),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );

    final ButtonStyle fullButtonStyle = FilledButton.styleFrom(
      backgroundColor: Colors.grey.shade400,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ).copyWith(
      backgroundColor: MaterialStateProperty.resolveWith(
        (Set<MaterialState> states) => Colors.grey.shade400,
      ),
      foregroundColor: MaterialStateProperty.resolveWith(
        (Set<MaterialState> states) => Colors.white.withOpacity(
          states.contains(MaterialState.disabled) ? 0.9 : 1,
        ),
      ),
    );

    Widget buildBookingButton() {
      if (isSoldOut) {
        return FilledButton.icon(
          onPressed: null,
          style: fullButtonStyle,
          icon: const Icon(Icons.event_busy),
          label: Text(isRtl ? 'مكتملة' : 'Full'),
        );
      }

      final String bookingLabel = isRtl ? 'احجز الآن' : 'Book Now';
      final String bookingInProgressLabel =
          isRtl ? 'جاري الحجز...' : 'Booking...';

      return FilledButton.icon(
        onPressed: (isBooking || onBook == null) ? null : onBook,
        style: purpleButtonStyle,
        icon: isBooking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.event_seat),
        label: Text(isBooking ? bookingInProgressLabel : bookingLabel),
      );
    }

    late final Widget action;

    if (isDriver) {
      action = _StatusBadge(
        color: Colors.orange.shade700,
        icon: Icons.directions_car_filled,
        text: 'هذه رحلتك',
      );
    } else if (isPendingRequest) {
      final String cancelLabel = isCancellingRequest
          ? (isRtl ? 'جاري الإلغاء...' : 'Cancelling...')
          : (isRtl ? 'إلغاء الطلب' : 'Cancel Request');

      action = Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StatusBadge(
            color: Colors.amber.shade700,
            icon: Icons.hourglass_top,
            text: 'بانتظار موافقة السائق…',
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: (isCancellingRequest || onCancelRequest == null)
                ? null
                : onCancelRequest,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade600,
            ),
            icon: isCancellingRequest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(cancelLabel),
          ),
        ],
      );
    } else if (isAcceptedRequest) {
      action = _StatusBadge(
        color: Colors.green.shade700,
        icon: Icons.check_circle_outline,
        text: 'تمت الموافقة ✅',
      );
    } else if (isRejectedRequest) {
      final String sanitizedReason =
          (requestReason?.trim().isNotEmpty ?? false)
              ? requestReason!.trim()
              : 'غير مذكور';
      final Widget rejectionChip = _RejectionStatusBadge(
        text: 'تم رفض الطلب ❌ – السبب: $sanitizedReason',
      );

      if (onBook != null || isSoldOut) {
        action = Column(
          crossAxisAlignment:
              isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            rejectionChip,
            const SizedBox(height: 8),
            buildBookingButton(),
          ],
        );
      } else {
        action = rejectionChip;
      }
    } else if (isBooked) {
      action = _StatusBadge(
        color: Colors.green.shade700,
        icon: Icons.check_circle_outline,
        text: 'تم تأكيد حجزك',
      );
    } else if (requiresLogin) {
      action = _StatusBadge(
        color: colorScheme.primary,
        icon: Icons.lock_outline,
        text: 'سجّل الدخول للحجز',
      );
    } else if (bookingUnavailable) {
      action = _StatusBadge(
        color: colorScheme.onSurface.withOpacity(0.7),
        icon: Icons.info_outline,
        text: 'الحجز غير متاح لهذه الرحلة',
      );
    } else {
      action = buildBookingButton();
    }

    final String seatLabel = isRtl
        ? 'عدد المقاعد المتاحة: ${availability.availableSeats}'
        : 'Available seats: ${availability.availableSeats}';

    return Column(
      crossAxisAlignment: isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          textDirection: direction,
          children: <Widget>[
            Icon(
              Icons.event_seat,
              color: colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                seatLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment:
              isRtl ? Alignment.centerRight : Alignment.centerLeft,
          child: action,
        ),
      ],
    );
  }

  String? _resolveDriverId(Map<String, dynamic> data) {
    final String? direct = _stringOrNull(data['driverId']);
    if (direct != null) {
      return direct;
    }

    final String? snakeCase = _stringOrNull(data['driver_id']);
    if (snakeCase != null) {
      return snakeCase;
    }

    final String? camelCase = _stringOrNull(data['driverID']);
    if (camelCase != null) {
      return camelCase;
    }

    final dynamic driverData = data['driver'];
    if (driverData is Map) {
      final Map<String, dynamic> driverMap = driverData.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final String? nestedId = _stringOrNull(driverMap['id']) ??
          _stringOrNull(driverMap['uid']) ??
          _stringOrNull(driverMap['userId']) ??
          _stringOrNull(driverMap['user_id']);
      if (nestedId != null) {
        return nestedId;
      }
    }

    return _stringOrNull(driverData);
  }

  String _resolveDriverName(Map<String, dynamic> data) {
    final String? direct = _stringOrNull(data['driverName']);
    if (direct != null) {
      return UserProfile.sanitizeDisplayName(direct);
    }

    final dynamic driverData = data['driver'];
    if (driverData is Map) {
      final Map<String, dynamic> driverMap = driverData.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final String? nestedName = _stringOrNull(driverMap['displayName']) ??
          _stringOrNull(driverMap['name']) ??
          _stringOrNull(driverMap['fullName']) ??
          _stringOrNull(driverMap['username']);
      if (nestedName != null) {
        return UserProfile.sanitizeDisplayName(nestedName);
      }
    }

    if (driverData is String) {
      final String? text = _stringOrNull(driverData);
      if (text != null) {
        return UserProfile.sanitizeDisplayName(text);
      }
    }

    return 'مستخدم';
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      final trimmed = date.trim();
      if (trimmed.isEmpty) {
        return '';
      }

      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return '${_twoDigits(parsed.day)}.${_twoDigits(parsed.month)}.${parsed.year}';
      }

      return trimmed;
    }

    if (date is DateTime) {
      return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
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

class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.fromCity,
    required this.toCity,
    required this.date,
    required this.price,
    required this.driverId,
    required this.driverName,
    required this.availableSeats,
    required this.totalSeats,
    required this.isBooked,
    required this.isSoldOut,
    required this.isOwnTrip,
    required this.requiresLogin,
    required this.isBooking,
    this.notes,
    this.onTap,
    this.onBook,
    this.requestStatus,
    this.requestReason,
    this.onCancelRequest,
    this.isCancellingRequest = false,
  });

  final String fromCity;
  final String toCity;
  final String date;
  final String price;
  final String driverId;
  final String driverName;
  final int availableSeats;
  final int totalSeats;
  final bool isBooked;
  final bool isSoldOut;
  final bool isOwnTrip;
  final bool requiresLogin;
  final bool isBooking;
  final String? notes;
  final VoidCallback? onTap;
  final VoidCallback? onBook;
  final RideRequestStatus? requestStatus;
  final String? requestReason;
  final VoidCallback? onCancelRequest;
  final bool isCancellingRequest;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final TextDirection textDirection = Directionality.of(context);
    final bool isRtl = textDirection == TextDirection.rtl;

    final Color dividerColor = colorScheme.onSurface.withOpacity(0.08);
    final TextStyle driverLabelStyle = textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
          letterSpacing: 0.3,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        );

    final TextStyle routeTextStyle = textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: (textTheme.titleMedium?.fontSize ?? 16) + 1,
          color: colorScheme.onSurface,
        ) ??
        TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 17,
          color: colorScheme.onSurface,
        );

    final TextStyle notesStyle = textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
          height: 1.4,
        ) ??
        TextStyle(
          color: colorScheme.onSurface.withOpacity(0.7),
          height: 1.4,
        );

    final List<Widget> columnChildren = <Widget>[];

    final bool hasDriverInfo =
        driverId.trim().isNotEmpty || driverName.trim().isNotEmpty;
    if (hasDriverInfo) {
      columnChildren.addAll([
        Align(
          alignment: isRtl ? Alignment.topRight : Alignment.topLeft,
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'السائق',
                style: driverLabelStyle,
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 6),
              UserProfilePreview(
                userId: driverId,
                fallbackName: driverName,
                avatarRadius: 22,
                textDirection: textDirection,
                textStyle: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: (textTheme.titleMedium?.fontSize ?? 16) + 2,
                      color: colorScheme.onSurface,
                    ) ??
                    TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
      ]);
    }

    columnChildren.addAll([
      Row(
        textDirection: textDirection,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Icon(
            Icons.directions_car,
            color: colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isRtl
                  ? 'من $fromCity → إلى $toCity'
                  : 'From $fromCity → To $toCity',
              style: routeTextStyle,
              overflow: TextOverflow.ellipsis,
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Divider(
        height: 1,
        color: dividerColor,
      ),
      const SizedBox(height: 16),
      Align(
        alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: textDirection,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              price,
              style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ) ??
                  TextStyle(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
            const SizedBox(width: 18),
            Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: textDirection,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.event,
                  color: colorScheme.onSurface.withOpacity(0.7),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  date,
                  style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ) ??
                      TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                  textAlign: isRtl ? TextAlign.right : TextAlign.left,
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Row(
        textDirection: textDirection,
        children: [
          Icon(
            Icons.event_seat,
            color: colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isRtl
                  ? 'عدد المقاعد المتاحة: $availableSeats'
                  : 'Available seats: $availableSeats',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ),
        ],
      ),
    ]);

    if (notes != null && notes!.trim().isNotEmpty) {
      columnChildren.addAll([
        const SizedBox(height: 16),
        Text(
          notes!,
          style: notesStyle,
          textAlign: isRtl ? TextAlign.right : TextAlign.left,
        ),
      ]);
    }

    columnChildren.add(const SizedBox(height: 16));

    final AlignmentDirectional actionAlignment =
        isRtl ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart;

    columnChildren.add(
      Align(
        alignment: actionAlignment,
        child: _buildBookingAction(context),
      ),
    );

    return Directionality(
      textDirection: textDirection,
      child: Card(
        elevation: 4,
        shadowColor: colorScheme.shadow.withOpacity(0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        color: colorScheme.surface.withOpacity(0.96),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsetsDirectional.symmetric(horizontal: 22, vertical: 18),
            child: Column(
              crossAxisAlignment:
                  isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: columnChildren,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookingAction(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextDirection direction = Directionality.of(context);
    final bool isRtl = direction == TextDirection.rtl;

    if (isOwnTrip) {
      return _StatusBadge(
        color: Colors.orange.shade700,
        icon: Icons.directions_car_filled,
        text: 'هذه رحلتك',
      );
    }

    final RideRequestStatus? status = requestStatus;
    final bool isPendingRequest = status == RideRequestStatus.pending;
    final bool isAcceptedRequest = status == RideRequestStatus.accepted;
    final bool isRejectedRequest = status == RideRequestStatus.rejected;
    final bool bookingUnavailable = onBook == null &&
        !isOwnTrip &&
        !isBooked &&
        !requiresLogin &&
        !isSoldOut &&
        !isPendingRequest;

    final ButtonStyle purpleButtonStyle = FilledButton.styleFrom(
      backgroundColor: const Color(0xFF6A1B9A),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );

    final ButtonStyle fullButtonStyle = FilledButton.styleFrom(
      backgroundColor: Colors.grey.shade400,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ).copyWith(
      backgroundColor: MaterialStateProperty.resolveWith(
        (Set<MaterialState> states) => Colors.grey.shade400,
      ),
      foregroundColor: MaterialStateProperty.resolveWith(
        (Set<MaterialState> states) => Colors.white.withOpacity(
          states.contains(MaterialState.disabled) ? 0.9 : 1,
        ),
      ),
    );

    Widget buildBookingButton() {
      if (isSoldOut) {
        return FilledButton.icon(
          onPressed: null,
          style: fullButtonStyle,
          icon: const Icon(Icons.event_busy),
          label: Text(isRtl ? 'مكتملة' : 'Full'),
        );
      }

      final String bookingLabel = isRtl ? 'احجز الآن' : 'Book Now';
      final String bookingInProgressLabel =
          isRtl ? 'جاري الحجز...' : 'Booking...';

      return FilledButton.icon(
        onPressed: (isBooking || onBook == null) ? null : onBook,
        style: purpleButtonStyle,
        icon: isBooking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.event_seat),
        label: Text(isBooking ? bookingInProgressLabel : bookingLabel),
      );
    }

    if (isPendingRequest) {
      final String cancelLabel = isCancellingRequest
          ? (isRtl ? 'جاري الإلغاء...' : 'Cancelling...')
          : (isRtl ? 'إلغاء الطلب' : 'Cancel Request');

      return Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StatusBadge(
            color: Colors.amber.shade700,
            icon: Icons.hourglass_top,
            text: 'تم إرسال طلبك للسائق… بانتظار الموافقة',
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: (isCancellingRequest || onCancelRequest == null)
                ? null
                : onCancelRequest,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade600,
            ),
            icon: isCancellingRequest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cancel_outlined),
            label: Text(cancelLabel),
          ),
        ],
      );
    }

    if (isAcceptedRequest) {
      return _StatusBadge(
        color: Colors.green.shade700,
        icon: Icons.check_circle_outline,
        text: 'تمت الموافقة ✅',
      );
    }

    if (isBooked) {
      return _StatusBadge(
        color: Colors.green.shade700,
        icon: Icons.check_circle_outline,
        text: 'تم تأكيد حجزك',
      );
    }

    if (requiresLogin) {
      return _StatusBadge(
        color: colorScheme.primary,
        icon: Icons.lock_outline,
        text: 'سجّل الدخول للحجز',
      );
    }

    if (isRejectedRequest) {
      final String sanitizedReason =
          (requestReason?.trim().isNotEmpty ?? false)
              ? requestReason!.trim()
              : 'غير مذكور';
      final Widget rejectionChip = _RejectionStatusBadge(
        text: 'تم رفض الطلب ❌ – السبب: $sanitizedReason',
      );

      if (onBook != null || isSoldOut) {
        return Column(
          crossAxisAlignment:
              isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            rejectionChip,
            const SizedBox(height: 8),
            buildBookingButton(),
          ],
        );
      }

      return rejectionChip;
    }

    if (bookingUnavailable) {
      return _StatusBadge(
        color: colorScheme.onSurface.withOpacity(0.7),
        icon: Icons.info_outline,
        text: 'الحجز غير متاح لهذه الرحلة',
      );
    }

    return buildBookingButton();
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.color,
    required this.text,
    required this.icon,
  });

  final Color color;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextDirection direction = Directionality.of(context);
    final bool isRtl = direction == TextDirection.rtl;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 18),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
          ),
        ],
      ),
    );
  }
}

class _RejectionStatusBadge extends StatelessWidget {
  const _RejectionStatusBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextDirection direction = Directionality.of(context);
    final bool isRtl = direction == TextDirection.rtl;
    final Color color = Colors.red.shade600;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        textDirection: direction,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cancel_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatAvailability {
  const _SeatAvailability({
    required this.totalSeats,
    required this.availableSeats,
    required this.bookedUsers,
  });

  final int totalSeats;
  final int availableSeats;
  final List<String> bookedUsers;
}
