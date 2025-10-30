import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../l10n/app_localizations.dart';

class _CityOption {
  const _CityOption({required this.value, this.localizationKey});

  final String value;
  final String? localizationKey;

  String label(BuildContext context) {
    final key = localizationKey;
    if (key == null || key.isEmpty) {
      return value;
    }
    return context.translate(key);
  }
}

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({
    super.key,
    this.showAppBar = true,
    this.initialTripData,
  });

  final bool showAppBar;
  final Map<String, dynamic>? initialTripData;

  bool get isEditing => initialTripData != null;

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  static const List<_CityOption> _defaultCities = <_CityOption>[
    _CityOption(value: 'رام الله', localizationKey: 'city_ramallah'),
    _CityOption(value: 'البيرة', localizationKey: 'city_al_bireh'),
    _CityOption(value: 'نابلس', localizationKey: 'city_nablus'),
    _CityOption(value: 'جنين', localizationKey: 'city_jenin'),
    _CityOption(value: 'طولكرم', localizationKey: 'city_tulkarm'),
    _CityOption(value: 'قلقيلية', localizationKey: 'city_qalqilya'),
    _CityOption(value: 'طوباس', localizationKey: 'city_tubas'),
    _CityOption(value: 'سلفيت', localizationKey: 'city_salfit'),
    _CityOption(value: 'أريحا', localizationKey: 'city_jericho'),
    _CityOption(value: 'بيت لحم', localizationKey: 'city_bethlehem'),
    _CityOption(value: 'الخليل', localizationKey: 'city_hebron'),
  ];

  static const List<int> _seatOptions = <int>[1, 2, 3, 4, 5, 6];

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _seatsController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _carModelController = TextEditingController();
  final TextEditingController _carColorController = TextEditingController();
  final ApiService _apiService = ApiService();

  late final List<_CityOption> _cityOptions;
  late final bool _isEditing;
  String? _tripId;
  String? _fromCity;
  String? _toCity;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int? _selectedSeats;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cityOptions = List<_CityOption>.from(_defaultCities);
    _isEditing = widget.isEditing;
    if (_isEditing && widget.initialTripData != null) {
      _initialiseFromTrip(widget.initialTripData!);
    }
    _syncSelectedSeatsFromController();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _seatsController.dispose();
    _priceController.dispose();
    _carModelController.dispose();
    _carColorController.dispose();
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

  Future<void> _pickTime() async {
    FocusScope.of(context).unfocus();

    final TimeOfDay initialTime = _selectedTime ?? TimeOfDay.now();

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (pickedTime != null) {
      setState(() {
        _selectedTime = pickedTime;
        _timeController.text = _formatTime(pickedTime);
      });
    }
  }

  void _initialiseFromTrip(Map<String, dynamic> trip) {
    _tripId = _stringOrNull(trip['id']);

    final fromCity = _stringOrNull(trip['fromCity']);
    if (fromCity != null) {
      _ensureCityOptionExists(fromCity);
      _fromCity = fromCity;
    }

    final toCity = _stringOrNull(trip['toCity']);
    if (toCity != null) {
      _ensureCityOptionExists(toCity);
      _toCity = toCity;
    }

    final dateString = _stringOrNull(trip['date']);
    if (dateString != null) {
      final parsedDate = DateTime.tryParse(dateString);
      if (parsedDate != null) {
        _selectedDate = parsedDate;
        _dateController.text = _formatDate(parsedDate);
      } else {
        _dateController.text = dateString;
      }
    }

    final timeString = _stringOrNull(trip['time']);
    if (timeString != null) {
      final parsedTime = _parseTimeOfDay(timeString);
      if (parsedTime != null) {
        _selectedTime = parsedTime;
        _timeController.text = _formatTime(parsedTime);
      } else {
        _timeController.text = timeString;
      }
    }

    final priceValue = trip['price'];
    if (priceValue is num) {
      final formatted = priceValue % 1 == 0
          ? priceValue.toStringAsFixed(0)
          : priceValue.toStringAsFixed(2);
      _priceController.text = formatted;
    } else {
      final priceString = _stringOrNull(priceValue);
      if (priceString != null) {
        _priceController.text = priceString;
      }
    }

    final carModel = _stringOrNull(trip['carModel']);
    if (carModel != null) {
      _carModelController.text = carModel;
    }

    final carColor = _stringOrNull(trip['carColor']);
    if (carColor != null) {
      _carColorController.text = carColor;
    }

    final dynamic totalSeatsValue = trip['totalSeats'];
    if (totalSeatsValue is num) {
      _seatsController.text = totalSeatsValue.toInt().toString();
    } else {
      final String? seatsText =
          _stringOrNull(totalSeatsValue) ?? _stringOrNull(trip['availableSeats']);
      if (seatsText != null) {
        _seatsController.text = seatsText;
      }
    }
    _syncSelectedSeatsFromController();
  }

  void _syncSelectedSeatsFromController() {
    final parsed = int.tryParse(_seatsController.text);
    if (parsed != null && _seatOptions.contains(parsed)) {
      _selectedSeats = parsed;
    } else {
      _selectedSeats = null;
    }
  }

  void _ensureCityOptionExists(String city) {
    if (!_cityOptions.any((option) => option.value == city)) {
      _cityOptions.add(_CityOption(value: city));
    }
  }

  String _seatLabel(BuildContext context, int seatCount) {
    return context.translate('create_trip_seat_option_$seatCount');
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }
    final result = value.toString().trim();
    if (result.isEmpty) {
      return null;
    }
    return result;
  }

  TimeOfDay? _parseTimeOfDay(String value) {
    final parts = value.split(':');
    if (parts.length < 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  String _formatDate(DateTime date) {
    final String year = date.year.toString().padLeft(4, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime(TimeOfDay time) {
    final hours = time.hour.toString().padLeft(2, '0');
    final minutes = time.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
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
        SnackBar(
          content: Text(context.translate('create_trip_toast_login_required')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final DateTime? date = _selectedDate;
    if (date == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_invalid_date')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final TimeOfDay? time = _selectedTime;
    if (time == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_invalid_time')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final String? fromCity = _fromCity;
    final String? toCity = _toCity;
    final double? price =
        double.tryParse(_priceController.text.trim().replaceAll(',', '.'));
    final String carModel = _carModelController.text.trim();
    final String carColor = _carColorController.text.trim();
    final int? totalSeats = int.tryParse(_seatsController.text.trim());
    if (price == null) {
      // Should not happen because validator already checks this, but guard anyway.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_invalid_price')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (totalSeats == null || totalSeats <= 0) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_invalid_seats')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == null || toCity == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_select_cities')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == toCity) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.translate('create_trip_toast_different_cities')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Fetch the driver's phone number from Firestore using their UID so we
      // can reuse the saved profile data instead of a manual input field.
      final String? driverPhoneNumber =
          await _fetchDriverPhoneNumber(user.uid);
      if (driverPhoneNumber == null) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) {
            return AlertDialog(
              title: const Text('Missing phone number'),
              content: const Text(
                'You need to add your phone number in your profile before creating a trip.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }

      final payload = <String, dynamic>{
        'fromCity': fromCity,
        'toCity': toCity,
        'date': _formatDate(date),
        'time': _formatTime(time),
        'price': price,
        'carModel': carModel,
        'carColor': carColor,
        // Add the driver's saved phone number so the trip document links back
        // to the contact details stored in their Firestore profile.
        'phoneNumber': driverPhoneNumber,
        'totalSeats': totalSeats,
      };

      if (_isEditing) {
        final tripId = _tripId;
        if (tripId == null || tripId.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(context.translate('create_trip_toast_missing_trip')),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        final updatedTrip = await _apiService.updateTrip(tripId, payload);

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.translate('create_trip_toast_edit_success'),
            ),
          ),
        );

        Navigator.of(context).pop(updatedTrip);
      } else {
        await _apiService.createTrip(payload);

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.translate('create_trip_toast_create_success'),
            ),
          ),
        );

        currentState.reset();
        setState(() {
          _fromCity = null;
          _toCity = null;
          _selectedDate = null;
          _selectedTime = null;
        });
        _dateController.clear();
        _timeController.clear();
        _seatsController.clear();
        _selectedSeats = null;
        _priceController.clear();
        _carModelController.clear();
        _carColorController.clear();

        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!context.mounted) return;

        if (widget.showAppBar) {
          Navigator.of(context).pop();
        }
      }
    } on ApiException catch (error) {
      if (!context.mounted) return;
      final baseMessage = context.translate(
        _isEditing
            ? 'create_trip_toast_edit_failed'
            : 'create_trip_toast_create_failed',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$baseMessage: ${error.message}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      final message = context.translate(
        _isEditing
            ? 'create_trip_toast_edit_unexpected'
            : 'create_trip_toast_create_unexpected',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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

  Future<String?> _fetchDriverPhoneNumber(String userId) async {
    final String trimmedId = userId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }

    // Retrieve the driver's persisted phone number from Firestore so we can
    // reuse the same contact info when creating trip documents.
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
        .instance
        .collection('users')
        .doc(trimmedId)
        .get();

    if (!snapshot.exists) {
      return null;
    }

    final Map<String, dynamic>? data = snapshot.data();
    if (data == null) {
      return null;
    }

    return _stringOrNull(data['phoneNumber']);
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textDirection = Directionality.of(context);
    final String headerTitle = context.translate(
      _isEditing
          ? 'create_trip_header_title_edit'
          : 'create_trip_header_title_new',
    );
    final String headerSubtitle = context.translate(
      _isEditing
          ? 'create_trip_header_subtitle_edit'
          : 'create_trip_header_subtitle_new',
    );

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
                child: Directionality(
                  textDirection: textDirection,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          headerTitle,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          headerSubtitle,
                          textAlign: TextAlign.start,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          value: _fromCity,
                          isExpanded: true,
                          items: _cityOptions
                              .map(
                                (city) => DropdownMenuItem<String>(
                                  value: city.value,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(city.label(context)),
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_departure_label'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🧭'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _fromCity = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return context
                                  .translate('create_trip_departure_error');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _toCity,
                          isExpanded: true,
                          items: _cityOptions
                              .map(
                                (city) => DropdownMenuItem<String>(
                                  value: city.value,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(city.label(context)),
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_destination_label'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('📍'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _toCity = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return context
                                  .translate('create_trip_destination_error');
                            }
                            if (value == _fromCity) {
                              return context.translate(
                                  'create_trip_destination_same_error');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _dateController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_date_label'),
                            hintText: context.translate('create_trip_date_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('📅'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onTap: _pickDate,
                          validator: (value) {
                            if (_selectedDate == null) {
                              return context
                                  .translate('create_trip_date_validation_error');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _timeController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_time_label'),
                            hintText: context.translate('create_trip_time_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🕐'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onTap: _pickTime,
                          validator: (value) {
                            if (_selectedTime == null) {
                              return context
                                  .translate('create_trip_time_validation_error');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        // Dropdown for selecting available seats (1-6) while keeping
                        // compatibility with the existing _seatsController used for
                        // Firestore integration.
                        DropdownButtonFormField<int>(
                          value: _selectedSeats,
                          isExpanded: true,
                          items: _seatOptions
                              .map(
                                (seat) => DropdownMenuItem<int>(
                                  value: seat,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(_seatLabel(context, seat)),
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_seats_label'),
                            hintText: context.translate('create_trip_seats_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('💺'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _selectedSeats = value;
                              _seatsController.text =
                                  value != null ? value.toString() : '';
                            });
                          },
                          validator: (value) {
                            if (value == null) {
                              return context
                                  .translate('create_trip_seats_validation_error');
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
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          decoration: InputDecoration(
                            labelText: context.translate('create_trip_price_label'),
                            hintText: context.translate('create_trip_price_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('💰'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return context
                                  .translate('create_trip_price_validation_required');
                            }
                            final price =
                                double.tryParse(value.trim().replaceAll(',', '.'));
                            if (price == null || price <= 0) {
                              return context
                                  .translate('create_trip_price_validation_positive');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _carModelController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_car_model_label'),
                            hintText:
                                context.translate('create_trip_car_model_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🚗'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return context
                                  .translate('create_trip_car_model_validation');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _carColorController,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText:
                                context.translate('create_trip_car_color_label'),
                            hintText:
                                context.translate('create_trip_car_color_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🎨'),
                            ),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return context
                                  .translate('create_trip_car_color_validation');
                            }
                            return null;
                          },
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
                              : Icon(_isEditing ? Icons.save_outlined : Icons.check_circle_outline),
                          label: Text(
                            _isSubmitting
                                ? (_isEditing
                                    ? context.translate('create_trip_button_saving')
                                    : context.translate(
                                        'create_trip_button_creating'))
                                : (_isEditing
                                    ? context.translate('create_trip_button_save')
                                    : context
                                        .translate('create_trip_button_create')),
                          ),
                        ),
                        if (_isEditing) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () {
                                    Navigator.of(context).maybePop();
                                  },
                            child:
                                Text(context.translate('create_trip_button_cancel')),
                          ),
                        ],
                      ],
                    ),
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
        title: Text(
          context.translate(
            _isEditing
                ? 'create_trip_appbar_edit'
                : 'nav_create_trip',
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
}
