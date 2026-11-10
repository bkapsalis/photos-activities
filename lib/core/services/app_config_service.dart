import 'package:cloud_firestore/cloud_firestore.dart';

/// App-wide switches kept in Firestore's config/app document, changed in the
/// Firebase console rather than by an app release.
class AppConfigService {
  AppConfigService._();

  /// Whether everyone may upload photos, not just moderators. False while
  /// the document or the field is missing, matching the rules: uploads stay
  /// closed until someone opens them on purpose.
  static Stream<bool> uploadsOpen() => FirebaseFirestore.instance
      .doc('config/app')
      .snapshots()
      .map((snapshot) => snapshot.data()?['uploadsOpen'] == true);
}
