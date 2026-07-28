enum Environment { dev, staging, prod }

class EnvConfig {
  final Environment environment;
  final String title;
  final String firebaseProjectId;

  EnvConfig({
    required this.environment,
    required this.title,
    required this.firebaseProjectId,
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
