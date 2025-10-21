import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class MyTripsScreen extends StatelessWidget {
  const MyTripsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  Future<void> _onRefresh(String userId) async {
    await FirebaseFirestore.instance
        .collection('trips')
        .where('driverId', isEqualTo: userId)
        .get();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buildStream(String userId) {
    return FirebaseFirestore.instance
        .collection('trips')
        .where('driverId', isEqualTo: userId)
        .snapshots();
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
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Text(
                        'الرجاء تسجيل الدخول لعرض رحلاتك.',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
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
              )
            : RefreshIndicator(
                onRefresh: () => _onRefresh(user.uid),
                color: Theme.of(context).colorScheme.primary,
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _buildStream(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Center(
                              child: Text(
                                'حدث خطأ غير متوقع. حاول مرة أخرى لاحقًا.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
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

                    if (snapshot.connectionState == ConnectionState.waiting) {
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

                    final docs = snapshot.data?.docs ?? [];

                    if (docs.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Center(
                              child: Text(
                                'لم تقم بإنشاء أي رحلات بعد',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
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
                      itemCount: docs.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final fromCity =
                            (data['fromCity'] ?? data['from'] ?? '').toString().trim();
                        final toCity =
                            (data['toCity'] ?? data['to'] ?? '').toString().trim();
                        final dateText = _formatDate(data['date']);
                        final timeText = _formatTime(data['time']);
                        final priceText = _formatPrice(data['price']);

                        return MyTripCard(
                          fromCity: fromCity.isEmpty ? 'غير متوفر' : fromCity,
                          toCity: toCity.isEmpty ? 'غير متوفر' : toCity,
                          date: dateText.isEmpty ? 'غير متوفر' : dateText,
                          time: timeText.isEmpty ? 'غير متوفر' : timeText,
                          price: priceText,
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );

    if (!showAppBar) {
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

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${_twoDigits(dateTime.day)}.${_twoDigits(dateTime.month)}.${dateTime.year}';
    }

    if (date is DateTime) {
      return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
    }

    if (date is String) {
      final trimmed = date.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return '';
  }

  String _formatTime(dynamic time) {
    if (time is Timestamp) {
      final dateTime = time.toDate();
      return '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}';
    }

    if (time is DateTime) {
      return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
    }

    if (time is String) {
      final trimmed = time.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
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
  });

  final String fromCity;
  final String toCity;
  final String date;
  final String time;
  final String price;

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
                  Icon(
                    Icons.event,
                    color: colorScheme.primary.withOpacity(0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      date,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: colorScheme.primary.withOpacity(0.9),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      time,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.8),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    price.isEmpty ? '—' : price,
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
    );
  }
}
