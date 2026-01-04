import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    this.onYouFolderLogin,
    required this.isBusy,
  });

  final VoidCallback onLogin;
  final VoidCallback? onYouFolderLogin;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    void handleYouFolderLogin() {
      final handler = onYouFolderLogin;
      if (handler != null) {
        handler();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouFolder login is coming soon.'),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/app_icon.png',
                  width: 72,
                  height: 72,
                ),
                const SizedBox(height: 16),
                Text(
                  'YouFolder',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Organize your YouTube playlists into nested playlists.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: isBusy ? null : onLogin,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Login with YouTube'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: isBusy ? null : handleYouFolderLogin,
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Login with YouFolder'),
                ),
                const SizedBox(height: 20),
                Text(
                  "By continuing you're agreeing to our terms and conditions.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
