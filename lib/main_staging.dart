import 'package:flutter/material.dart';
import 'core/config/env_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.staging,
    title: "Bill's Fun Things To Do In The Bay Area! (Staging)",
    firebaseProjectId: "Photos-Activity-staging",
  ));

  // TODO: Firebase init after running flutterfire configure
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const BillsBayAreaApp());
}
