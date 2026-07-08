
class Friend {
  final int id;
  final String username;
  final String? displayName;
  final String email;

  Friend({
    required this.id,
    required this.username,
    this.displayName,
    required this.email,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      email: json['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'email': email,
  };
}

class ActivityItem {
  final int movieId;
  final bool isTv;
  final int rating;
  final String title;
  final String? posterPath;
  final int updatedAt;
  final String? comment;
  final bool isSpoiler;
  final int friendId;
  final String? friendName;
  final String friendUsername;

  ActivityItem({
    required this.movieId,
    required this.isTv,
    required this.rating,
    required this.title,
    this.posterPath,
    required this.updatedAt,
    this.comment,
    required this.isSpoiler,
    required this.friendId,
    this.friendName,
    required this.friendUsername,
  });

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    return ActivityItem(
      movieId: int.tryParse(json['movie_id']?.toString() ?? '') ?? 0,
      isTv: json['is_tv'] == true || json['is_tv'] == 1 || json['is_tv']?.toString() == '1',
      rating: int.tryParse(json['rating']?.toString() ?? '') ?? 0,
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      updatedAt: int.tryParse(json['updated_at']?.toString() ?? '') ?? 0,
      comment: json['comment'] as String?,
      isSpoiler: json['is_spoiler'] == true || json['is_spoiler'] == 1 || json['is_spoiler']?.toString() == '1',
      friendId: int.tryParse(json['friend_id']?.toString() ?? '') ?? 0,
      friendName: json['friend_name'] as String?,
      friendUsername: json['friend_username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'movie_id': movieId,
    'is_tv': isTv ? 1 : 0,
    'rating': rating,
    'title': title,
    'poster_path': posterPath,
    'updated_at': updatedAt,
    'comment': comment,
    'is_spoiler': isSpoiler ? 1 : 0,
    'friend_id': friendId,
    'friend_name': friendName,
    'friend_username': friendUsername,
  };
}

class RecommendationInboxItem {
  final int id;
  final int movieId;
  final bool isTv;
  final String title;
  final String? posterPath;
  final String? note;
  final bool seen;
  final int createdAt;
  final int fromId;
  final String? fromName;
  final String fromUsername;

  RecommendationInboxItem({
    required this.id,
    required this.movieId,
    required this.isTv,
    required this.title,
    this.posterPath,
    this.note,
    required this.seen,
    required this.createdAt,
    required this.fromId,
    this.fromName,
    required this.fromUsername,
  });

  factory RecommendationInboxItem.fromJson(Map<String, dynamic> json) {
    return RecommendationInboxItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      movieId: int.tryParse(json['movie_id']?.toString() ?? '') ?? 0,
      isTv: json['is_tv'] == true || json['is_tv'] == 1 || json['is_tv']?.toString() == '1',
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      note: json['note'] as String?,
      seen: json['seen'] == true || json['seen'] == 1 || json['seen']?.toString() == '1',
      createdAt: int.tryParse(json['created_at']?.toString() ?? '') ?? 0,
      fromId: int.tryParse(json['from_id']?.toString() ?? '') ?? 0,
      fromName: json['from_name'] as String?,
      fromUsername: json['from_username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'movie_id': movieId,
    'is_tv': isTv ? 1 : 0,
    'title': title,
    'poster_path': posterPath,
    'note': note,
    'seen': seen ? 1 : 0,
    'created_at': createdAt,
    'from_id': fromId,
    'from_name': fromName,
    'from_username': fromUsername,
  };
}
