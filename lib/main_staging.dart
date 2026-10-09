import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options_staging.dart';
import 'core/config/env_config.dart';
import 'core/services/crash_reporting.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.staging,
    title: "Bill's Bay Area Fun Activities (Staging)",
    firebaseProjectId: "photos-activities-staging",
    googleServerClientId:
        "593867148848-hgfqofn0goh79b8bj20l9q75pti5gp9c.apps.googleusercontent.com",
  ));

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Firebase already initialized (e.g. during hot restart)
  }

  await CrashReporting.install();

  runApp(const BillsBayAreaApp());
}
