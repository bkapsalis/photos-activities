import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/app.dart';
import 'package:bills_bay_area/core/config/env_config.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    EnvConfig.init(EnvConfig(
      environment: Environment.dev,
      title: "Bill's Fun Things To Do In The Bay Area! (Test)",
      firebaseProjectId: 'test-project',
    ));
    await tester.pumpWidget(const BillsBayAreaApp());
    expect(find.text("Bill's Fun Things To Do In The Bay Area! \u{1F3D4}"), findsOneWidget);
  });
}
