import 'package:flutter/material.dart';

class SearchTripsScreen extends StatelessWidget {
  const SearchTripsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Trips'),
      ),
      body: const Center(
        child: Text(
          'Search Trips Screen\n(Here you’ll add filters and search results later)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
