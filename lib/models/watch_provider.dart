class WatchProvider {
  final int providerId;
  final String name;
  final String? logoPath;

  const WatchProvider({
    required this.providerId,
    required this.name,
    this.logoPath,
  });

  factory WatchProvider.fromJson(Map<String, dynamic> json) => WatchProvider(
    providerId: json['provider_id'] as int,
    name: json['provider_name'] as String? ?? '',
    logoPath: json['logo_path'] as String?,
  );

  String get logoUrl =>
      logoPath != null ? 'https://image.tmdb.org/t/p/w92$logoPath' : '';
}
