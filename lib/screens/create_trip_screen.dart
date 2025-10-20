import 'package:flutter/material.dart';

class CreateTripScreen extends StatelessWidget {
  const CreateTripScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  Widget _buildBody() {
    return const Center(
      child: Text(
        'Create Trip Screen\n(Here you’ll add form fields for drivers)',
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
        title: const Text('Create Trip'),
      ),
      body: _buildBody(),
    );
  }
}
