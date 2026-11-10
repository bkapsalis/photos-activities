import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Every photo in the feed, carousel and full-screen view is drawn through
/// this, so they share one download cache, one loading state and one failure
/// state.
///
/// The cache is keyed by URL: a photo already fetched for a grid tile or a
/// thumbnail is not downloaded again when it is opened large.
///
/// On web this fetches the bytes and decodes them ([_webMethod]), the same
/// way the `Image.network` it replaced did. The package's default instead
/// decodes straight from an `<img>`, and those images cannot be rebuilt once
/// the browser's graphics layer drops them: measured on Chrome, every
/// thumbnail came back solid black after a full-screen photo had covered it.
/// Either way the picture is drawn into the canvas, so no `<img>` element is
/// put in the page for a right-click "Save image as".
///
/// The placeholder is deliberately still (no spinner): a grid can have
/// dozens of tiles loading at once, and a wall of spinners reads as broken.
class AppNetworkImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Decode at roughly this many physical pixels wide. For thumbnails, so a
  /// strip of them never expands every full-size photo in memory.
  final int? decodeWidth;

  /// Dark surroundings (the full-screen viewer) get dark placeholder and
  /// error states rather than a pale grey box.
  final bool onDark;

  /// When [url] changes, keep showing the old photo until the new one is
  /// ready, rather than the placeholder. For a view whose photo is swapped in
  /// place, such as the carousel's large photo.
  final bool keepPreviousWhileLoading;

  const AppNetworkImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.decodeWidth,
    this.onDark = false,
    this.keepPreviousWhileLoading = false,
  });

  static const _webMethod = ImageRenderMethodForWeb.HttpGet;

  /// The provider this widget draws from, for code that needs the image
  /// itself — such as measuring its real aspect ratio — without a second
  /// download.
  static ImageProvider provider(String url) =>
      CachedNetworkImageProvider(url, imageRenderMethodForWeb: _webMethod);

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      imageRenderMethodForWeb: _webMethod,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: decodeWidth,
      useOldImageOnUrlChange: keepPreviousWhileLoading,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => _ImageState(onDark: onDark),
      errorWidget: (_, _, _) => _ImageState(onDark: onDark, failed: true),
    );
  }
}

class _ImageState extends StatelessWidget {
  final bool onDark;
  final bool failed;

  const _ImageState({required this.onDark, this.failed = false});

  @override
  Widget build(BuildContext context) {
    final iconColor = onDark ? Colors.white38 : AppColors.textSecondary;
    return Container(
      color: onDark ? Colors.transparent : AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: failed
          ? Semantics(
              label: 'Photo could not be loaded',
              child: Icon(Icons.broken_image_outlined, size: 40, color: iconColor),
            )
          : Icon(
              Icons.image_outlined,
              size: 32,
              color: iconColor.withValues(alpha: 0.5),
            ),
    );
  }
}
