import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/phone_launcher.dart';

class TripDashboardArguments {
  TripDashboardArguments({
    required this.tripId,
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
  });

  final String tripId;
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
}

class TripDashboardScreen extends StatelessWidget {
  const TripDashboardScreen({super.key, required this.arguments});

  final TripDashboardArguments arguments;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(isRtl ? 'لوحة الرحلة' : 'Trip Dashboard'),
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
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 12),
                child: _TripSummaryCard(
                  arguments: arguments,
                  textDirection: textDirection,
                ),
              ),
              // TODO: Enable this button when bulk notifications are implemented.
              // Padding(
              //   padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
              //   child: SizedBox(
              //     width: double.infinity,
              //     child: ElevatedButton.icon(
              //       onPressed: null,
              //       icon: const Icon(Icons.notifications_active),
              //       label: Text(
              //         isRtl
              //             ? 'إرسال إشعار لجميع الركاب'
              //             : 'Send Notification to All Passengers',
              //       ),
              //     ),
              //   ),
              // ),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _passengerStream(arguments.tripId),
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                  ) {
                    if (snapshot.hasError) {
                      final Object? error = snapshot.error;
                      final String fallback = isRtl
                          ? 'حدث خطأ أثناء تحميل الركاب. حاول مرة أخرى لاحقًا.'
                          : 'Failed to load passengers. Please try again later.';
                      final String message =
                          error is FirebaseException && error.message != null
                              ? error.message!
                              : fallback;
                      return _CenteredMessage(message: message);
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                        snapshot.data?.docs ??
                            <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                    final List<_PassengerBooking> passengers = docs
                        .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                      final Map<String, dynamic> data = doc.data();
                      return _PassengerBooking.fromMap(data);
                    }).where((_PassengerBooking booking) {
                      return !booking.isCanceled;
                    }).toList();

                    if (passengers.isEmpty) {
                      return _CenteredMessage(
                        message: '🚫 ' +
                            (isRtl
                                ? 'لا يوجد ركّاب في هذه الرحلة بعد'
                                : 'No passengers booked yet'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 24),
                      itemCount: passengers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final _PassengerBooking booking = passengers[index];
                        return _PassengerCard(
                          booking: booking,
                          textDirection: textDirection,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _passengerStream(String tripId) async* {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;
    final DocumentReference<Map<String, dynamic>> tripRef =
        firestore.collection('trips').doc(tripId);

    try {
      final Query<Map<String, dynamic>> query = firestore
          .collection('bookings')
          .where(
            // Firestore throws when filtering with the wrong value type (String
            // vs DocumentReference). Matching both fields keeps old data
            // compatible and fixes the dashboard crash.
            Filter.or(
              Filter('tripId', isEqualTo: tripId),
              Filter('tripRef', isEqualTo: tripRef),
            ),
          )
          // Keep most recent status changes at the top of the dashboard.
          .orderBy('updatedAt', descending: true);

      yield* query.snapshots();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Failed to load passengers for trip $tripId: ${error.message}');
      // Surface a readable message to the StreamBuilder so the UI can present
      // something friendlier than the default Firebase error text.
      Error.throwWithStackTrace(
        FirebaseException(
          plugin: error.plugin,
          code: error.code,
          message:
              'حدث خطأ أثناء تحميل الركاب. حاول مرة أخرى لاحقًا. (${error.code})',
        ),
        stackTrace,
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected passengers stream error: $error');
      Error.throwWithStackTrace(
        Exception('حدث خطأ غير متوقع أثناء تحميل الركاب. ($error)'),
        stackTrace,
      );
    }
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({
    required this.arguments,
    required this.textDirection,
  });

  final TripDashboardArguments arguments;
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
        (isRtl ? 'المقاعد المتاحة: ' : 'Available seats: ') +
            arguments.availableSeats.toString();

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
          padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                textDirection: textDirection,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
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
                        children: <InlineSpan>[
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
                    children: <InlineSpan>[
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
                  seatsLabel,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
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
                ),
              ),
              if (vehicleDescription != null) ...<Widget>[
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.directions_car_filled_outlined,
                  textDirection: textDirection,
                  iconColor: colorScheme.onSurface.withOpacity(0.7),
                  child: Text(
                    (isRtl ? 'المركبة: ' : 'Vehicle: ') + vehicleDescription,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _InfoRow(
                icon: Icons.schedule,
                textDirection: textDirection,
                iconColor: colorScheme.onSurface.withOpacity(0.6),
                child: Text(
                  (isRtl ? 'تاريخ الإنشاء: ' : 'Created at: ') + createdAtLabel,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
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
    final String? sanitizedModel = model?.trim();
    final String? sanitizedColor = color?.trim();

    if ((sanitizedModel == null || sanitizedModel.isEmpty) &&
        (sanitizedColor == null || sanitizedColor.isEmpty)) {
      return null;
    }

    if (sanitizedModel != null && sanitizedModel.isNotEmpty &&
        sanitizedColor != null && sanitizedColor.isNotEmpty) {
      return isRtl
          ? '$sanitizedModel - $sanitizedColor'
          : '$sanitizedModel • $sanitizedColor';
    }

    return sanitizedModel != null && sanitizedModel.isNotEmpty
        ? sanitizedModel
        : sanitizedColor;
  }

  String _formatDateTime(DateTime? value, bool isRtl) {
    if (value == null) {
      return isRtl ? 'غير متاح' : 'Not available';
    }

    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({
    required this.booking,
    required this.textDirection,
  });

  final _PassengerBooking booking;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextTheme textTheme = theme.textTheme;
    final bool isRtl = textDirection == TextDirection.rtl;

    final String statusLabel = _localizeStatus(booking.status, isRtl);
    final Color statusColor = _statusColor(booking.status, colorScheme);
    final String bookingDate = _formatBookingDate(booking.createdAt, isRtl);

    return Directionality(
      textDirection: textDirection,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 3,
        color: colorScheme.surface,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment:
                isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                textDirection: textDirection,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _PassengerAvatar(
                    name: booking.passengerName,
                    photoUrl: booking.photoUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: isRtl
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          booking.passengerName.isEmpty
                              ? (isRtl ? 'راكب غير معروف' : 'Unknown passenger')
                              : booking.passengerName,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          (isRtl ? 'تاريخ الحجز: ' : 'Booked at: ') + bookingDate,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        isRtl ? 'الاتصال بالراكب' : 'Call passenger',
                    icon: const Icon(Icons.phone),
                    color: colorScheme.primary,
                    onPressed: booking.phoneNumber.isEmpty
                        ? null
                        : () => _callPassenger(context, booking.phoneNumber, isRtl),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    statusLabel,
                    style: textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _callPassenger(
    BuildContext context,
    String phoneNumber,
    bool isRtl,
  ) async {
    final bool success = await PhoneLauncher.launchDialer(phoneNumber);
    if (!success && context.mounted) {
      final String message = isRtl
          ? 'تعذر فتح تطبيق الاتصال لهذا الرقم.'
          : 'Unable to open the dialer for this number.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _formatBookingDate(DateTime? dateTime, bool isRtl) {
    if (dateTime == null) {
      return isRtl ? 'غير متاح' : 'Not available';
    }

    final String year = dateTime.year.toString().padLeft(4, '0');
    final String month = dateTime.month.toString().padLeft(2, '0');
    final String day = dateTime.day.toString().padLeft(2, '0');
    final String hour = dateTime.hour.toString().padLeft(2, '0');
    final String minute = dateTime.minute.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute';
  }

  String _localizeStatus(String status, bool isRtl) {
    final String normalized = status.toLowerCase();
    switch (normalized) {
      case 'confirmed':
        return isRtl ? 'مؤكد' : 'Confirmed';
      case 'active':
        return isRtl ? 'نشط' : 'Active';
      case 'pending':
        return isRtl ? 'قيد الانتظار' : 'Pending';
      case 'canceled':
        return isRtl ? 'ملغي' : 'Canceled';
      default:
        return status.isEmpty
            ? (isRtl ? 'غير متاح' : 'Not available')
            : status;
    }
  }

  Color _statusColor(String status, ColorScheme colorScheme) {
    final String normalized = status.toLowerCase();
    switch (normalized) {
      case 'confirmed':
      case 'active':
        return colorScheme.primary;
      case 'pending':
        return colorScheme.tertiary;
      case 'canceled':
        return colorScheme.error;
      default:
        return colorScheme.onSurface;
    }
  }
}

class _PassengerAvatar extends StatelessWidget {
  const _PassengerAvatar({
    required this.name,
    this.photoUrl,
  });

  final String name;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final String initials = _extractInitials(name);

    return CircleAvatar(
      radius: 24,
      backgroundImage:
          photoUrl != null && photoUrl!.isNotEmpty ? NetworkImage(photoUrl!) : null,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: (photoUrl == null || photoUrl!.isEmpty)
          ? Text(
              initials,
              style: const TextStyle(fontWeight: FontWeight.w600),
            )
          : null,
    );
  }

  String _extractInitials(String value) {
    final String sanitized = value.trim();
    if (sanitized.isEmpty) {
      return '?';
    }

    final List<String> parts = sanitized.split(RegExp(r'\s+'));
    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      final String word = parts.first;
      final int length = word.length >= 2 ? 2 : word.length;
      return word.substring(0, length).toUpperCase();
    }

    final String first = parts.first;
    final String last = parts.last;
    final String firstInitial = first.isNotEmpty ? first[0] : '';
    final String lastInitial = last.isNotEmpty ? last[0] : '';
    final String combined = (firstInitial + lastInitial).trim();

    return combined.isEmpty ? '?' : combined.toUpperCase();
  }
}

class _PassengerBooking {
  _PassengerBooking({
    required this.passengerName,
    required this.phoneNumber,
    required this.status,
    required this.createdAt,
    required this.photoUrl,
  });

  final String passengerName;
  final String phoneNumber;
  final String status;
  final DateTime? createdAt;
  final String? photoUrl;

  bool get isCanceled => status.toLowerCase() == 'canceled';

  static _PassengerBooking fromMap(Map<String, dynamic> data) {
    return _PassengerBooking(
      passengerName: _stringOrEmpty(data['passengerName']) ??
          _stringOrEmpty(data['name']) ??
          '',
      phoneNumber: _stringOrEmpty(data['phoneNumber']) ?? '',
      status: _stringOrEmpty(data['status']) ?? '',
      createdAt: _parseDateTime(
        data['createdAt'] ?? data['bookedAt'] ?? data['updatedAt'],
      ),
      photoUrl: _stringOrEmpty(
            data['passengerPhotoUrl'] ??
                data['photoUrl'] ??
                data['avatarUrl'] ??
                data['avatar'],
          ) ??
          null,
    );
  }

  static String? _stringOrEmpty(dynamic value) {
    if (value == null) {
      return null;
    }
    final String stringValue = value.toString().trim();
    if (stringValue.isEmpty) {
      return null;
    }
    return stringValue;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int || value is double) {
      final num numericValue = value as num;
      if (numericValue > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(numericValue.toInt());
      }
      if (numericValue > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch((numericValue * 1000).toInt());
      }
      return DateTime.fromMillisecondsSinceEpoch(numericValue.toInt());
    }
    if (value is String) {
      final String trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final DateTime? parsed = DateTime.tryParse(trimmed);
      if (parsed != null) {
        return parsed;
      }
      final num? numeric = num.tryParse(trimmed);
      if (numeric != null) {
        return _parseDateTime(numeric);
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
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
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
      children: <Widget>[
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
