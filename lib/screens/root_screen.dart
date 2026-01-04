import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'library_screen.dart';
import 'onboarding_screen.dart';

class RootScreen extends StatelessWidget {
  const RootScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isSignedIn) {
          return LibraryScreen(controller: controller);
        }
        return OnboardingScreen(controller: controller);
      },
    );
  }
}
