import 'package:flutter/material.dart';
import 'package:ride/l10n/app_localizations.dart';
import 'package:ride/screens/create_trip_screen.dart';
import 'package:ride/screens/my_bookings_screen.dart';
import 'package:ride/screens/my_trips_screen.dart';
import 'package:ride/screens/profile_screen.dart';
import 'package:ride/screens/search_trips_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static final List<_Destination> _destinations = <_Destination>[
    const _Destination(
      titleKey: 'nav_search_trips',
      icon: Icons.search,
      page: const SearchTripsScreen(showAppBar: false),
    ),
    const _Destination(
      titleKey: 'nav_my_trips',
      icon: Icons.directions_car_filled,
      page: const MyTripsScreen(showAppBar: false),
    ),
    const _Destination(
      titleKey: 'nav_create_trip',
      icon: Icons.add_circle_outline,
      page: const CreateTripScreen(showAppBar: false),
    ),
    const _Destination(
      titleKey: 'nav_my_bookings',
      icon: Icons.event_seat,
      page: const MyBookingsScreen(showAppBar: false),
    ),
    const _Destination(
      titleKey: 'nav_profile',
      icon: Icons.person,
      page: const ProfileScreen(showAppBar: false),
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final _Destination currentDestination = _destinations[_selectedIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.translate(currentDestination.titleKey)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: currentDestination.page,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: _destinations
            .map(
              (destination) => BottomNavigationBarItem(
                icon: Icon(destination.icon),
                label: context.translate(destination.titleKey),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.titleKey,
    required this.page,
    required this.icon,
  });

  final String titleKey;
  final Widget page;
  final IconData icon;
}
