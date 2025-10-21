import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

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
        final fromCity = (data['fromCity'] ?? '').toString().trim();
        final toCity = (data['toCity'] ?? '').toString().trim();
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
    );
  }
}
