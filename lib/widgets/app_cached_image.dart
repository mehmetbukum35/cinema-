import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'pulsing_placeholder.dart';

enum AppImageCachePreset {
  /// Standard movie/TV posters (cards, lists, grids)
  poster,

  /// High-resolution detail backdrops & hero banners
  backdrop,

  /// Small avatars, thumbnails & profile badges
  avatar,

  /// Custom explicit cache dimensions
  custom,
}

/// A wrapper around [CachedNetworkImage] enforcing disk & RAM cache limits
/// to prevent mobile storage bloat and out-of-memory issues.
class AppCachedNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final AppImageCachePreset preset;
  final int? maxWidthDiskCache;
  final int? maxHeightDiskCache;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const AppCachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.preset = AppImageCachePreset.poster,
    this.maxWidthDiskCache,
    this.maxHeightDiskCache,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return placeholder?.call(context, imageUrl) ?? const PulsingPlaceholder();
    }

    final resolvedLimits = _resolveLimits();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: fit,
      width: width,
      height: height,
      maxWidthDiskCache: resolvedLimits.maxWidthDisk,
      maxHeightDiskCache: resolvedLimits.maxHeightDisk,
      memCacheWidth: resolvedLimits.memWidth,
      memCacheHeight: resolvedLimits.memHeight,
      placeholder: placeholder ?? (ctx, url) => const PulsingPlaceholder(),
      errorWidget: errorWidget ?? (ctx, url, err) => const PulsingPlaceholder(),
    );
  }

  _CacheLimits _resolveLimits() {
    switch (preset) {
      case AppImageCachePreset.poster:
        return _CacheLimits(
          maxWidthDisk: maxWidthDiskCache ?? 360,
          maxHeightDisk: maxHeightDiskCache ?? 540,
          memWidth: memCacheWidth ?? 360,
          memHeight: memCacheHeight ?? 540,
        );
      case AppImageCachePreset.backdrop:
        return _CacheLimits(
          maxWidthDisk: maxWidthDiskCache ?? 800,
          maxHeightDisk: maxHeightDiskCache ?? 1200,
          memWidth: memCacheWidth ?? 800,
          memHeight: memCacheHeight ?? 1200,
        );
      case AppImageCachePreset.avatar:
        return _CacheLimits(
          maxWidthDisk: maxWidthDiskCache ?? 200,
          maxHeightDisk: maxHeightDiskCache ?? 200,
          memWidth: memCacheWidth ?? 200,
          memHeight: memCacheHeight ?? 200,
        );
      case AppImageCachePreset.custom:
        return _CacheLimits(
          maxWidthDisk: maxWidthDiskCache,
          maxHeightDisk: maxHeightDiskCache,
          memWidth: memCacheWidth,
          memHeight: memCacheHeight,
        );
    }
  }
}

class _CacheLimits {
  final int? maxWidthDisk;
  final int? maxHeightDisk;
  final int? memWidth;
  final int? memHeight;

  const _CacheLimits({
    this.maxWidthDisk,
    this.maxHeightDisk,
    this.memWidth,
    this.memHeight,
  });
}
