import 'package:flutter_test/flutter_test.dart';
import 'package:bills_bay_area/app.dart';
import 'package:bills_bay_area/core/config/env_config.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    EnvConfig.init(EnvConfig(
      environment: Environment.dev,
      title: 'Bills Bay Area (Test)',
      firebaseProjectId: 'test-project',
    ));
    await tester.pumpWidget(const BillsBayAreaApp());
    expect(find.text('Bills Bay Area 🏔'), findsOneWidget);
  });
}
