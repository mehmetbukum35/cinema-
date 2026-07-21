part of '../api_service.dart';

/// Taste matching and recommendations backend operations.
mixin RecommendationApi on ApiClient {
  Future<void> publishTasteDna(Map<String, dynamic> snapshot) async {
    final response = await _request(
      'POST',
      '/social/dna',
      body: {'dna': snapshot},
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'DNA yayınlanamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<List<dynamic>> getAllTasteMatches() async {
    final response = await _request(
      'GET',
      '/social/match/taste-all',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['scores'] as List<dynamic>? ?? const [];
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Uyum skorları alınamadı.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> getTasteMatch(int friendId) async {
    final response = await _request(
      'GET',
      '/social/match/taste/$friendId',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Uyum skoru alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> recommendToFriend({
    required int friendId,
    required int movieId,
    required bool isTv,
    required String title,
    String? posterPath,
    String? note,
  }) async {
    final response = await _request(
      'POST',
      '/social/recommend',
      body: {
        'friend_id': friendId,
        'movie_id': movieId,
        'is_tv': isTv ? 1 : 0,
        'title': title,
        'poster_path': ?posterPath,
        if (note != null && note.isNotEmpty) 'note': note,
      },
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Öneri gönderilemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> getRecommendations() async {
    final response = await _request(
      'GET',
      '/social/recommendations',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Öneriler alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<void> markRecommendationsSeen() async {
    final response = await _request(
      'POST',
      '/social/recommendations/seen',
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'İşaretlenemedi.',
        code: data['code'] as String?,
      );
    }
  }

  Future<Map<String, dynamic>> getSentRecommendations() async {
    final response = await _request(
      'GET',
      '/social/recommendations/sent',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Gönderilen öneriler alınamadı.',
        code: data['code'] as String?,
      );
    }
  }

  /// Topluluk "Popüler Top 20" (film ya da dizi). Kimlik doğrulaması gerekmez —
  /// misafirler de görebilir. Sunucu cron ile önhesaplar; bu çağrı hafiftir.
  Future<List<dynamic>> getPopularTitles(bool isTV) async {
    final type = isTV ? 'tv' : 'movie';
    final response = await _request(
      'GET',
      '/titles/popular?type=$type',
      requireAuth: false,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['titles'] as List<dynamic>? ?? const [];
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Popüler liste yüklenemedi.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> getTitleScore(String type, int id) async {
    final response = await _request(
      'GET',
      '/titles/$type/$id/score',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Skor yüklenemedi.',
      code: data['code'] as String?,
    );
  }
}
