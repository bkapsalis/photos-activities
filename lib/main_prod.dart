import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options_prod.dart';
import 'core/config/env_config.dart';
import 'core/services/crash_reporting.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  EnvConfig.init(EnvConfig(
    environment: Environment.prod,
    title: "Bill's Bay Area Fun Activities",
    firebaseProjectId: "photos-activities-prod",
    googleServerClientId:
        "978335208017-u5bvv9gmbvlas81dmh3i0subm3havcu7.apps.googleusercontent.com",
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
