enum DiscoveryMedia { any, movie, tv }

enum DiscoveryDuration { any, short, medium, long }

enum DiscoveryFamiliarity { safe, balanced, surprise }

enum DiscoveryOrigin { any, local, foreign }

class DiscoveryContext {
  const DiscoveryContext({
    this.media = DiscoveryMedia.any,
    this.duration = DiscoveryDuration.any,
    this.familiarity = DiscoveryFamiliarity.balanced,
    this.origin = DiscoveryOrigin.any,
  });

  final DiscoveryMedia media;
  final DiscoveryDuration duration;
  final DiscoveryFamiliarity familiarity;
  final DiscoveryOrigin origin;

  bool get isDefault =>
      media == DiscoveryMedia.any &&
      duration == DiscoveryDuration.any &&
      familiarity == DiscoveryFamiliarity.balanced &&
      origin == DiscoveryOrigin.any;

  DiscoveryContext copyWith({
    DiscoveryMedia? media,
    DiscoveryDuration? duration,
    DiscoveryFamiliarity? familiarity,
    DiscoveryOrigin? origin,
  }) => DiscoveryContext(
    media: media ?? this.media,
    duration: duration ?? this.duration,
    familiarity: familiarity ?? this.familiarity,
    origin: origin ?? this.origin,
  );
}
