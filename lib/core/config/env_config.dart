enum Environment { dev, staging, prod }

class EnvConfig {
  final Environment environment;
  final String title;
  final String firebaseProjectId;

  /// The OAuth **web** client id for this Firebase project.
  ///
  /// google_sign_in needs it as `serverClientId` on Android (it is what makes
  /// the returned idToken addressed to Firebase) and as `clientId` on web.
  /// iOS reads its own client id from GoogleService-Info.plist.
  final String googleServerClientId;

  EnvConfig({
    required this.environment,
    required this.title,
    required this.firebaseProjectId,
    required this.googleServerClientId,
  });

  static late EnvConfig _instance;

  static void init(EnvConfig config) {
    _instance = config;
  }

  static EnvConfig get instance => _instance;

  bool get isDev => environment == Environment.dev;
  bool get isStaging => environment == Environment.staging;
  bool get isProd => environment == Environment.prod;
}
