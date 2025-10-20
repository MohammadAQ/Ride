import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  String? _selectedFromCity;
  String? _selectedToCity;
  String? _appliedFromCity;
  String? _appliedToCity;

  Future<void> _onRefresh() async {
    await _buildQuery().get();
  }

  Query<Map<String, dynamic>> _buildQuery() {
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('trips');

    final fromCity = _appliedFromCity;
    final trimmedFrom = fromCity?.trim();
    if (trimmedFrom != null && trimmedFrom.isNotEmpty) {
      query = query.where('from', isEqualTo: trimmedFrom);
    }

    final toCity = _appliedToCity;
    final trimmedTo = toCity?.trim();
    if (trimmedTo != null && trimmedTo.isNotEmpty) {
      query = query.where('to', isEqualTo: trimmedTo);
    }

    print(
      'Firestore query filters -> from: '
      '${trimmedFrom != null && trimmedFrom.isNotEmpty ? '"$trimmedFrom"' : '(any)'}'
      ', to: '
      '${trimmedTo != null && trimmedTo.isNotEmpty ? '"$trimmedTo"' : '(any)'}',
    );

    return query;
  }

  void _onSearchPressed() {
    final fromCity = (_selectedFromCity ?? '').trim();
    final toCity = (_selectedToCity ?? '').trim();

    print('Searching trips with fromCity: "$fromCity", toCity: "$toCity"');

    setState(() {
      _appliedFromCity = fromCity.isEmpty ? null : fromCity;
      _appliedToCity = toCity.isEmpty ? null : toCity;
    });
  }

  void _loadAllTrips() {
    setState(() {
      _appliedFromCity = null;
      _appliedToCity = null;
    });
  }

  void _resetFilters() {
    setState(() {
      _selectedFromCity = null;
      _selectedToCity = null;
    });

    _loadAllTrips();
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
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _buildQuery().snapshots(),
            builder: (context, snapshot) {
              final children = <Widget>[
                _buildFilters(context),
              ];

              if (snapshot.hasError) {
                children.add(
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Text(
                        'Something went wrong. Please try again later.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  children: children,
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                children.add(
                  const SizedBox(
                    height: 280,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  children: children,
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                children.add(
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.4,
                    child: Center(
                      child: Text(
                        'لا توجد رحلات متاحة',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onBackground
                                  .withOpacity(0.7),
                            ),
                      ),
                    ),
                  ),
                );

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  children: children,
                );
              }

              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                itemCount: docs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildFilters(context);
                  }

                  final data = docs[index - 1].data();
                  final fromCity = (data['from'] ?? '').toString();
                  final toCity = (data['to'] ?? '').toString();
                  final notesValue = data['notes'];
                  final notes = notesValue == null ? null : notesValue.toString();

                  final dateValue = data['date'];
                  final dateText = _formatDate(dateValue);

                  final priceValue = data['price'];
                  final priceText = _formatPrice(priceValue);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TripCard(
                      fromCity: fromCity,
                      toCity: toCity,
                      date: dateText,
                      price: priceText,
                      notes: notes,
                    ),
                  );
                },
              );
            },
          ),
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

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      final dateTime = date.toDate();
      return '${_twoDigits(dateTime.day)}.${_twoDigits(dateTime.month)}.${dateTime.year}';
    }

    if (date is DateTime) {
      return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
    }

    return date?.toString() ?? '';
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
    this.notes,
  });

  final String fromCity;
  final String toCity;
  final String date;
  final String price;
  final String? notes;

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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    fromCity,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    toCity,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    date,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
                Text(
                  price,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (notes != null && notes!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                notes!,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
