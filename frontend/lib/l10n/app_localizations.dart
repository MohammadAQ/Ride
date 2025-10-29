import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('ar', 'PS'),
    Locale('en', 'US'),
  ];

  static const fallbackLocale = Locale('ar', 'PS');

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  Map<String, String> _localizedStrings = const <String, String>{};

  static AppLocalizations of(BuildContext context) {
    final AppLocalizations? result = maybeOf(context);
    assert(result != null, 'No AppLocalizations instance found in widget tree.');
    return result!;
  }

  static AppLocalizations? maybeOf(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static Locale localeResolutionCallback(Locale? locale, Iterable<Locale> supportedLocales) {
    if (locale == null) {
      return fallbackLocale;
    }

    for (final Locale supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == locale.languageCode &&
          supportedLocale.countryCode == locale.countryCode) {
        return supportedLocale;
      }
    }

    return fallbackLocale;
  }

  Future<void> load() async {
    final Map<String, String>? primary = await _loadLocalizedStrings(locale);
    final Map<String, String>? fallback =
        await _loadLocalizedStrings(fallbackLocale);

    _localizedStrings = primary ?? fallback ?? const <String, String>{};
  }

  Future<Map<String, String>?> _loadLocalizedStrings(Locale targetLocale) async {
    final String assetSuffix = _assetName(targetLocale);
    final String assetPath = 'assets/lang/$assetSuffix.json';

    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final Map<String, dynamic> jsonMap =
          json.decode(jsonString) as Map<String, dynamic>;
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } on FlutterError {
      return null;
    }
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  static String _assetName(Locale locale) {
    final String languageCode = locale.languageCode.toLowerCase();
    final String? countryCode = locale.countryCode;

    if (countryCode == null || countryCode.isEmpty) {
      return languageCode;
    }

    return '$languageCode-${countryCode.toUpperCase()}';
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (Locale supportedLocale) =>
          supportedLocale.languageCode == locale.languageCode &&
          supportedLocale.countryCode == locale.countryCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    final AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) {
    return false;
  }
}

extension LocalizationBuildContext on BuildContext {
  String translate(String key) {
    return AppLocalizations.maybeOf(this)?.translate(key) ?? key;
  }
}
