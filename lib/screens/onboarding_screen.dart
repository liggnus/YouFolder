import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _showLogin = false;

  void _goToLogin() {
    setState(() => _showLogin = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) {
      return LoginScreen(
        onLogin: widget.controller.connect,
        isBusy: widget.controller.isBusy,
      );
    }
    return WelcomeScreen(onGetStarted: _goToLogin);
  }
}
