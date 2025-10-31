import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:ride/l10n/app_localizations.dart';
import 'package:ride/models/ride_request.dart';
import 'package:ride/services/booking_service.dart';
import 'package:ride/services/ride_request_service.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final gradientColors = <Color>[
      const Color(0xFFEDE7F6),
      Theme.of(context).colorScheme.primary.withOpacity(0.08),
      const Color(0xFFD1C4E9),
    ];

    final Widget body = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          initialData: FirebaseAuth.instance.currentUser,
          builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
            final User? user = snapshot.data;
            if (user == null) {
              return _buildMessage(context, 'يرجى تسجيل الدخول لعرض حجوزاتك.');
            }

            final Query<Map<String, dynamic>> query = FirebaseFirestore.instance
                .collection('bookings')
                .where('userId', isEqualTo: user.uid)
                .orderBy('bookedAt', descending: true);

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (
                BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> bookingsSnapshot,
              ) {
                if (bookingsSnapshot.hasError) {
                  return _buildMessage(
                    context,
                    'حدث خطأ أثناء تحميل الحجوزات. حاول مرة أخرى لاحقًا.',
                  );
                }

                if (bookingsSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    bookingsSnapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                if (docs.isEmpty) {
                  return _buildMessage(context, 'لا توجد حجوزات حتى الآن.');
                }

                return ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
                  itemCount: docs.length,
                  itemBuilder: (BuildContext context, int index) {
                    final QueryDocumentSnapshot<Map<String, dynamic>> bookingDoc = docs[index];
                    final Map<String, dynamic> bookingData = bookingDoc.data();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _BookingCard(
                        tripId: bookingData['tripId']?.toString() ?? '',
                        status: bookingData['status']?.toString() ?? 'confirmed',
                        bookedAt: bookingData['bookedAt'],
                        userId: bookingData['userId']?.toString() ?? user.uid,
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );

    if (!showAppBar) {
      return body;
    }

    final String title = context.translate('nav_my_bookings');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }

  Widget _buildMessage(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatefulWidget {
  const _BookingCard({
    required this.tripId,
    required this.status,
    required this.userId,
    this.bookedAt,
  });

  final String tripId;
  final String status;
  final String userId;
  final dynamic bookedAt;

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  final BookingService _bookingService = BookingService();
  final RideRequestService _rideRequestService = RideRequestService();
  bool _isCancelling = false;

  @override
  void didUpdateWidget(covariant _BookingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status && _isCancelling) {
      _isCancelling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tripId.isEmpty) {
      return _buildPlaceholderCard(
        context,
        'تعذر تحميل بيانات الرحلة لهذه الحجز.',
      );
    }

    final DocumentReference<Map<String, dynamic>> tripRef =
        FirebaseFirestore.instance.collection('trips').doc(widget.tripId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tripRef.snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        if (snapshot.hasError) {
          return _buildPlaceholderCard(
            context,
            'حدث خطأ أثناء تحميل بيانات الرحلة.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return _buildLoadingCard(context);
        }

        final Map<String, dynamic>? data = snapshot.data?.data();
        if (data == null) {
          return _buildPlaceholderCard(
            context,
            'لم تعد هذه الرحلة متاحة.',
          );
        }

        final String fromCity = (data['fromCity'] ?? '').toString().trim();
        final String toCity = (data['toCity'] ?? '').toString().trim();
        final String driverName = (data['driverName'] ?? '').toString().trim();
        final String tripDate = (data['date'] ?? '').toString().trim();
        final String tripTime = (data['time'] ?? '').toString().trim();
        final int availableSeats = _parseInt(data['availableSeats']);
        final List<dynamic> bookedUsers = data['bookedUsers'] is List
            ? List<dynamic>.from(data['bookedUsers'] as List)
            : const <dynamic>[];
        final int bookedCount = bookedUsers.length;

        final TextDirection direction = Directionality.of(context);
        final bool isRtl = direction == TextDirection.rtl;
        final ThemeData theme = Theme.of(context);
        final ColorScheme colorScheme = theme.colorScheme;

        final String routeText = isRtl
            ? 'من $fromCity → إلى $toCity'
            : 'From $fromCity → To $toCity';
        final String seatSummary = isRtl
            ? 'عدد المقاعد المتاحة: $availableSeats'
            : 'Available seats: $availableSeats';
        final DateTime? bookedAtDate = _parseTimestamp(widget.bookedAt);
        final String bookingDateText = bookedAtDate != null
            ? '${bookedAtDate.year.toString().padLeft(4, '0')}-${bookedAtDate.month.toString().padLeft(2, '0')}-${bookedAtDate.day.toString().padLeft(2, '0')} ${bookedAtDate.hour.toString().padLeft(2, '0')}:${bookedAtDate.minute.toString().padLeft(2, '0')}'
            : 'غير متاح';

        final String statusLower = widget.status.toLowerCase();
        final bool isConfirmed = statusLower == 'confirmed';
        final bool isCanceled = statusLower == 'canceled';
        final String statusLabel;
        final Color statusColor;
        if (isConfirmed) {
          statusLabel = isRtl ? 'مؤكد' : 'Confirmed';
          statusColor = Colors.green.shade700;
        } else if (isCanceled) {
          statusLabel = isRtl ? 'ملغى' : 'Canceled';
          statusColor = Colors.red.shade600;
        } else {
          statusLabel = widget.status;
          statusColor = colorScheme.primary;
        }

        final Stream<RideRequest?> requestStream =
            _rideRequestService.requestForPassengerStream(
          rideId: widget.tripId,
          passengerId: widget.userId,
        );

        return StreamBuilder<RideRequest?>(
          stream: requestStream,
          builder: (
            BuildContext context,
            AsyncSnapshot<RideRequest?> requestSnapshot,
          ) {
            final RideRequest? request = requestSnapshot.data;
            final Widget? statusChip = _buildRequestStatusChip(
              context: context,
              request: request,
              isRtl: isRtl,
            );

            return Directionality(
              textDirection: direction,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                color: colorScheme.surface.withOpacity(0.96),
                child: Padding(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
                  child: Column(
                    crossAxisAlignment:
                        isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (statusChip != null) ...<Widget>[
                        statusChip,
                        const SizedBox(height: 12),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.directions_car,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              routeText,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface,
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment:
                            isRtl ? MainAxisAlignment.end : MainAxisAlignment.start,
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.event,
                            color: colorScheme.onSurface.withOpacity(0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$tripDate • $tripTime',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.person,
                            color: colorScheme.onSurface.withOpacity(0.7),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              driverName.isEmpty ? 'السائق غير معروف' : driverName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.85),
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.event_seat,
                            color: colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              seatSummary,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.check_circle_outline,
                            color: statusColor,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (isRtl ? 'الحالة: ' : 'Status: ') + statusLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        textDirection: direction,
                        children: <Widget>[
                          Icon(
                            Icons.schedule,
                            color: colorScheme.onSurface.withOpacity(0.6),
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              (isRtl ? 'تاريخ الحجز: ' : 'Booked at: ') +
                                  bookingDateText,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                              ),
                              textAlign: isRtl ? TextAlign.right : TextAlign.left,
                            ),
                          ),
                        ],
                      ),
                      if (bookedCount > 0) ...<Widget>[
                        const SizedBox(height: 12),
                        Align(
                          alignment:
                              isRtl ? Alignment.centerRight : Alignment.centerLeft,
                          child: Text(
                            isRtl
                                ? 'عدد الركاب المؤكدين: $bookedCount'
                                : 'Confirmed passengers: $bookedCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                      if (isConfirmed)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Align(
                            alignment:
                                isRtl ? Alignment.centerRight : Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _isCancelling ? null : _cancelBooking,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              icon: _isCancelling
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.cancel_outlined),
                              label: Text(
                                isRtl ? 'إلغاء الحجز' : 'Cancel Booking',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget? _buildRequestStatusChip({
    required BuildContext context,
    required RideRequest? request,
    required bool isRtl,
  }) {
    if (request == null) {
      return null;
    }

    final ThemeData theme = Theme.of(context);

    late final String text;
    late final Color color;

    switch (request.status) {
      case RideRequestStatus.pending:
        text = 'بانتظار موافقة السائق…';
        color = Colors.amber.shade700;
        break;
      case RideRequestStatus.accepted:
        text = 'تمت الموافقة ✅';
        color = Colors.green.shade600;
        break;
      case RideRequestStatus.rejected:
        final String sanitizedReason = request.reason.trim().isEmpty
            ? 'غير مذكور'
            : request.reason.trim();
        text = 'تم رفض الطلب ❌ – السبب: $sanitizedReason';
        color = Colors.red.shade600;
        break;
    }

    return Align(
      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          textAlign: isRtl ? TextAlign.right : TextAlign.left,
        ),
      ),
    );
  }

  Future<void> _cancelBooking() async {
    if (widget.tripId.isEmpty || widget.userId.isEmpty) {
      return;
    }
    if (_isCancelling) {
      return;
    }

    setState(() {
      _isCancelling = true;
    });

    try {
      await _bookingService.cancelBooking(
        tripId: widget.tripId,
        userId: widget.userId,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking canceled successfully'),
        ),
      );
    } on BookingException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إلغاء الحجز. حاول مرة أخرى لاحقًا.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCancelling = false;
      });
    }
  }

  Card _buildPlaceholderCard(BuildContext context, String message) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      color: colorScheme.surface.withOpacity(0.96),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.info_outline,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Card _buildLoadingCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      color: colorScheme.surface.withOpacity(0.96),
      child: const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final int? parsed = int.tryParse(value.toString());
    return parsed ?? 0;
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
