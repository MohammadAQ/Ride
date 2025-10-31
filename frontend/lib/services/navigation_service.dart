import 'package:flutter/material.dart';

class NavigationService {
  NavigationService._();

  static final GlobalKey<NavigatorState> searchTripsNavKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> myTripsNavKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> createTripNavKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> myBookingsNavKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<NavigatorState> profileNavKey =
      GlobalKey<NavigatorState>();
}
