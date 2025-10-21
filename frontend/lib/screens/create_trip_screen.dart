import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';

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
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _carModelController = TextEditingController();
  final TextEditingController _carColorController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final ApiService _apiService = ApiService();

  late final List<String> _cityOptions;
  late final bool _isEditing;
  String? _tripId;
  String? _fromCity;
  String? _toCity;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cityOptions = List<String>.from(_cities);
    _isEditing = widget.isEditing;
    if (_isEditing && widget.initialTripData != null) {
      _initialiseFromTrip(widget.initialTripData!);
    }
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _priceController.dispose();
    _carModelController.dispose();
    _carColorController.dispose();
    _phoneController.dispose();
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
      if (!_cityOptions.contains(fromCity)) {
        _cityOptions.add(fromCity);
      }
      _fromCity = fromCity;
    }

    final toCity = _stringOrNull(trip['toCity']);
    if (toCity != null) {
      if (!_cityOptions.contains(toCity)) {
        _cityOptions.add(toCity);
      }
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

    final phoneNumber = _stringOrNull(trip['phoneNumber']);
    if (phoneNumber != null) {
      _phoneController.text = phoneNumber;
    }
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
        const SnackBar(
          content: Text('يجب تسجيل الدخول لإنشاء رحلة.'),
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
          content: Text('يرجى اختيار تاريخ صالح للرحلة.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final TimeOfDay? time = _selectedTime;
    if (time == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار وقت صالح للرحلة.'),
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
    final String phoneNumber = _phoneController.text.trim();
    if (price == null) {
      // Should not happen because validator already checks this, but guard anyway.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال سعر صالح.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == null || toCity == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار مدينتي الانطلاق والوصول.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (fromCity == toCity) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب أن تكون مدينتا الانطلاق والوصول مختلفتين.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final payload = <String, dynamic>{
      'fromCity': fromCity,
      'toCity': toCity,
      'date': _formatDate(date),
      'time': _formatTime(time),
      'price': price,
      'carModel': carModel,
      'carColor': carColor,
      'phoneNumber': phoneNumber,
    };

    try {
      if (_isEditing) {
        final tripId = _tripId;
        if (tripId == null || tripId.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تعذر تحديد الرحلة لتعديلها. حاول مرة أخرى.'),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }

        final updatedTrip = await _apiService.updateTrip(tripId, payload);

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التعديلات بنجاح'),
          ),
        );

        Navigator.of(context).pop(updatedTrip);
      } else {
        await _apiService.createTrip(payload);

        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء الرحلة بنجاح ✅'),
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
        _priceController.clear();
        _carModelController.clear();
        _carColorController.clear();
        _phoneController.clear();

        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!context.mounted) return;

        if (widget.showAppBar) {
          Navigator.of(context).pop();
        }
      }
    } on ApiException catch (error) {
      if (!context.mounted) return;
      final message = _isEditing
          ? 'فشل حفظ التعديلات: ${error.message}'
          : 'فشل إنشاء الرحلة: ${error.message}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'فشل حفظ التعديلات: حدث خطأ غير متوقع'
                : 'فشل إنشاء الرحلة: حدث خطأ غير متوقع',
          ),
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
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isEditing ? 'تعديل الرحلة' : 'إنشاء رحلة جديدة',
                          textAlign: TextAlign.right,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _isEditing
                              ? 'قم بتحديث تفاصيل رحلتك الحالية.'
                              : 'املأ جميع تفاصيل الرحلة ليتمكن الركاب من الانضمام بسهولة.',
                          textAlign: TextAlign.right,
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
                                  value: city,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(city),
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'مدينة الانطلاق',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🧭'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _fromCity = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار مدينة الانطلاق';
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
                                  value: city,
                                  child: Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(city),
                                  ),
                                ),
                              )
                              .toList(),
                          decoration: const InputDecoration(
                            labelText: 'مدينة الوصول',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('📍'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _toCity = value;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى اختيار مدينة الوصول';
                            }
                            if (value == _fromCity) {
                              return 'يجب أن تكون مدينة الوصول مختلفة عن مدينة الانطلاق';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _dateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'التاريخ',
                            hintText: 'اختر تاريخ الرحلة',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('📅'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onTap: _pickDate,
                          validator: (value) {
                            if (_selectedDate == null) {
                              return 'يرجى اختيار تاريخ الرحلة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _timeController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'الوقت',
                            hintText: 'اختر وقت الرحلة',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🕐'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          onTap: _pickTime,
                          validator: (value) {
                            if (_selectedTime == null) {
                              return 'يرجى اختيار وقت الرحلة';
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
                          decoration: const InputDecoration(
                            labelText: 'السعر',
                            hintText: 'أدخل سعر الرحلة',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('💰'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال السعر';
                            }
                            final price = double.tryParse(value.trim().replaceAll(',', '.'));
                            if (price == null || price <= 0) {
                              return 'أدخل رقمًا صحيحًا أكبر من صفر';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _carModelController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'طراز السيارة',
                            hintText: 'مثال: Kia Sportage 2021',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🚗'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال طراز السيارة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _carColorController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'لون السيارة',
                            hintText: 'مثال: أسود',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('🎨'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال لون السيارة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'رقم الجوال',
                            hintText: 'أدخل رقم التواصل مع السائق',
                            border: OutlineInputBorder(),
                            prefixIcon: Padding(
                              padding: EdgeInsetsDirectional.only(start: 12, end: 8),
                              child: Text('📞'),
                            ),
                            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'الرجاء إدخال رقم الجوال';
                            }
                            if (value.trim().length < 6) {
                              return 'رقم الجوال المدخل غير صالح';
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
                                ? (_isEditing ? 'جاري حفظ التعديلات...' : 'جاري إنشاء الرحلة...')
                                : (_isEditing ? 'حفظ التعديلات' : 'إنشاء الرحلة'),
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
                            child: const Text('إلغاء'),
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
        title: Text(_isEditing ? 'تعديل الرحلة' : 'إنشاء رحلة'),
      ),
      body: _buildBody(),
    );
  }
}
