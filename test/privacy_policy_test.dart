import 'dart:io';

import 'package:bills_bay_area/core/config/contact.dart';
import 'package:bills_bay_area/core/config/env_config.dart';
import 'package:bills_bay_area/features/safety/community_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

EnvConfig _config(Environment environment, String projectId) => EnvConfig(
  environment: environment,
  title: "Bill's Bay Area Fun Activities",
  firebaseProjectId: projectId,
  googleServerClientId: '1-test.apps.googleusercontent.com',
);

void main() {
  group('PrivacyPolicy', () {
    test('lives on each environment\'s own website', () {
      EnvConfig.init(_config(Environment.prod, 'photos-activities-prod'));
      expect(
        EnvConfig.instance.website,
        'https://photos-activities-prod.web.app',
      );
      expect(
        PrivacyPolicy.url.toString(),
        'https://photos-activities-prod.web.app/privacy',
      );

      EnvConfig.init(_config(Environment.staging, 'photos-activities-staging'));
      expect(
        PrivacyPolicy.url.toString(),
        'https://photos-activities-staging.web.app/privacy',
      );
    });

    testWidgets('is linked under the sign-in buttons', (tester) async {
      EnvConfig.init(_config(Environment.dev, 'photos-activities-dev'));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RulesAgreementNote())),
      );
      expect(find.text('Community rules'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
    });
  });

  group('The website\'s pages', () {
    final privacy = File('web/privacy.html').readAsStringSync();
    final deletion = File('web/delete-account.html').readAsStringSync();

    test('give the same contact as the app', () {
      expect(privacy, contains(contactEmail));
      expect(deletion, contains(contactEmail));
    });

    test('link to each other', () {
      expect(privacy, contains('href="delete-account.html"'));
      expect(deletion, contains('href="privacy.html"'));
    });
  });
}
