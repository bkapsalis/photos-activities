import 'package:flutter/material.dart';
import 'core/config/env_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.prod,
    title: "Bill's Fun Things To Do In The Bay Area!",
    firebaseProjectId: "Photos-Activity-prod",
  ));

  // TODO: Firebase init after running flutterfire configure
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const BillsBayAreaApp());
}
