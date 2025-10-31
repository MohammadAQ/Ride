import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:ride/l10n/app_localizations.dart';
import 'package:ride/screens/create_trip_screen.dart';
import 'package:ride/screens/my_bookings_screen.dart';
import 'package:ride/screens/my_trips_screen.dart';
import 'package:ride/screens/profile_screen.dart';
import 'package:ride/screens/search_trips_screen.dart';
import 'package:ride/services/navigation_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final Stream<int> _pendingRequestsCountStream;

  static final List<_Destination> _destinations = <_Destination>[
    _Destination(
      titleKey: 'nav_search_trips',
      icon: Icons.search,
      navigatorKey: NavigationService.searchTripsNavKey,
      pageBuilder: () => const SearchTripsScreen(showAppBar: true),
    ),
    _Destination(
      titleKey: 'nav_my_trips',
      icon: Icons.directions_car_filled,
      navigatorKey: NavigationService.myTripsNavKey,
      pageBuilder: () => const MyTripsScreen(showAppBar: true),
    ),
    _Destination(
      titleKey: 'nav_create_trip',
      icon: Icons.add_circle_outline,
      navigatorKey: NavigationService.createTripNavKey,
      pageBuilder: () => const CreateTripScreen(showAppBar: true),
    ),
    _Destination(
      titleKey: 'nav_my_bookings',
      icon: Icons.event_seat,
      navigatorKey: NavigationService.myBookingsNavKey,
      pageBuilder: () => const MyBookingsScreen(showAppBar: true),
    ),
    _Destination(
      titleKey: 'nav_profile',
      icon: Icons.person,
      navigatorKey: NavigationService.profileNavKey,
      pageBuilder: () => const ProfileScreen(showAppBar: true),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pendingRequestsCountStream = _buildPendingRequestsCountStream();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) {
      final NavigatorState? currentNavigator =
          _destinations[index].navigatorKey.currentState;
      currentNavigator?.popUntil((Route<dynamic> route) => route.isFirst);
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  Stream<int> _buildPendingRequestsCountStream() {
    return FirebaseAuth.instance.authStateChanges().asyncExpand((User? user) {
      if (user == null || user.uid.trim().isEmpty) {
        return Stream<int>.value(0);
      }

      return FirebaseFirestore.instance
          .collection('ride_requests')
          .where('driver_id', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.size);
    });
  }

  Widget _buildNavIcon(_Destination destination) {
    if (destination.titleKey != 'nav_my_trips') {
      return Icon(destination.icon);
    }

    return StreamBuilder<int>(
      stream: _pendingRequestsCountStream,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        final int count = snapshot.data ?? 0;
        final TextDirection textDirection = Directionality.of(context);
        final bool isRtl = textDirection == TextDirection.rtl;

        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Icon(destination.icon),
            if (count > 0)
              Positioned(
                top: -4,
                right: isRtl ? null : -6,
                left: isRtl ? -6 : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minHeight: 18,
                    minWidth: 18,
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final NavigatorState? currentNavigator =
            _destinations[_selectedIndex].navigatorKey.currentState;
        if (currentNavigator == null) {
          return true;
        }

        final bool isFirstRoute = !await currentNavigator.maybePop();
        if (isFirstRoute) {
          if (_selectedIndex != 0) {
            setState(() {
              _selectedIndex = 0;
            });
            return false;
          }
        }

        return isFirstRoute;
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedIndex,
          children:
              _destinations.map((destination) => _buildNavigator(destination)).toList(),
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: Colors.deepPurple,
          unselectedItemColor: Colors.grey,
          items: _destinations
              .map(
                (destination) => BottomNavigationBarItem(
                  icon: _buildNavIcon(destination),
                  label: context.translate(destination.titleKey),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.titleKey,
    required this.icon,
    required this.navigatorKey,
    required this.pageBuilder,
  });

  final String titleKey;
  final IconData icon;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function() pageBuilder;
}

Widget _buildNavigator(_Destination destination) {
  return Navigator(
    key: destination.navigatorKey,
    onGenerateRoute: (RouteSettings settings) {
      return MaterialPageRoute<void>(
        builder: (BuildContext context) => destination.pageBuilder(),
        settings: settings,
      );
    },
  );
}
