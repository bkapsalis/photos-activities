import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/constants.dart';

/// Phones stay upright; tablets turn freely.
///
/// Held sideways, a phone is too short for the header, search and tabs to
/// leave room for any photos, so the app keeps phones in portrait, as most
/// photo apps do. A tablet, or an unfolded foldable, has room both ways.
/// Decided from the window's shorter side, so it follows a foldable as it
/// opens and closes. A browser decides for itself.
class OrientationPolicy extends StatefulWidget {
  final Widget child;

  const OrientationPolicy({super.key, required this.child});

  @override
  State<OrientationPolicy> createState() => _OrientationPolicyState();
}

class _OrientationPolicyState extends State<OrientationPolicy> {
  bool? _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb) return;
    final phone = isPhoneSized(MediaQuery.sizeOf(context));
    if (phone == _phone) return;
    _phone = phone;
    SystemChrome.setPreferredOrientations(orientationsFor(phone: phone));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A window whose shorter side is under the tablet breakpoint, whichever
/// way it is held.
@visibleForTesting
bool isPhoneSized(Size size) => size.shortestSide < Breakpoints.mobile;

/// Portrait for a phone. Empty for a tablet, which leaves it every
/// orientation the app's platform settings allow.
@visibleForTesting
List<DeviceOrientation> orientationsFor({required bool phone}) =>
    phone ? const [DeviceOrientation.portraitUp] : const [];
