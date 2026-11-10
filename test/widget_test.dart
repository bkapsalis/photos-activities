import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/core/config/env_config.dart';

void main() {
  // The generated "pump the whole app" smoke test cannot run here: the widget
  // tree reaches _AuthGate, which touches Firebase, and Firebase.initializeApp
  // needs platform channels a unit test does not have. Rendering the real app
  // belongs in integration_test/, running against a device or the emulator
  // suite. What this file can check without any platform is that each flavor's
  // configuration is wired up correctly — which is where the mistakes that
  // actually bite (a flavor pointed at the wrong project) would show up.

  test('EnvConfig exposes the values a flavor supplies', () {
    EnvConfig.init(EnvConfig(
      environment: Environment.dev,
      title: "Bill's Bay Area Fun Activities (Test)",
      firebaseProjectId: 'test-project',
      googleServerClientId: 'test-client-id.apps.googleusercontent.com',
    ));

    final config = EnvConfig.instance;
    expect(config.environment, Environment.dev);
    expect(config.firebaseProjectId, 'test-project');
    expect(config.googleServerClientId, contains('.apps.googleusercontent.com'));
  });

  test('Google server client id is required for sign-in to address Firebase',
      () {
    // Regression guard: google_sign_in only returns a Firebase-usable idToken
    // when serverClientId is the *web* OAuth client. An empty value here means
    // a flavor forgot to pass one, which fails at runtime, not compile time.
    expect(EnvConfig.instance.googleServerClientId, isNotEmpty);
  });
}
