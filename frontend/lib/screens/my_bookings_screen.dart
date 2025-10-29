import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:carpal_app/l10n/app_localizations.dart';

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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _BookingCard(
                        tripId: bookingDoc.data()['tripId']?.toString() ?? '',
                        status: bookingDoc.data()['status']?.toString() ?? 'confirmed',
                        bookedAt: bookingDoc.data()['bookedAt'],
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

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.tripId,
    required this.status,
    this.bookedAt,
  });

  final String tripId;
  final String status;
  final dynamic bookedAt;

  @override
  Widget build(BuildContext context) {
    if (tripId.isEmpty) {
      return _buildPlaceholderCard(
        context,
        'تعذر تحميل بيانات الرحلة لهذه الحجز.',
      );
    }

    final DocumentReference<Map<String, dynamic>> tripRef =
        FirebaseFirestore.instance.collection('trips').doc(tripId);

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
        final int totalSeats = _parseInt(data['totalSeats']);
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
        final String seatSummary = totalSeats > 0
            ? 'المقاعد المتاحة: $availableSeats / $totalSeats'
            : 'المقاعد المتاحة: غير محدد';
        final DateTime? bookedAtDate = _parseTimestamp(bookedAt);
        final String bookingDateText = bookedAtDate != null
            ? '${bookedAtDate.year.toString().padLeft(4, '0')}-${bookedAtDate.month.toString().padLeft(2, '0')}-${bookedAtDate.day.toString().padLeft(2, '0')} ${bookedAtDate.hour.toString().padLeft(2, '0')}:${bookedAtDate.minute.toString().padLeft(2, '0')}'
            : 'غير متاح';

        return Directionality(
          textDirection: direction,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            color: colorScheme.surface.withOpacity(0.96),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment:
                    isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
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
                        color: Colors.green.shade600,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'الحالة: ${status == 'confirmed' ? 'مؤكد' : status}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.green.shade700,
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
                          'تاريخ الحجز: $bookingDateText',
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
                      alignment: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        'عدد الركاب المؤكدين: $bookedCount',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
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
