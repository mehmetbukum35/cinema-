/// Arkadaşların yüksek puan verdiği yapımlar: `movie_123` / `tv_456` → isim listesi.
class FriendSignals {
  final Map<String, List<String>> byTitleKey;

  const FriendSignals([this.byTitleKey = const {}]);

  factory FriendSignals.fromJson(Map<String, dynamic> json) {
    return FriendSignals({
      for (final entry in json.entries)
        if (entry.value is List)
          entry.key: (entry.value as List)
              .map((name) => name.toString())
              .toList(),
    });
  }

  List<String>? friendsFor({required int movieId, required bool isTv}) {
    return byTitleKey['${isTv ? 'tv' : 'movie'}_$movieId'];
  }

  Map<String, List<String>> toRecommendationMap() => byTitleKey;
}

class Friend {
  final int id;
  final String username;
  final String? displayName;

  Friend({required this.id, required this.username, this.displayName});

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
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
      isTv:
          json['is_tv'] == true ||
          json['is_tv'] == 1 ||
          json['is_tv']?.toString() == '1',
      rating: int.tryParse(json['rating']?.toString() ?? '') ?? 0,
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      updatedAt: int.tryParse(json['updated_at']?.toString() ?? '') ?? 0,
      comment: json['comment'] as String?,
      isSpoiler:
          json['is_spoiler'] == true ||
          json['is_spoiler'] == 1 ||
          json['is_spoiler']?.toString() == '1',
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
      isTv:
          json['is_tv'] == true ||
          json['is_tv'] == 1 ||
          json['is_tv']?.toString() == '1',
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      note: json['note'] as String?,
      seen:
          json['seen'] == true ||
          json['seen'] == 1 ||
          json['seen']?.toString() == '1',
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

class SentRecommendationItem {
  final int id;
  final int movieId;
  final bool isTv;
  final String title;
  final String? posterPath;
  final String? note;
  final int createdAt;
  final int toId;
  final String? toName;
  final String toUsername;

  SentRecommendationItem({
    required this.id,
    required this.movieId,
    required this.isTv,
    required this.title,
    this.posterPath,
    this.note,
    required this.createdAt,
    required this.toId,
    this.toName,
    required this.toUsername,
  });

  String get friendLabel =>
      (toName != null && toName!.trim().isNotEmpty) ? toName! : toUsername;

  factory SentRecommendationItem.fromJson(Map<String, dynamic> json) {
    return SentRecommendationItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      movieId: int.tryParse(json['movie_id']?.toString() ?? '') ?? 0,
      isTv:
          json['is_tv'] == true ||
          json['is_tv'] == 1 ||
          json['is_tv']?.toString() == '1',
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      note: json['note'] as String?,
      createdAt: int.tryParse(json['created_at']?.toString() ?? '') ?? 0,
      toId: int.tryParse(json['to_id']?.toString() ?? '') ?? 0,
      toName: json['to_name'] as String?,
      toUsername: json['to_username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'movie_id': movieId,
    'is_tv': isTv ? 1 : 0,
    'title': title,
    'poster_path': posterPath,
    'note': note,
    'created_at': createdAt,
    'to_id': toId,
    'to_name': toName,
    'to_username': toUsername,
  };
}

class ReceivedRecommendationItem {
  final int id;
  final int movieId;
  final bool isTv;
  final String title;
  final String? posterPath;
  final String? note;
  final int createdAt;
  final int fromId;
  final String? fromName;
  final String fromUsername;
  final bool seen;

  ReceivedRecommendationItem({
    required this.id,
    required this.movieId,
    required this.isTv,
    required this.title,
    this.posterPath,
    this.note,
    required this.createdAt,
    required this.fromId,
    this.fromName,
    required this.fromUsername,
    this.seen = false,
  });

  String get friendLabel => (fromName != null && fromName!.trim().isNotEmpty)
      ? fromName!
      : fromUsername;

  factory ReceivedRecommendationItem.fromJson(Map<String, dynamic> json) {
    return ReceivedRecommendationItem(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      movieId: int.tryParse(json['movie_id']?.toString() ?? '') ?? 0,
      isTv:
          json['is_tv'] == true ||
          json['is_tv'] == 1 ||
          json['is_tv']?.toString() == '1',
      title: json['title'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      note: json['note'] as String?,
      createdAt: int.tryParse(json['created_at']?.toString() ?? '') ?? 0,
      fromId: int.tryParse(json['from_id']?.toString() ?? '') ?? 0,
      fromName: json['from_name'] as String?,
      fromUsername: json['from_username'] as String? ?? '',
      seen:
          json['seen'] == true ||
          json['seen'] == 1 ||
          json['seen']?.toString() == '1',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'movie_id': movieId,
    'is_tv': isTv ? 1 : 0,
    'title': title,
    'poster_path': posterPath,
    'note': note,
    'created_at': createdAt,
    'from_id': fromId,
    'from_name': fromName,
    'from_username': fromUsername,
    'seen': seen ? 1 : 0,
  };
}

/// "Popüler Listeler" sıralamasında bir üyenin afiş önizlemesi.
class TopProfilePreview {
  final String? title;
  final String? posterPath;
  final int movieId;
  final bool isTv;

  TopProfilePreview({
    this.title,
    this.posterPath,
    required this.movieId,
    required this.isTv,
  });

  String get posterUrl =>
      posterPath != null ? 'https://image.tmdb.org/t/p/w185$posterPath' : '';

  factory TopProfilePreview.fromJson(Map<String, dynamic> json) {
    return TopProfilePreview(
      title: json['title'] as String?,
      posterPath: json['poster_path'] as String?,
      movieId: int.tryParse(json['movie_id']?.toString() ?? '') ?? 0,
      isTv:
          json['is_tv'] == true ||
          json['is_tv'] == 1 ||
          json['is_tv']?.toString() == '1',
    );
  }
}

/// "Popüler Listeler" sıralamasındaki bir üye (GET /social/profiles/top).
class TopProfile {
  final int id;
  final String username;
  final String? displayName;
  final int likeCount;
  final bool meLiked;
  final bool isMe;
  final int likedTitles;
  final List<TopProfilePreview> previews;

  TopProfile({
    required this.id,
    required this.username,
    this.displayName,
    required this.likeCount,
    required this.meLiked,
    required this.isMe,
    required this.likedTitles,
    this.previews = const [],
  });

  String get shownName =>
      (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!
      : username;

  TopProfile copyWith({int? likeCount, bool? meLiked}) {
    return TopProfile(
      id: id,
      username: username,
      displayName: displayName,
      likeCount: likeCount ?? this.likeCount,
      meLiked: meLiked ?? this.meLiked,
      isMe: isMe,
      likedTitles: likedTitles,
      previews: previews,
    );
  }

  factory TopProfile.fromJson(Map<String, dynamic> json) {
    return TopProfile(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      username: json['username'] as String? ?? '',
      displayName: json['display_name'] as String?,
      likeCount: int.tryParse(json['like_count']?.toString() ?? '') ?? 0,
      meLiked:
          json['me_liked'] == true ||
          json['me_liked'] == 1 ||
          json['me_liked']?.toString() == '1',
      isMe:
          json['is_me'] == true ||
          json['is_me'] == 1 ||
          json['is_me']?.toString() == '1',
      likedTitles: int.tryParse(json['liked_titles']?.toString() ?? '') ?? 0,
      previews:
          (json['previews'] as List<dynamic>?)
              ?.map(
                (x) => TopProfilePreview.fromJson(x as Map<String, dynamic>),
              )
              .toList() ??
          const [],
    );
  }
}
