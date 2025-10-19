import 'package:flutter/material.dart';

class CreateTripScreen extends StatelessWidget {
  const CreateTripScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Trip'),
      ),
      body: const Center(
        child: Text(
          'Create Trip Screen\n(Here you’ll add form fields for drivers)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
