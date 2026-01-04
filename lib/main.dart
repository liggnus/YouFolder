import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/auth_config.dart';
import 'controllers/app_controller.dart';
import 'data/app_storage.dart';
import 'screens/root_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final storage = AppStorage();
  final repository = await storage.load();
  final signIn = GoogleSignIn(
    scopes: const [
      YouTubeApi.youtubeScope,
      YouTubeApi.youtubeReadonlyScope,
    ],
    clientId: (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
        ? iosClientId
        : null,
  );
  final controller = AppController(
    repository: repository,
    storage: storage,
    signIn: signIn,
  );
  await controller.init();
  runApp(YouFolderApp(controller: controller));
}

class YouFolderApp extends StatelessWidget {
  const YouFolderApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YouFolder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: RootScreen(controller: controller),
    );
  }
}
