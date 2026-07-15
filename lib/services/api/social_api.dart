part of '../api_service.dart';

/// Friends, profiles, reviews, and devices backend operations.
mixin SocialApi on ApiClient {
  Future<Map<String, dynamic>> setupProfile(
    String username,
    bool isPublic,
  ) async {
    final response = await _request(
      'POST',
      '/social/profile/setup',
      body: {'username': username, 'is_public': isPublic ? 1 : 0},
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Profil ayarları güncellenemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> registerDevice(String token, {String? platform}) async {
    final response = await _request(
      'POST',
      '/social/device/register',
      body: {'token': token, 'platform': platform},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Cihaz kaydedilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> unregisterDevice(String token) async {
    final response = await _request(
      'POST',
      '/social/device/unregister',
      body: {'token': token},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Cihaz kaydı silinemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> getFriends() async {
    final response = await _request(
      'GET',
      '/social/friends',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaş listesi alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> sendFriendRequest(String searchQuery) async {
    final response = await _request(
      'POST',
      '/social/friends/request',
      body: {'search_query': searchQuery},
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaşlık isteği gönderilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> acceptFriendRequest(int friendId) async {
    final response = await _request(
      'POST',
      '/social/friends/accept',
      body: {'friend_id': friendId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'İstek kabul edilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> rejectFriendRequest(int friendId) async {
    final response = await _request(
      'POST',
      '/social/friends/reject',
      body: {'friend_id': friendId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaşlık silinemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<List<dynamic>> getActivityFeed({int? friendId}) async {
    final path = friendId != null
        ? '/social/friends/activity?friend_id=$friendId'
        : '/social/friends/activity';
    final response = await _request('GET', path, requireAuth: true);
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['activity'] as List<dynamic>;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Aktivite akışı alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<List<dynamic>> getWatchlistIntersection(int friendId) async {
    final response = await _request(
      'GET',
      '/social/match/watchlist-intersection/$friendId',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['watchlist'] as List<dynamic>;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Ortak izleme listesi alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<FriendSignals> getFriendSignals() async {
    final response = await _request(
      'GET',
      '/social/friends/signals',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      // Eski sunucu boş sinyal kümesini `[]` (liste) dönebilir (PHP boş assoc
      // dizi tuzağı); Map değilse boş sayılır.
      final raw = data['signals'];
      return FriendSignals.fromJson(
        raw is Map ? Map<String, dynamic>.from(raw) : const {},
      );
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Arkadaş sinyalleri alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> getTopProfiles() async {
    final response = await _request(
      'GET',
      '/social/profiles/top',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Popüler listeler alınamadı.',
      code: data['code'] as String?,
    );
  }

  Future<int> likeProfile(int ownerId, bool liked) async {
    final response = await _request(
      'POST',
      '/social/profile/like',
      body: {'owner_id': ownerId, 'liked': liked},
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return int.tryParse(data['like_count']?.toString() ?? '') ?? 0;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Beğeni gönderilemedi.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> getTitleReviews(String type, int id) async {
    final response = await _request(
      'GET',
      '/social/title-reviews/$type/$id',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Yorumlar yüklenemedi.',
      code: data['code'] as String?,
    );
  }

  Future<bool> reportReview({
    required int userId,
    required int movieId,
    required bool isTV,
    required String reason,
  }) async {
    final response = await _request(
      'POST',
      '/social/reviews/report',
      body: {
        'user_id': userId,
        'movie_id': movieId,
        'is_tv': isTV ? 1 : 0,
        'reason': reason,
      },
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['auto_hidden'] == true;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Şikayet gönderilemedi.',
      code: data['code'] as String?,
    );
  }

  Future<void> blockUser(int userId) async {
    final response = await _request(
      'POST',
      '/social/users/block',
      body: {'user_id': userId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Kullanıcı engellenemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> unblockUser(int userId) async {
    final response = await _request(
      'POST',
      '/social/users/unblock',
      body: {'user_id': userId},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Engel kaldırılamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<List<dynamic>> getBlockedUsers() async {
    final response = await _request(
      'GET',
      '/social/users/blocked',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['blocked'] as List<dynamic>? ?? [];
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Engellenenler yüklenemedi.',
      code: data['code'] as String?,
    );
  }
}
