import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  static const List<String> _cities = <String>[
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

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  String? _fromCity;
  String? _toCity;
  DateTime? _selectedDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _dateController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();

    final DateTime now = DateTime.now();
    final DateTime firstDate = DateTime(now.year, now.month, now.day);

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? firstDate,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2),
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _dateController.text = _formatDate(pickedDate);
      });
    }
  }

  String _formatDate(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _submit() async {
    final currentState = _formKey.currentState;
    if (currentState == null || _isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (!currentState.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be logged in to create a trip.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final DateTime? date = _selectedDate;
    if (date == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a valid date.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final String? fromCity = _fromCity;
    final String? toCity = _toCity;
    final double? price = double.tryParse(_priceController.text.trim());
    if (price == null) {
      // Should not happen because validator already checks this, but guard anyway.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid numeric price.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == null || toCity == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both departure and destination cities.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == toCity) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Departure and destination must be different.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final String notes = _notesController.text.trim();

      await FirebaseFirestore.instance.collection('trips').add({
        'from': fromCity,
        'to': toCity,
        'date': Timestamp.fromDate(date),
        'price': price,
        if (notes.isNotEmpty) 'notes': notes,
        'driverId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip created successfully!'),
        ),
      );

      currentState.reset();
      setState(() {
        _fromCity = null;
        _toCity = null;
        _selectedDate = null;
      });
      _dateController.clear();
      _priceController.clear();
      _notesController.clear();

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!context.mounted) return;

      if (widget.showAppBar) {
        Navigator.of(context).pop();
      }
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create trip: ${error.message ?? 'Unknown error'}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (!context.mounted) return;
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final form = SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 2,
              shadowColor: colorScheme.shadow.withOpacity(0.2),
              surfaceTintColor: colorScheme.surfaceTint,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Create a New Trip',
                        textAlign: TextAlign.start,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Fill in the details below to share your trip with riders.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        value: _fromCity,
                        items: _cities
                            .map(
                              (city) => DropdownMenuItem<String>(
                                value: city,
                                child: Text(city),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'From (Departure City)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _fromCity = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a departure city.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _toCity,
                        items: _cities
                            .map(
                              (city) => DropdownMenuItem<String>(
                                value: city,
                                child: Text(city),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(
                          labelText: 'To (Destination City)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _toCity = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please select a destination city.';
                          }
                          if (value == _fromCity) {
                            return 'Departure and destination must be different.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _dateController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          hintText: 'Select trip date',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        onTap: _pickDate,
                        validator: (value) {
                          if (_selectedDate == null) {
                            return 'Please choose a valid date.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          hintText: 'Enter trip price',
                          prefixIcon: Icon(Icons.attach_money),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a price.';
                          }
                          final price = double.tryParse(value.trim());
                          if (price == null || price <= 0) {
                            return 'Enter a valid positive number.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notes (Optional)',
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle_outline),
                        label: Text(_isSubmitting ? 'Creating Trip...' : 'Create Trip'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return form;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showAppBar) {
      return _buildBody();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Trip'),
      ),
      body: _buildBody(),
    );
  }
}
