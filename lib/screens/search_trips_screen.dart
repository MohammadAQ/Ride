import 'package:flutter/material.dart';

class SearchTripsScreen extends StatelessWidget {
  const SearchTripsScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  Widget _buildBody() {
    return const Center(
      child: Text(
        'Search Trips Screen\n(Here you’ll add filters and search results later)',
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!showAppBar) {
      return _buildBody();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Trips'),
      ),
      body: _buildBody(),
    );
  }
}
