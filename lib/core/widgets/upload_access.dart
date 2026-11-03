import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_config_service.dart';
import '../utils/permissions.dart';

/// Builds [builder] with whether the signed-in user may upload, kept up to
/// date as the uploadsOpen switch changes. See [canUpload].
///
/// Until the switch has been read, and if it cannot be read, uploading is
/// not offered to anyone but a moderator: the rules refuse everyone else in
/// that state too.
class UploadAccess extends StatefulWidget {
  final Widget Function(BuildContext context, bool canUpload) builder;

  /// Stand-ins for Firestore and Firebase Auth, for widget tests.
  final Stream<bool>? uploadsOpen;
  final User? user;

  const UploadAccess({
    super.key,
    required this.builder,
    this.uploadsOpen,
    this.user,
  });

  @override
  State<UploadAccess> createState() => _UploadAccessState();
}

class _UploadAccessState extends State<UploadAccess> {
  /// Subscribed once: a new stream each build would resubscribe every time.
  late final Stream<bool> _uploadsOpen =
      widget.uploadsOpen ?? AppConfigService.uploadsOpen();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _uploadsOpen,
      initialData: false,
      builder: (context, snapshot) => widget.builder(
        context,
        canUpload(uploadsOpen: snapshot.data ?? false, user: widget.user),
      ),
    );
  }
}
