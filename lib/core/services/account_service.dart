import 'package:cloud_functions/cloud_functions.dart';

/// Deleting the reader's account, which App Store guideline 5.1.1(v) and
/// Google Play require of an app people sign up to.
///
/// The deleteMyAccount function (functions/src/account.ts) does the work:
/// it can remove everything at once, including the likes and comments
/// counted on other people's photos, which the app may not change.
class AccountService {
  // Where the functions are deployed: REGION in functions/src/config.ts.
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-west1');

  /// Deletes the signed-in account and everything in it. A registered
  /// reader must have just signed in again: AuthService.confirmIdentity.
  /// Throws [FirebaseFunctionsException]; a failed-precondition one has a
  /// message fit to show.
  Future<void> deleteMyAccount() => _functions
      .httpsCallable(
        'deleteMyAccount',
        // Someone who posted a great deal takes a while to clear.
        options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
      )
      .call<Object?>();
}
