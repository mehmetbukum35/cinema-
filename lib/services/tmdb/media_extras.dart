part of '../tmdb_service.dart';

mixin TmdbMediaExtrasMixin on TmdbServiceBase {
  Future<List<Movie>> getSimilar(int id, {bool isTV = false}) async {
    final cacheKey = "${isTV ? 'tv' : 'movie'}_$id";
    final cached = _readMemoryCache(_similarCache, cacheKey);
    if (cached != null) {
      return cached.map((m) => m.clone()).toList();
    }
    final path = isTV ? '/3/tv/$id/similar' : '/3/movie/$id/similar';
    final list = await _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: isTV);
    _writeMemoryCache(_similarCache, cacheKey, list);
    return list.map((m) => m.clone()).toList();
  }

  Future<List<Movie>> getRecommendations(int id, {bool isTV = false}) async {
    final cacheKey = "${isTV ? 'tv' : 'movie'}_$id";
    final cached = _readMemoryCache(_recommendationsCache, cacheKey);
    if (cached != null) {
      return cached.map((m) => m.clone()).toList();
    }
    final path = isTV
        ? '/3/tv/$id/recommendations'
        : '/3/movie/$id/recommendations';
    final list = await _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: isTV);
    _writeMemoryCache(_recommendationsCache, cacheKey, list);
    return list.map((m) => m.clone()).toList();
  }

  Future<String?> getTrailerKey(int id, {bool isTV = false}) async {
    final path = isTV ? '/3/tv/$id/videos' : '/3/movie/$id/videos';

    String? pickKey(List<Map<String, dynamic>> results) {
      final official = results.where(
        (v) =>
            v['site'] == 'YouTube' &&
            (v['type'] == 'Trailer' || v['type'] == 'Teaser') &&
            v['official'] == true,
      );
      final any = results.where((v) => v['site'] == 'YouTube');
      final hit = official.isNotEmpty
          ? official.first
          : any.isNotEmpty
          ? any.first
          : null;
      return hit?['key'] as String?;
    }

    try {
      // Try Turkish first
      final trJson = await _fetchRawWithCache(
        path: path,
        params: {'api_key': _apiKey, 'language': _language},
      );
      if (trJson != null) {
        final rawResults = (trJson is Map) ? trJson['results'] : null;
        final results = rawResults is List
            ? rawResults
                  .whereType<Map<dynamic, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : <Map<String, dynamic>>[];
        final key = pickKey(results);
        if (key != null) return key;
      }
      // Fallback: English (only if primary language is not English)
      if (_language == 'en-US' || _language == 'en') return null;
      final enParams = {'api_key': _apiKey, 'language': 'en-US'};
      final enJson = await _fetchRawWithCache(path: path, params: enParams);
      if (enJson != null) {
        final rawResults = (enJson is Map) ? enJson['results'] : null;
        final results = rawResults is List
            ? rawResults
                  .whereType<Map<dynamic, dynamic>>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : <Map<String, dynamic>>[];
        final key = pickKey(results);
        if (key != null) {
          // TR miss + EN hit: cache EN payload under the primary language key
          // so the next open does not refetch videos twice.
          final trCacheKey = _cacheKey(path, {
            'api_key': _apiKey,
            'language': _language,
          });
          try {
            await DatabaseHelper().saveTmdbCache(
              trCacheKey,
              jsonEncode(enJson),
              _language,
            );
          } catch (e) {
            debugPrint('Trailer EN fallback cache write failed: $e');
          }
          return key;
        }
      }
      return null;
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to get trailer key: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  Future<List<WatchProvider>> getWatchProviders(
    int id, {
    bool isTV = false,
  }) async {
    final path = isTV
        ? '/3/tv/$id/watch/providers'
        : '/3/movie/$id/watch/providers';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey},
    );
    if (json == null) return [];
    final rawResults = json['results'];
    final Map<String, dynamic>? resultsByRegion = rawResults is Map
        ? Map<String, dynamic>.from(rawResults)
        : null;
    final rawRegional = resultsByRegion?[_region.toUpperCase()];
    final regionalData = rawRegional is Map
        ? Map<String, dynamic>.from(rawRegional)
        : null;
    final flatrate = regionalData?['flatrate'] as List<dynamic>? ?? [];
    final rent = regionalData?['rent'] as List<dynamic>? ?? [];
    final buy = regionalData?['buy'] as List<dynamic>? ?? [];
    final seen = <int>{};
    final list = <WatchProvider>[];
    for (final item in [...flatrate, ...rent, ...buy]) {
      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        final pid = int.tryParse(map['provider_id']?.toString() ?? '');
        if (pid != null && seen.add(pid)) {
          list.add(WatchProvider.fromJson(map));
        }
      }
    }
    return list;
  }

  Future<List<CastMember>> getCredits(int id, {bool isTV = false}) async {
    // TV uses aggregate_credits (roles array); movies use credits (character field)
    final path = isTV ? '/3/tv/$id/aggregate_credits' : '/3/movie/$id/credits';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey, 'language': _language},
    );
    if (json == null) return [];
    final rawCast = json['cast'];
    if (rawCast is! List) return [];
    final list = <CastMember>[];
    for (final item in rawCast.take(15)) {
      if (item is Map) {
        final member = CastMember.fromJson(Map<String, dynamic>.from(item));
        if (member.id > 0) list.add(member);
      }
    }
    return list;
  }

  Future<Map<String, dynamic>?> getFullDetails(
    int id, {
    bool isTV = false,
  }) async {
    final path = isTV ? '/3/tv/$id' : '/3/movie/$id';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey, 'language': _language},
    );
    return json as Map<String, dynamic>?;
  }

  Future<List<Review>> getReviews(int id, {bool isTV = false}) async {
    final path = isTV ? '/3/tv/$id/reviews' : '/3/movie/$id/reviews';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey, 'language': _language},
    );
    if (json == null) return [];
    final results = ((json['results'] as List<dynamic>?) ?? [])
        .cast<Map<String, dynamic>>();
    return results
        .where((r) => (r['content'] as String? ?? '').length > 20)
        .take(5)
        .map(Review.fromJson)
        .toList();
  }

  Future<List<String>> getKeywords(int id, {bool isTV = false}) async {
    final path = isTV ? '/3/tv/$id/keywords' : '/3/movie/$id/keywords';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey},
    );
    if (json == null) return [];
    final list =
        (json['keywords'] as List<dynamic>?) ??
        (json['results'] as List<dynamic>?) ??
        [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((k) => k['name'] as String?)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .take(10)
        .toList();
  }

  /// Kosinüs benzerliği için anahtar kelime ID'leri (isim değil — dil bağımsız,
  /// stabil eşleştirme). getKeywords ile AYNI cache girdisini kullanır; ekstra
  /// ağ isteği yapmaz.
  Future<List<int>> getKeywordIds(int id, {bool isTV = false}) async {
    final cacheKey = "${isTV ? 'tv' : 'movie'}_$id";
    final cached = _readMemoryCache(_keywordIdsCache, cacheKey);
    if (cached != null) {
      return cached;
    }
    final path = isTV ? '/3/tv/$id/keywords' : '/3/movie/$id/keywords';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey},
    );
    if (json == null) return [];
    final list =
        (json['keywords'] as List<dynamic>?) ??
        (json['results'] as List<dynamic>?) ??
        [];
    final ids = list
        .whereType<Map<String, dynamic>>()
        .map(
          (k) => k['id'] is num
              ? (k['id'] as num).toInt()
              : int.tryParse(k['id']?.toString() ?? ''),
        )
        .whereType<int>()
        .where((id) => id > 0)
        .take(15)
        .toList();
    _writeMemoryCache(_keywordIdsCache, cacheKey, ids);
    return ids;
  }

  Future<Map<String, dynamic>?> getPersonDetails(int personId) async {
    final json = await _fetchRawWithCache(
      path: '/3/person/$personId',
      params: {'api_key': _apiKey, 'language': _language},
    );
    return json as Map<String, dynamic>?;
  }

  Future<List<Movie>> getPersonMovies(int personId) async {
    final uri = _tmdbUri('/3/person/$personId/combined_credits', {
      'api_key': _apiKey,
      'language': _language,
    });
    try {
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
      _handleNon200Response(response);
      final decoded = jsonDecode(response.body);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final rawCast = data['cast'];
      if (rawCast is! List) return [];
      final seen = <int>{};
      final movies = <Movie>[];
      for (final e in rawCast) {
        if (e is Map) {
          final item = Map<String, dynamic>.from(e);
          final id = int.tryParse(item['id']?.toString() ?? '');
          final voteCount =
              int.tryParse(item['vote_count']?.toString() ?? '') ?? 0;
          if (item['poster_path'] != null &&
              id != null &&
              voteCount > 50 &&
              seen.add(id)) {
            final isTV = item['media_type']?.toString() == 'tv';
            movies.add(Movie.fromJson(item, isTV: isTV));
          }
        }
      }
      movies.sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      return _sanitizeList(movies.take(20).toList());
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to get person movies: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  Future<List<Movie>> getCollection(int collectionId) async {
    final json = await _fetchRawWithCache(
      path: '/3/collection/$collectionId',
      params: {'api_key': _apiKey, 'language': _language},
    );
    if (json == null) return [];
    final parts =
        (json['parts'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .where((e) => e['poster_path'] != null)
            .map((e) => Movie.fromJson(e, isTV: false))
            .toList()
          ..sort((a, b) => a.year.compareTo(b.year));
    return parts;
  }
}
