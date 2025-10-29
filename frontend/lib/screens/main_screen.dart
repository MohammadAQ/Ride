import 'package:flutter/material.dart';
import 'package:carpal_app/screens/create_trip_screen.dart';
import 'package:carpal_app/screens/global_chat_screen.dart';
import 'package:carpal_app/screens/my_trips_screen.dart';
import 'package:carpal_app/screens/profile_screen.dart';
import 'package:carpal_app/screens/search_trips_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<_Destination> _destinations = <_Destination>[
    _Destination(
      title: 'Search Trips',
      page: SearchTripsScreen(showAppBar: false),
    ),
    _Destination(
      title: 'My Trips',
      page: MyTripsScreen(showAppBar: false),
    ),
    _Destination(
      title: 'Create Trip',
      page: CreateTripScreen(showAppBar: false),
    ),
    _Destination(
      title: 'Global Chat',
      page: GlobalChatScreen(showAppBar: false),
    ),
    _Destination(
      title: 'Profile',
      page: ProfileScreen(showAppBar: false),
    ),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_destinations[_selectedIndex].title),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _destinations[_selectedIndex].page,
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Search Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car_filled),
            label: 'My Trips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            label: 'Create Trip',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Global Chat',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _Destination {
  const _Destination({required this.title, required this.page});

  final String title;
  final Widget page;
}
