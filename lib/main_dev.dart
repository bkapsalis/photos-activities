import 'package:flutter/material.dart';
import 'core/config/env_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.dev,
    title: "Bill's Fun Things To Do In The Bay Area! (Dev)",
    firebaseProjectId: "Photos-Activity-dev",
  ));

  // TODO: Firebase init after running flutterfire configure
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const BillsBayAreaApp());
}
