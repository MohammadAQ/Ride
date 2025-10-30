import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/ride_request.dart';
import '../services/ride_request_service.dart';

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key, this.showAppBar = true});

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
              return _buildMessage(context, 'يرجى تسجيل الدخول لعرض طلبات الركاب.');
            }

            final RideRequestService service = RideRequestService();

            return StreamBuilder<List<RideRequest>>(
              stream: service.watchDriverPendingRequests(user.uid),
              builder: (
                BuildContext context,
                AsyncSnapshot<List<RideRequest>> requestsSnapshot,
              ) {
                if (requestsSnapshot.hasError) {
                  return _buildMessage(
                    context,
                    'حدث خطأ أثناء تحميل الطلبات. حاول مرة أخرى لاحقًا.',
                  );
                }

                if (requestsSnapshot.connectionState == ConnectionState.waiting &&
                    !requestsSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<RideRequest> requests =
                    requestsSnapshot.data ?? <RideRequest>[];

                if (requests.isEmpty) {
                  return _buildMessage(context, 'لا توجد طلبات ركاب حالياً.');
                }

                return ListView.builder(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 16),
                  itemCount: requests.length,
                  itemBuilder: (BuildContext context, int index) {
                    final RideRequest request = requests[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _DriverRequestCard(
                        request: request,
                        service: service,
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

    return Scaffold(
      appBar: AppBar(
        title: Text(context.translate('nav_driver_requests')),
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

class _DriverRequestCard extends StatefulWidget {
  const _DriverRequestCard({required this.request, required this.service});

  final RideRequest request;
  final RideRequestService service;

  @override
  State<_DriverRequestCard> createState() => _DriverRequestCardState();
}

class _DriverRequestCardState extends State<_DriverRequestCard> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final RideRequest request = widget.request;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(context, request),
            const SizedBox(height: 12),
            _buildTripInfo(context, request),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isProcessing ? null : () => _acceptRequest(context),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('موافقة'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : () => _showRejectDialog(context),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('رفض'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, RideRequest request) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(request.passengerId).snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        final Map<String, dynamic>? data = snapshot.data?.data();
        final String passengerName = _resolveDisplayName(data);
        final String subtitle = _formatTimestamp(request.timestamp, context);

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              passengerName.isNotEmpty ? passengerName[0].toUpperCase() : 'م',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          title: Text(passengerName.isEmpty ? 'راكب' : passengerName),
          subtitle: Text(subtitle),
        );
      },
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

        final String fromCity = (data?['fromCity'] ?? '').toString();
        final String toCity = (data?['toCity'] ?? '').toString();
        final String time = (data?['time'] ?? '').toString();
        final String date = (data?['date'] ?? '').toString();

        if (data == null) {
          return Text(
            'لم تعد بيانات هذه الرحلة متاحة.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          );
        }

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

  Future<void> _acceptRequest(BuildContext context) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.service.acceptRequest(widget.request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الموافقة على الطلب.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث حالة الطلب. حاول لاحقاً.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showRejectDialog(BuildContext context) {
    final TextEditingController controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('سبب الرفض'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'اكتب سبب الرفض (اختياري)',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: _isProcessing
                  ? null
                  : () {
                      Navigator.of(context).pop();
                      _rejectRequest(context, controller.text.trim());
                    },
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _rejectRequest(BuildContext context, String reason) async {
    setState(() {
      _isProcessing = true;
    });

    try {
      await widget.service.rejectRequest(widget.request.id, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض الطلب.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تحديث حالة الطلب. حاول لاحقاً.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  String _resolveDisplayName(Map<String, dynamic>? data) {
    if (data == null) {
      return '';
    }
    final List<dynamic> candidates = <dynamic>[
      data['displayName'],
      data['fullName'],
      data['name'],
    ];

    for (final dynamic candidate in candidates) {
      final String? sanitized = candidate?.toString().trim();
      if (sanitized != null && sanitized.isNotEmpty) {
        return sanitized;
      }
    }

    return '';
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
