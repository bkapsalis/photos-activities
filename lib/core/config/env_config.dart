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

  /// The browser key for Google's Drive picker on the web, or null where it
  /// is not set up, which leaves the web upload screen without "Photos from
  /// the Cloud". Not a secret: it is served to every browser, and Google
  /// accepts it only for the Picker API, only from this app's sites.
  final String? googlePickerApiKey;

  EnvConfig({
    required this.environment,
    required this.title,
    required this.firebaseProjectId,
    required this.googleServerClientId,
    this.googlePickerApiKey,
  });

  /// The Google Cloud project number, which Drive's picker takes as the app
  /// id so the files picked are opened to this app. It leads every OAuth
  /// client id the project issues.
  String get googleCloudProjectNumber => googleServerClientId.split('-').first;

  static late EnvConfig _instance;

  static void init(EnvConfig config) {
    _instance = config;
  }

  static EnvConfig get instance => _instance;

  bool get isDev => environment == Environment.dev;
  bool get isStaging => environment == Environment.staging;
  bool get isProd => environment == Environment.prod;
}
