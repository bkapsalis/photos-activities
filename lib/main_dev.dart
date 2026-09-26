import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options_dev.dart';
import 'core/config/env_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.dev,
    title: "Bill's Bay Area Fun Activities (Dev)",
    firebaseProjectId: "photos-activities-dev",
    googleServerClientId:
        "1036671893175-u1tqrdfs780uq10c9dnjk3dqtmnrjaqg.apps.googleusercontent.com",
  ));

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized (e.g. during hot restart)
    // Just use the existing instance.
  }

  runApp(const BillsBayAreaApp());
}
