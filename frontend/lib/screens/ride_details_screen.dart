import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ride/models/ride_request.dart';
import 'package:ride/models/user_profile.dart';
import 'package:ride/services/ride_request_service.dart';
import 'package:ride/services/user_profile_cache.dart';

class RideDetailsArguments {
  RideDetailsArguments({
    required this.tripId,
    required this.fromCity,
    required this.toCity,
    required this.tripDate,
    required this.tripTime,
    required this.driverName,
    required this.availableSeats,
    required this.price,
    this.driverId,
    this.carModel,
    this.carColor,
    this.createdAt,
  });

  final String tripId;
  final String fromCity;
  final String toCity;
  final String tripDate;
  final String tripTime;
  final String driverName;
  final int availableSeats;
  final String price;
  final String? driverId;
  final String? carModel;
  final String? carColor;
  final DateTime? createdAt;
}

class RideDetailsScreen extends StatefulWidget {
  const RideDetailsScreen({super.key, required this.arguments});

  final RideDetailsArguments arguments;

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  final RideRequestService _rideRequestService = RideRequestService();
  late final String _driverId;
  late final Stream<List<RideRequest>> _requestsStream;

  @override
  void initState() {
    super.initState();
    _driverId = _resolveDriverId();
    _requestsStream = _buildRequestsStream();
  }

  String _resolveDriverId() {
    final String? argumentDriverId = widget.arguments.driverId?.trim();
    if (argumentDriverId != null && argumentDriverId.isNotEmpty) {
      return argumentDriverId;
    }
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) {
      return '';
    }
    return currentUserId.trim();
  }

  Stream<List<RideRequest>> _buildRequestsStream() {
    final String tripId = widget.arguments.tripId.trim();
    if (tripId.isEmpty || _driverId.isEmpty) {
      return Stream<List<RideRequest>>.value(const <RideRequest>[]);
    }

    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    return firestore
        .collection('ride_requests')
        .where('driver_id', isEqualTo: _driverId)
        .where('ride_id', isEqualTo: tripId)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((QuerySnapshot<Map<String, dynamic>> snapshot) {
      return snapshot.docs
          .map(RideRequest.fromQuerySnapshot)
          .toList(growable: false);
    });
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade600 : null,
      ),
    );
  }

  Future<void> _acceptRequest(RideRequest request) async {
    final String requestId = request.id.trim();
    if (requestId.isEmpty) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
      return;
    }

    try {
      await _rideRequestService.acceptRideRequest(
        rideId: widget.arguments.tripId,
        requestId: requestId,
      );
      _showSnack('تم تحديث الطلب بنجاح ✅');
    } on RideRequestException catch (error) {
      if (error.code == 'not_enough_seats') {
        _showSnack('لا توجد مقاعد كافية', error: true);
      } else {
        _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
      }
    } on FirebaseException catch (_) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
    } catch (_) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
    }
  }

  Future<void> _rejectRequest(RideRequest request) async {
    final String requestId = request.id.trim();
    if (requestId.isEmpty) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
      return;
    }

    final String? reason = await _promptRejectionReason();
    if (reason == null) {
      return;
    }

    try {
      await _rideRequestService.rejectRideRequest(
        requestId: requestId,
        reason: reason,
      );
      _showSnack('تم تحديث الطلب بنجاح ✅');
    } on FirebaseException catch (_) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
    } catch (_) {
      _showSnack('تعذر تحديث الطلب، حاول مرة أخرى لاحقاً', error: true);
    }
  }

  Future<String?> _promptRejectionReason() async {
    final TextEditingController controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            title: const Text('سبب الرفض'),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب سبب الرفض...',
              ),
              textDirection: Directionality.of(context),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('إرسال'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection textDirection = Directionality.of(context);
    final bool isRtl = textDirection == TextDirection.rtl;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final List<Color> gradientColors = <Color>[
      const Color(0xFFEDE7F6),
      colorScheme.primary.withOpacity(0.08),
      const Color(0xFFD1C4E9),
    ];

    final String tripId = widget.arguments.tripId.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(isRtl ? 'تفاصيل الرحلة' : 'Ride Details'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: tripId.isEmpty || _driverId.isEmpty
              ? _CenteredMessage(
                  message: isRtl
                      ? 'تعذر تحميل تفاصيل الطلبات لهذه الرحلة.'
                      : 'Unable to load requests for this ride.',
                )
              : StreamBuilder<List<RideRequest>>(
                  stream: _requestsStream,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<List<RideRequest>> snapshot,
                  ) {
                    if (snapshot.hasError) {
                      return _CenteredMessage(
                        message: isRtl
                            ? 'حدث خطأ أثناء تحميل الطلبات. حاول مرة أخرى لاحقاً.'
                            : 'Failed to load requests. Please try again later.',
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<RideRequest> requests =
                        snapshot.data ?? const <RideRequest>[];

                    final List<RideRequest> acceptedRequests = requests
                        .where((RideRequest request) =>
                            request.status == RideRequestStatus.accepted)
                        .toList(growable: false);
                    final List<RideRequest> pendingRequests = requests
                        .where((RideRequest request) =>
                            request.status == RideRequestStatus.pending)
                        .toList(growable: false);

                    return SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _RideSummaryCard(
                            arguments: widget.arguments,
                            textDirection: textDirection,
                          ),
                          const SizedBox(height: 24),
                          _RequestsSection(
                            title: 'الركاب المؤكدة',
                            textDirection: textDirection,
                            emptyLabel: isRtl
                                ? 'لا يوجد ركاب مقبولون حالياً.'
                                : 'No accepted passengers yet.',
                            children: acceptedRequests
                                .map((RideRequest request) =>
                                    _AcceptedRequestTile(
                                      request: request,
                                      textDirection: textDirection,
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 24),
                          _RequestsSection(
                            title: 'الطلبات المعلقة',
                            textDirection: textDirection,
                            emptyLabel: isRtl
                                ? 'لا توجد طلبات معلقة حالياً.'
                                : 'No pending requests right now.',
                            children: pendingRequests
                                .map((RideRequest request) =>
                                    _PendingRequestTile(
                                      request: request,
                                      textDirection: textDirection,
                                      onApprove: () => _acceptRequest(request),
                                      onReject: () => _rejectRequest(request),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _RequestsSection extends StatelessWidget {
  const _RequestsSection({
    required this.title,
    required this.children,
    required this.textDirection,
    required this.emptyLabel,
  });

  final String title;
  final List<Widget> children;
  final TextDirection textDirection;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final bool isRtl = textDirection == TextDirection.rtl;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: textDirection,
      child: Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                emptyLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            )
          else
            Column(
              children: <Widget>[
                for (int index = 0; index < children.length; index++) ...<Widget>[
                  children[index],
                  if (index < children.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AcceptedRequestTile extends StatefulWidget {
  const _AcceptedRequestTile({
    required this.request,
    required this.textDirection,
  });

  final RideRequest request;
  final TextDirection textDirection;

  @override
  State<_AcceptedRequestTile> createState() => _AcceptedRequestTileState();
}

class _AcceptedRequestTileState extends State<_AcceptedRequestTile> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final String passengerId = widget.request.passengerId.trim();
    if (passengerId.isEmpty) {
      return;
    }

    final UserProfile? cached = UserProfileCache.get(passengerId);
    if (cached != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = cached;
      });
      return;
    }

    if (UserProfileCache.hasEntry(passengerId)) {
      return;
    }

    final UserProfile? fetched = await UserProfileCache.fetch(passengerId);
    if (!mounted || fetched == null) {
      return;
    }
    setState(() {
      _profile = fetched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isRtl = widget.textDirection == TextDirection.rtl;

    final String passengerName = _resolvePassengerName();
    final String? phone = _resolvePhone();

    return Directionality(
      textDirection: widget.textDirection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment:
                  isRtl ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.verified, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    passengerName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: isRtl ? TextAlign.right : TextAlign.left,
                  ),
                ),
              ],
            ),
            if (phone != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '${isRtl ? 'رقم الجوال' : 'Phone'}: $phone',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${isRtl ? 'المقاعد المحجوزة' : 'Seats booked'}: ${widget.request.seatsRequested}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ],
        ),
      ),
    );
  }

  String _resolvePassengerName() {
    final UserProfile? profile = _profile ??
        UserProfileCache.get(widget.request.passengerId.trim());
    if (profile != null) {
      final String sanitized =
          UserProfile.sanitizeDisplayName(profile.displayName);
      if (sanitized.isNotEmpty && sanitized != 'مستخدم') {
        return sanitized;
      }
      final String? phone = profile.phone?.trim();
      if (phone != null && phone.isNotEmpty) {
        return phone;
      }
    }

    final String fallback = widget.request.passengerId.trim();
    return fallback.isEmpty ? 'مستخدم' : fallback;
  }

  String? _resolvePhone() {
    final UserProfile? profile = _profile ??
        UserProfileCache.get(widget.request.passengerId.trim());
    final String? phone = profile?.phone;
    if (phone == null) {
      return null;
    }
    final String trimmed = phone.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _PendingRequestTile extends StatefulWidget {
  const _PendingRequestTile({
    required this.request,
    required this.textDirection,
    required this.onApprove,
    required this.onReject,
  });

  final RideRequest request;
  final TextDirection textDirection;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  State<_PendingRequestTile> createState() => _PendingRequestTileState();
}

class _PendingRequestTileState extends State<_PendingRequestTile> {
  UserProfile? _profile;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final String passengerId = widget.request.passengerId.trim();
    if (passengerId.isEmpty) {
      return;
    }

    final UserProfile? cached = UserProfileCache.get(passengerId);
    if (cached != null) {
      setState(() {
        _profile = cached;
      });
      return;
    }

    if (UserProfileCache.hasEntry(passengerId)) {
      return;
    }

    final UserProfile? fetched = await UserProfileCache.fetch(passengerId);
    if (!mounted || fetched == null) {
      return;
    }
    setState(() {
      _profile = fetched;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isRtl = widget.textDirection == TextDirection.rtl;

    final String passengerName = _resolvePassengerName();
    final String? phone = _resolvePhone();

    return Directionality(
      textDirection: widget.textDirection,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.secondary.withOpacity(0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              passengerName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
            if (phone != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '${isRtl ? 'رقم الجوال' : 'Phone'}: $phone',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: isRtl ? TextAlign.right : TextAlign.left,
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${isRtl ? 'عدد المقاعد المطلوبة' : 'Seats requested'}: ${widget.request.seatsRequested}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: widget.textDirection,
              children: <Widget>[
                FilledButton(
                  onPressed: _isProcessing ? null : _handleApprove,
                  child: _isProcessing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : const Text('موافقة'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isProcessing ? null : _handleReject,
                  child: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('رفض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleApprove() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    await widget.onApprove();
    if (!mounted) {
      return;
    }
    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _handleReject() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    await widget.onReject();
    if (!mounted) {
      return;
    }
    setState(() {
      _isProcessing = false;
    });
  }

  String _resolvePassengerName() {
    final UserProfile? profile = _profile ??
        UserProfileCache.get(widget.request.passengerId.trim());
    if (profile != null) {
      final String sanitized =
          UserProfile.sanitizeDisplayName(profile.displayName);
      if (sanitized.isNotEmpty && sanitized != 'مستخدم') {
        return sanitized;
      }
      final String? phone = profile.phone?.trim();
      if (phone != null && phone.isNotEmpty) {
        return phone;
      }
    }

    final String fallback = widget.request.passengerId.trim();
    return fallback.isEmpty ? 'مستخدم' : fallback;
  }

  String? _resolvePhone() {
    final UserProfile? profile = _profile ??
        UserProfileCache.get(widget.request.passengerId.trim());
    final String? phone = profile?.phone;
    if (phone == null) {
      return null;
    }
    final String trimmed = phone.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _RideSummaryCard extends StatelessWidget {
  const _RideSummaryCard({
    required this.arguments,
    required this.textDirection,
  });

  final RideDetailsArguments arguments;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final bool isRtl = textDirection == TextDirection.rtl;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;

    final String fromCityLabel = arguments.fromCity.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : arguments.fromCity;
    final String toCityLabel = arguments.toCity.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : arguments.toCity;
    final String dateLabel = arguments.tripDate.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : arguments.tripDate;
    final String timeLabel = arguments.tripTime.isEmpty
        ? (isRtl ? 'غير متوفر' : 'Not available')
        : arguments.tripTime;
    final String driverLabel = arguments.driverName.isEmpty
        ? (isRtl ? 'غير متاح' : 'Not available')
        : arguments.driverName;
    final String priceLabel = arguments.price.isEmpty
        ? (isRtl ? 'غير متاح' : 'Not available')
        : arguments.price;
    final String seatsLabel =
        '${isRtl ? 'المقاعد المتاحة' : 'Available seats'}: ${arguments.availableSeats}';

    final String? vehicleDescription = _buildVehicleDescription(
      arguments.carModel,
      arguments.carColor,
      isRtl,
    );

    final String createdAtLabel = _formatDateTime(arguments.createdAt, isRtl);

    return Directionality(
      textDirection: textDirection,
      child: Card(
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        color: colorScheme.surface.withOpacity(0.96),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                textDirection: textDirection,
                children: <Widget>[
                  Icon(Icons.directions_car, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isRtl
                          ? 'من $fromCityLabel إلى $toCityLabel'
                          : 'From $fromCityLabel to $toCityLabel',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _RideInfoRow(
                icon: Icons.event,
                textDirection: textDirection,
                label: '${isRtl ? 'التاريخ' : 'Date'}: $dateLabel',
              ),
              const SizedBox(height: 8),
              _RideInfoRow(
                icon: Icons.access_time,
                textDirection: textDirection,
                label: '${isRtl ? 'الوقت' : 'Time'}: $timeLabel',
              ),
              const SizedBox(height: 8),
              _RideInfoRow(
                icon: Icons.person,
                textDirection: textDirection,
                label: '${isRtl ? 'السائق' : 'Driver'}: $driverLabel',
              ),
              const SizedBox(height: 8),
              _RideInfoRow(
                icon: Icons.chair_alt,
                textDirection: textDirection,
                label: seatsLabel,
              ),
              const SizedBox(height: 8),
              _RideInfoRow(
                icon: Icons.attach_money,
                textDirection: textDirection,
                label: '${isRtl ? 'السعر' : 'Price'}: $priceLabel',
              ),
              if (vehicleDescription != null) ...<Widget>[
                const SizedBox(height: 8),
                _RideInfoRow(
                  icon: Icons.directions_car_filled,
                  textDirection: textDirection,
                  label: vehicleDescription,
                ),
              ],
              if (createdAtLabel.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _RideInfoRow(
                  icon: Icons.history,
                  textDirection: textDirection,
                  label: createdAtLabel,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _buildVehicleDescription(
    String? model,
    String? color,
    bool isRtl,
  ) {
    final String? sanitizedModel = _sanitizeText(model);
    final String? sanitizedColor = _sanitizeText(color);
    if (sanitizedModel == null && sanitizedColor == null) {
      return null;
    }

    if (sanitizedModel != null && sanitizedColor != null) {
      return isRtl
          ? 'المركبة: $sanitizedModel - اللون: $sanitizedColor'
          : 'Vehicle: $sanitizedModel - Color: $sanitizedColor';
    }

    if (sanitizedModel != null) {
      return isRtl ? 'المركبة: $sanitizedModel' : 'Vehicle: $sanitizedModel';
    }

    return isRtl ? 'اللون: $sanitizedColor' : 'Color: $sanitizedColor';
  }

  String? _sanitizeText(String? value) {
    if (value == null) {
      return null;
    }
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _formatDateTime(DateTime? value, bool isRtl) {
    if (value == null) {
      return '';
    }
    final String formatted =
        '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return isRtl
        ? 'آخر تحديث: $formatted'
        : 'Last updated: $formatted';
  }
}

class _RideInfoRow extends StatelessWidget {
  const _RideInfoRow({
    required this.icon,
    required this.label,
    required this.textDirection,
  });

  final IconData icon;
  final String label;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final bool isRtl = textDirection == TextDirection.rtl;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Directionality(
      textDirection: textDirection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: colorScheme.primary.withOpacity(0.8)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: isRtl ? TextAlign.right : TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final TextDirection textDirection = Directionality.of(context);
    final bool isRtl = textDirection == TextDirection.rtl;
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          style: theme.textTheme.bodyLarge,
          textAlign: isRtl ? TextAlign.right : TextAlign.center,
        ),
      ),
    );
  }
}
