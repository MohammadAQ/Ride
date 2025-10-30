import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/ride_request.dart';
import '../services/ride_request_service.dart';

class MyRideRequestsScreen extends StatelessWidget {
  const MyRideRequestsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final List<Color> gradientColors = <Color>[
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
              return _buildMessage(context, 'يرجى تسجيل الدخول لعرض طلباتك.');
            }

            final RideRequestService service = RideRequestService();

            return StreamBuilder<List<RideRequest>>(
              stream: service.watchPassengerRequests(user.uid),
              builder: (
                BuildContext context,
                AsyncSnapshot<List<RideRequest>> requestsSnapshot,
              ) {
                if (requestsSnapshot.hasError) {
                  return _buildMessage(
                    context,
                    'حدث خطأ أثناء تحميل طلباتك. حاول مرة أخرى لاحقًا.',
                  );
                }

                if (requestsSnapshot.connectionState == ConnectionState.waiting &&
                    !requestsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<RideRequest> requests =
                    requestsSnapshot.data ?? <RideRequest>[];

                if (requests.isEmpty) {
                  return _buildMessage(context, 'لم تقم بإرسال أي طلبات بعد.');
                }

                return ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
                  itemCount: requests.length,
                  itemBuilder: (BuildContext context, int index) {
                    final RideRequest request = requests[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _PassengerRequestCard(request: request),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.translate('nav_my_requests')),
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

class _PassengerRequestCard extends StatelessWidget {
  const _PassengerRequestCard({required this.request});

  final RideRequest request;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final Color statusColor = _statusColor(request.status, colorScheme);
    final String statusText = _statusText(request.status);
    final String messageText = _statusMessage(request.status);
    final String timestampText = _formatTimestamp(request.timestamp, context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  timestampText,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTripInfo(context, request),
            const SizedBox(height: 12),
            Text(
              messageText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (request.status == 'rejected' && request.reason.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'السبب: ${request.reason}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripInfo(BuildContext context, RideRequest request) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('trips').doc(request.rideId).snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        final Map<String, dynamic>? data = snapshot.data?.data();

        if (data == null) {
          return Text(
            'لم تعد بيانات هذه الرحلة متاحة.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          );
        }

        final String fromCity = (data['fromCity'] ?? '').toString();
        final String toCity = (data['toCity'] ?? '').toString();
        final String time = (data['time'] ?? '').toString();
        final String date = (data['date'] ?? '').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$fromCity → $toCity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            Text('الوقت: $time'),
            Text('التاريخ: $date'),
          ],
        );
      },
    );
  }

  Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'accepted':
        return Colors.green.shade700;
      case 'rejected':
        return scheme.error;
      default:
        return Colors.amber.shade700;
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'accepted':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'قيد الانتظار';
    }
  }

  String _statusMessage(String status) {
    switch (status) {
      case 'accepted':
        return 'تمت الموافقة على الرحلة ✅';
      case 'rejected':
        return 'تم رفض الطلب ❌';
      default:
        return 'تم إرسال الطلب، بانتظار موافقة السائق.';
    }
  }

  String _formatTimestamp(DateTime? time, BuildContext context) {
    if (time == null) {
      return 'غير محدد';
    }
    final Locale locale = Localizations.maybeLocaleOf(context) ?? const Locale('ar');
    final DateFormat formatter = DateFormat.yMMMd(locale.toLanguageTag()).add_Hm();
    return formatter.format(time);
  }
}
