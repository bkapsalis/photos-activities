import 'package:integration_test/integration_test.dart';

import '../test/support/encoder_check.dart';

/// Android and iOS. See encoder_check.dart for how to run each platform.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  defineEncoderCheck();
}
