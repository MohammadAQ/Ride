import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:carpal_app/models/user_profile.dart';
import 'package:carpal_app/widgets/user_profile_preview.dart';

import '../services/api_service.dart';

const MethodChannel _phoneLauncherChannel =
    MethodChannel('com.example.carpal_app/phone_launcher');

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
  final List<Map<String, dynamic>> _trips = <Map<String, dynamic>>[];
  String? _selectedFromCity;
  String? _selectedToCity;
  String? _appliedFromCity;
  String? _appliedToCity;
  String? _nextCursor;
  bool _isLoading = false;
  bool _initialLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_fetchTrips(reset: true));
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

  void _showTripDetails(
    BuildContext context,
    Map<String, dynamic> data,
  ) {
    final fromCity = (data['fromCity'] ?? data['from'] ?? '').toString();
    final toCity = (data['toCity'] ?? data['to'] ?? '').toString();
    final trimmedFromCity = fromCity.trim();
    final trimmedToCity = toCity.trim();
    final displayFromCity =
        trimmedFromCity.isEmpty ? 'غير متوفر' : trimmedFromCity;
    final displayToCity = trimmedToCity.isEmpty ? 'غير متوفر' : trimmedToCity;
    final routeText = 'من: $displayFromCity → إلى: $displayToCity';
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
          bool isLink = false,
          VoidCallback? onTap,
        }) {
          final displayValue = value.trim().isEmpty ? 'غير متوفر' : value.trim();
          final rowContent = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: labelStyle),
                    const SizedBox(height: 4),
                    Text(
                      displayValue,
                      style: isLink
                          ? valueStyle?.copyWith(color: colorScheme.secondary)
                          : valueStyle,
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

        return Directionality(
          textDirection: TextDirection.rtl,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
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
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Icon(
                    Icons.schedule,
                    color: colorScheme.primary,
                  ),
                  label: 'الوقت',
                  value: timeText,
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '💰',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'السعر',
                  value: priceText,
                ),
                const SizedBox(height: 16),
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '👤',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('السائق', style: labelStyle),
                              const SizedBox(height: 8),
                              UserProfilePreview(
                                userId: driverId,
                                fallbackName: driverName,
                                avatarRadius: 26,
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
                ),
                const SizedBox(height: 16),
                buildDetailRow(
                  leading: Text(
                    '🎨',
                    style: theme.textTheme.titleLarge,
                  ),
                  label: 'لون السيارة',
                  value: carColor,
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
                  ),
                ],
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'البحث عن الرحلات',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedFromCity,
                      decoration: const InputDecoration(
                        labelText: 'من',
                        border: OutlineInputBorder(),
                      ),
                      items: westBankCities
                          .map(
                            (city) => DropdownMenuItem<String>(
                              value: city,
                              child: Text(city),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedFromCity = value;
                        });
                      },
                      isExpanded: true,
                      hint: const Text('اختر مدينة الانطلاق'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedToCity,
                      decoration: const InputDecoration(
                        labelText: 'إلى',
                        border: OutlineInputBorder(),
                      ),
                      items: westBankCities
                          .map(
                            (city) => DropdownMenuItem<String>(
                              value: city,
                              child: Text(city),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedToCity = value;
                        });
                      },
                      isExpanded: true,
                      hint: const Text('اختر مدينة الوصول'),
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

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Trips'),
        centerTitle: false,
      ),
      body: body,
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
      for (final data in _trips) {
        final fromCity = (data['fromCity'] ?? '').toString().trim();
        final toCity = (data['toCity'] ?? '').toString().trim();
        final dateText = _formatDate(data['date']);
        final priceText = _formatPrice(data['price']);
        final String driverId = _resolveDriverId(data) ?? '';
        final String driverName = _resolveDriverName(data);

        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TripCard(
              fromCity: fromCity.isEmpty ? 'غير متوفر' : fromCity,
              toCity: toCity.isEmpty ? 'غير متوفر' : toCity,
              date: dateText.isEmpty ? 'غير متوفر' : dateText,
              price: priceText,
              driverId: driverId,
              driverName: driverName,
              notes: (data['notes'] ?? '').toString().trim().isEmpty
                  ? null
                  : (data['notes'] ?? '').toString(),
              onTap: () => _showTripDetails(context, data),
            ),
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
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
    this.notes,
    this.onTap,
  });

  final String fromCity;
  final String toCity;
  final String date;
  final String price;
  final String driverId;
  final String driverName;
  final String? notes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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

    return Card(
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
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (driverId.trim().isNotEmpty || driverName.trim().isNotEmpty) ...[
                Directionality(
                  textDirection: TextDirection.rtl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'السائق',
                        style: driverLabelStyle,
                      ),
                      const SizedBox(height: 6),
                      UserProfilePreview(
                        userId: driverId,
                        fallbackName: driverName,
                        avatarRadius: 22,
                        textStyle: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize:
                                  (textTheme.titleMedium?.fontSize ?? 16) + 2,
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
              ],
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'من $fromCity  →  إلى $toCity',
                        style: routeTextStyle,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Divider(
                height: 1,
                color: dividerColor,
              ),
              const SizedBox(height: 16),
              Directionality(
                textDirection: TextDirection.rtl,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_money,
                        color: colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
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
                      ),
                      const SizedBox(width: 18),
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
                      ),
                    ],
                  ),
                ),
              ),
              if (notes != null && notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  notes!,
                  style: notesStyle,
                  textAlign: TextAlign.right,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
