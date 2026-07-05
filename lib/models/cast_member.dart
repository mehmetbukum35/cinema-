class CastMember {
  final int id;
  final String name;
  final String? profilePath;
  final String character;

  const CastMember({
    required this.id,
    required this.name,
    this.profilePath,
    required this.character,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    // TV aggregate_credits has roles array; movie credits has character directly
    final roles = json['roles'] as List<dynamic>?;
    final character = roles != null && roles.isNotEmpty
        ? (roles.first as Map<String, dynamic>)['character'] as String? ?? ''
        : json['character'] as String? ?? '';
    return CastMember(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      character: character,
    );
  }

  String get profileUrl =>
      profilePath != null ? 'https://image.tmdb.org/t/p/w185$profilePath' : '';
}
