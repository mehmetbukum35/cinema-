part of '../api_service.dart';

/// Live couch session backend operations.
mixin CouchApi on ApiClient {
  Future<Map<String, dynamic>> createCouchSession({
    required int friendId,
    required List<Map<String, dynamic>> deck,
  }) async {
    final response = await _request(
      'POST',
      '/social/couch/create',
      body: {'friend_id': friendId, 'deck': deck},
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['session'] as Map<String, dynamic>;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Oturum açılamadı.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>?> getActiveCouchSession() async {
    final response = await _request(
      'GET',
      '/social/couch/active',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['session'] as Map<String, dynamic>?;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Oturum sorgulanamadı.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> getCouchSession(int sessionId) async {
    final response = await _request(
      'GET',
      '/social/couch/$sessionId',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['session'] as Map<String, dynamic>;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Oturum yüklenemedi.',
      code: data['code'] as String?,
    );
  }

  Future<Map<String, dynamic>> voteCouchSession({
    required int sessionId,
    required int movieId,
    required bool isTv,
    required bool liked,
  }) async {
    final response = await _request(
      'POST',
      '/social/couch/$sessionId/vote',
      body: {'movie_id': movieId, 'is_tv': isTv ? 1 : 0, 'liked': liked},
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      return data['session'] as Map<String, dynamic>;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Oy gönderilemedi.',
      code: data['code'] as String?,
    );
  }

  Future<void> cancelCouchSession(int sessionId) async {
    final response = await _request(
      'POST',
      '/social/couch/$sessionId/cancel',
      requireAuth: true,
    );
    if (response.statusCode != 200) {
      final data = _decodeJsonMap(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: data['error'] as String? ?? 'Oturum kapatılamadı.',
        code: data['code'] as String?,
      );
    }
  }

  Future<List<String>> getUsedCouchMovies(int friendId) async {
    final response = await _request(
      'GET',
      '/social/couch/used-movies?friend_id=$friendId',
      requireAuth: true,
    );
    final data = _decodeJsonMap(response.body);
    if (response.statusCode == 200) {
      final list = data['used_keys'] as List<dynamic>? ?? const [];
      return list.map((e) => e.toString()).toList();
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: data['error'] as String? ?? 'Kullanılmış yapımlar yüklenemedi.',
      code: data['code'] as String?,
    );
  }
}
