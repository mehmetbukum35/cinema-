import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import '../models/cast_member.dart';
import '../models/watch_provider.dart';
import '../models/review.dart';
import 'app_config.dart';
import 'prefs_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'db_helper.dart';
import 'package:flutter/foundation.dart';

class TmdbApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic originalError;

  const TmdbApiException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() =>
      'TmdbApiException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

/// Converts a low-level error (socket, timeout, format, TLS, ...) into a
/// short, user-safe description. This must NEVER include the raw error
/// object, since its toString() can contain the full request URI —
/// including the TMDB api_key query parameter. The original error is
/// still preserved separately via TmdbApiException.originalError for
/// developer-side logging.
String _safeErrorMessage(Object error) {
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return 'No internet connection';
  }
  if (s.contains('TimeoutException') || s.contains('timed out')) {
    return 'Request timed out';
  }
  if (s.contains('HandshakeException') || s.contains('CertificateException')) {
    return 'Secure connection failed';
  }
  if (s.contains('FormatException')) {
    return 'Received an invalid response';
  }
  return 'Network error';
}

class TmdbService {
  final http.Client _client;
  final String _language;
  final String _region;

  TmdbService({http.Client? client, String? language, String? region})
    : _client = client ?? http.Client(),
      _language = language ?? 'tr-TR',
      _region = region ?? 'TR';

  Uri _tmdbUri(String path, Map<String, String> params) {
    final clean = Map<String, String>.from(params)..remove('api_key');
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final proxyPath =
        '${base.path}/tmdb${path.startsWith('/') ? path : '/$path'}';
    return base.replace(
      path: proxyPath,
      queryParameters: clean.isEmpty ? null : clean,
    );
  }

  // Geriye dönük uyumluluk: aşağıdaki metotlar hâlâ parametre haritalarına
  // 'api_key': _apiKey ekliyor, ama _tmdbUri bu değeri gönderilmeden önce
  // atıyor (bkz. yukarısı) — artık hiçbir isteğe gerçek bir anahtar
  // eklenmiyor, o tamamen backend proxy'sinin sorumluluğunda.
  String get _apiKey => '';

  static const _kTimeout = Duration(seconds: 12);

  // ─── Popular ────────────────────────────────────────────────────────────────

  Future<List<Movie>> getPopular({bool isTV = false, int page = 1}) {
    final path = isTV ? '/3/tv/popular' : '/3/movie/popular';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
      'page': page.toString(),
    }, isTV: isTV);
  }

  Future<List<Movie>> getTopRated({bool isTV = false}) {
    final path = isTV ? '/3/tv/top_rated' : '/3/movie/top_rated';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: isTV);
  }

  // ─── Similar / Recommendations ───────────────────────────────────────────

  Future<List<Movie>> getSimilar(int id, {bool isTV = false}) {
    final path = isTV ? '/3/tv/$id/similar' : '/3/movie/$id/similar';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: isTV);
  }

  Future<List<Movie>> getRecommendations(int id, {bool isTV = false}) {
    final path = isTV
        ? '/3/tv/$id/recommendations'
        : '/3/movie/$id/recommendations';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: isTV);
  }

  // ─── Search ─────────────────────────────────────────────────────────────────

  Future<List<Movie>> searchMulti(String query) async {
    if (query.trim().isEmpty) return [];

    // Detect 4-digit year (e.g. 1800 - 2099) in query
    final yearRegex = RegExp(r'\b(1[89]\d{2}|20\d{2})\b');
    final match = yearRegex.firstMatch(query);

    if (match != null) {
      final yearStr = match.group(0)!;
      final year = int.tryParse(yearStr);
      if (year != null) {
        // Strip the year and any surrounding parentheses/brackets
        var cleanQuery = query.replaceAll(yearStr, '').trim();
        cleanQuery = cleanQuery.replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '').trim();
        cleanQuery = cleanQuery.replaceAll(RegExp(r'^[\(\[,\-\s]+|[\)\]\s,\-\s]+$'), '').trim();

        if (cleanQuery.isNotEmpty) {
          try {
            final results = await Future.wait([
              _searchMoviesWithYear(cleanQuery, year),
              _searchTvWithYear(cleanQuery, year),
            ]);
            final combined = [...results[0], ...results[1]];
            combined.sort((a, b) => b.popularity.compareTo(a.popularity));
            return _sanitizeList(combined, isSearch: true);
          } catch (e) {
            debugPrint("Parallel year-based search failed, falling back: $e");
          }
        }
      }
    }

    final uri = _tmdbUri('/3/search/multi', {
      'api_key': _apiKey,
      'language': _language,
      'query': query.trim(),
      'include_adult': 'false',
    });
    try {
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];
      final list = results
          .where((e) {
            final t = e['media_type'] as String?;
            return t == 'movie' || t == 'tv';
          })
          .map((e) {
            final isTV = (e['media_type'] as String?) == 'tv';
            return Movie.fromJson(e as Map<String, dynamic>, isTV: isTV);
          })
          .toList();
      list.sort((a, b) => b.popularity.compareTo(a.popularity));
      return _sanitizeList(list, isSearch: true);
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to search: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  Future<List<Movie>> _searchMoviesWithYear(String query, int year) async {
    final uri = _tmdbUri('/3/search/movie', {
      'api_key': _apiKey,
      'language': _language,
      'query': query,
      'include_adult': 'false',
      'primary_release_year': year.toString(),
    });
    final response = await _client.get(uri).timeout(_kTimeout);
    _handleNon200Response(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? [];
    return results
        .cast<Map<String, dynamic>>()
        .map((e) => Movie.fromJson(e, isTV: false))
        .toList();
  }

  Future<List<Movie>> _searchTvWithYear(String query, int year) async {
    final uri = _tmdbUri('/3/search/tv', {
      'api_key': _apiKey,
      'language': _language,
      'query': query,
      'include_adult': 'false',
      'first_air_date_year': year.toString(),
    });
    final response = await _client.get(uri).timeout(_kTimeout);
    _handleNon200Response(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? [];
    return results
        .cast<Map<String, dynamic>>()
        .map((e) => Movie.fromJson(e, isTV: true))
        .toList();
  }

  // ─── Dedicated search (movie-only / tv-only) ────────────────────────────────

  Future<List<Movie>> searchMoviesOnly(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = _tmdbUri('/3/search/movie', {
      'api_key': _apiKey,
      'language': _language,
      'query': query.trim(),
      'include_adult': 'false',
    });
    try {
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];
      final list = results
          .cast<Map<String, dynamic>>()
          .map((e) => Movie.fromJson(e, isTV: false))
          .toList();
      list.sort((a, b) => b.popularity.compareTo(a.popularity));
      final sanitized = await _sanitizeList(list, isSearch: true);
      return sanitized.take(10).toList();
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to search movies: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  Future<List<Movie>> searchTvOnly(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = _tmdbUri('/3/search/tv', {
      'api_key': _apiKey,
      'language': _language,
      'query': query.trim(),
      'include_adult': 'false',
    });
    try {
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];
      final list = results
          .cast<Map<String, dynamic>>()
          .map((e) => Movie.fromJson(e, isTV: true))
          .toList();
      list.sort((a, b) => b.popularity.compareTo(a.popularity));
      final sanitized = await _sanitizeList(list, isSearch: true);
      return sanitized.take(10).toList();
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to search TV shows: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  // ─── Discover ───────────────────────────────────────────────────────────────

  Future<List<Movie>> discoverByGenres(
    List<int> genreIds, {
    bool isTV = false,
    int page = 1,
  }) async {
    if (genreIds.isEmpty) return getPopular(isTV: isTV, page: page);
    final genreStr = genreIds.join('|');
    return isTV
        ? _discoverTv(genreStr: genreStr, page: page)
        : _discoverMovies(genreStr: genreStr, page: page);
  }

  /// Genre-based match: AND logic, min 200 votes, sorted by popularity.
  /// Gives well-known content that shares the same genre combination.
  Future<List<Movie>> discoverForMatch(
    List<int> genreIds, {
    bool isTV = false,
  }) async {
    if (genreIds.isEmpty) return getPopular(isTV: isTV);

    // Map movie genre IDs → TV genre IDs when needed
    final mapped = isTV
        ? genreIds.map(
            (id) => switch (id) {
              28 => 10759,
              878 => 10765,
              10751 => 10762,
              _ => id,
            },
          )
        : genreIds;

    // Use top 2 genres with AND (comma) for tight matching
    final genreStr = mapped.take(2).join(',');
    final path = isTV ? '/3/discover/tv' : '/3/discover/movie';
    final isFamily = await PrefsService.isFamilyMode();
    final params = {
      'api_key': _apiKey,
      'language': _language,
      'sort_by': 'popularity.desc',
      'include_adult': 'false',
      'vote_count.gte': '200',
      'watch_region': _region,
      'with_genres': genreStr,
      if (!genreStr.contains('16')) 'without_genres': '16',
      if (isFamily) 'certification_country': 'US',
      if (isFamily) 'certification.lte': isTV ? 'TV-14' : 'PG-13',
    };
    return _fetchList(path, params, isTV: isTV);
  }

  Future<List<Movie>> discover({
    String? genreStr,
    int? maxRuntime,
    int? providerId,
    String? originalLanguage,
    String? originCountry,
    double? minRating,
    String? decade,
    String? startDate,
    String? endDate,
    String sortBy = 'popularity.desc',
    String? tvStatus,
    bool includeMovies = true,
    bool includeTv = true,
    int page = 1,
  }) async {
    final futures = <Future<List<Movie>>>[];

    if (includeMovies) {
      futures.add(
        _discoverMovies(
          genreStr: genreStr,
          maxRuntime: maxRuntime,
          providerId: providerId,
          originalLanguage: originalLanguage,
          originCountry: originCountry,
          minRating: minRating,
          decade: decade,
          startDate: startDate,
          endDate: endDate,
          sortBy: sortBy,
          page: page,
        ),
      );
    }

    if (includeTv) {
      futures.add(
        _discoverTv(
          genreStr: genreStr,
          providerId: providerId,
          originalLanguage: originalLanguage,
          originCountry: originCountry,
          minRating: minRating,
          decade: decade,
          startDate: startDate,
          endDate: endDate,
          sortBy: sortBy.replaceAll('primary_release_date', 'first_air_date'),
          tvStatus: tvStatus,
          page: page,
        ),
      );
    }

    final results = await Future.wait(futures);
    final all = results.expand((list) => list).toList();
    // Film ve dizi tek listede birleştiğinde, kullanıcının seçtiği sıralamayı
    // koru (önceden her zaman puana göre sıralanıyordu — bu seçimi eziyordu).
    all.sort(_discoverComparator(sortBy));
    return all;
  }

  /// Birleştirilmiş film+dizi listesini, kullanıcının seçtiği [sortBy] kriterine
  /// göre yerelde sıralar. TMDB her endpoint'i zaten sunucuda sıralıyor; bu
  /// yalnızca iki listeyi tek sıraya indirir.
  int Function(Movie, Movie) _discoverComparator(String sortBy) {
    int byDate(Movie a, Movie b, {required bool asc}) {
      final da = a.releaseDate ?? '';
      final db = b.releaseDate ?? '';
      // Tarihsiz öğeler yöne bakılmaksızın en sona düşer.
      if (da.isEmpty && db.isEmpty) return 0;
      if (da.isEmpty) return 1;
      if (db.isEmpty) return -1;
      return asc ? da.compareTo(db) : db.compareTo(da);
    }

    return switch (sortBy) {
      'vote_average.desc' => (a, b) => b.voteAverage.compareTo(a.voteAverage),
      'primary_release_date.desc' => (a, b) => byDate(a, b, asc: false),
      'primary_release_date.asc' => (a, b) => byDate(a, b, asc: true),
      _ => (a, b) => b.popularity.compareTo(a.popularity), // popularity.desc
    };
  }

  // ─── Trailers ────────────────────────────────────────────────────────────────

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
        final results =
            (((trJson as Map<String, dynamic>)['results'] as List<dynamic>?) ??
                    [])
                .cast<Map<String, dynamic>>();
        final key = pickKey(results);
        if (key != null) return key;
      }
      // Fallback: English (only if primary language is not English)
      if (_language == 'en-US' || _language == 'en') return null;
      final enJson = await _fetchRawWithCache(
        path: path,
        params: {'api_key': _apiKey, 'language': 'en-US'},
      );
      if (enJson != null) {
        final results =
            (((enJson as Map<String, dynamic>)['results'] as List<dynamic>?) ??
                    [])
                .cast<Map<String, dynamic>>();
        return pickKey(results);
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

  // ─── Watch providers ─────────────────────────────────────────────────────────

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
    final tr =
        ((json['results'] as Map<String, dynamic>?)?['TR'])
            as Map<String, dynamic>?;
    final flatrate = tr?['flatrate'] as List<dynamic>? ?? [];
    final rent = tr?['rent'] as List<dynamic>? ?? [];
    final buy = tr?['buy'] as List<dynamic>? ?? [];
    final seen = <int>{};
    return [...flatrate, ...rent, ...buy]
        .cast<Map<String, dynamic>>()
        .where((p) => seen.add(p['provider_id'] as int))
        .map(WatchProvider.fromJson)
        .toList();
  }

  // ─── Credits ─────────────────────────────────────────────────────────────────

  Future<List<CastMember>> getCredits(int id, {bool isTV = false}) async {
    // TV uses aggregate_credits (roles array); movies use credits (character field)
    final path = isTV ? '/3/tv/$id/aggregate_credits' : '/3/movie/$id/credits';
    final json = await _fetchRawWithCache(
      path: path,
      params: {'api_key': _apiKey, 'language': _language},
    );
    if (json == null) return [];
    final cast = (json['cast'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return cast.take(15).map(CastMember.fromJson).toList();
  }

  // ─── Trending ────────────────────────────────────────────────────────────────

  Future<List<Movie>> getTrending() {
    return _fetchListMixed('/3/trending/all/week', {
      'api_key': _apiKey,
      'language': _language,
    });
  }

  Future<List<Movie>> getTrendingPaged({required bool isTV, int page = 1}) {
    final path = isTV ? '/3/trending/tv/week' : '/3/trending/movie/week';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'page': page.toString(),
    }, isTV: isTV);
  }

  // ─── Upcoming movies ─────────────────────────────────────────────────────────

  Future<List<Movie>> getUpcoming() {
    return _fetchList('/3/movie/upcoming', {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: false);
  }

  // ─── Person filmography ──────────────────────────────────────────────────────

  Future<List<Movie>> getPersonMovies(int personId) async {
    final uri = _tmdbUri('/3/person/$personId/combined_credits', {
      'api_key': _apiKey,
      'language': _language,
    });
    try {
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final cast = (data['cast'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final seen = <int>{};
      final movies =
          cast
              .where(
                (e) =>
                    e['poster_path'] != null &&
                    (e['vote_count'] as int? ?? 0) > 50 &&
                    seen.add(e['id'] as int),
              )
              .map((e) {
                final isTV = (e['media_type'] as String?) == 'tv';
                return Movie.fromJson(e, isTV: isTV);
              })
              .toList()
            ..sort((a, b) => b.voteAverage.compareTo(a.voteAverage));
      return _sanitizeList(movies.take(20).toList());
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to get person movies: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  // ─── Now playing / Airing ────────────────────────────────────────────────────

  Future<List<Movie>> getNowPlaying() {
    return _fetchList('/3/movie/now_playing', {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: false);
  }

  Future<List<Movie>> getAiringToday() {
    return _fetchList('/3/tv/airing_today', {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: true);
  }

  Future<List<Movie>> getOnTheAir() {
    return _fetchList('/3/tv/on_the_air', {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: true);
  }

  // ─── Full details (runtime, tagline, budget, seasons…) ───────────────────────

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

  // ─── Reviews ─────────────────────────────────────────────────────────────────

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

  // ─── Keywords ────────────────────────────────────────────────────────────────

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
        .cast<Map<String, dynamic>>()
        .map((k) => k['name'] as String)
        .take(10)
        .toList();
  }

  /// Kosinüs benzerliği için anahtar kelime ID'leri (isim değil — dil bağımsız,
  /// stabil eşleştirme). getKeywords ile AYNI cache girdisini kullanır; ekstra
  /// ağ isteği yapmaz.
  Future<List<int>> getKeywordIds(int id, {bool isTV = false}) async {
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
        .cast<Map<String, dynamic>>()
        .map((k) => k['id'] as int)
        .take(15)
        .toList();
  }

  // ─── Person details (bio, birthday) ──────────────────────────────────────────

  Future<Map<String, dynamic>?> getPersonDetails(int personId) async {
    final json = await _fetchRawWithCache(
      path: '/3/person/$personId',
      params: {'api_key': _apiKey, 'language': _language},
    );
    return json as Map<String, dynamic>?;
  }

  // ─── Collection (film serisi) ────────────────────────────────────────────────

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

  // ─── Private helpers ────────────────────────────────────────────────────────

  int _getTtlForPath(String path) {
    if (path.contains('/trending') || path.contains('/discover')) {
      return 10800000; // 3 Hours
    }
    if (path.contains('/popular')) {
      return 43200000; // 12 Hours
    }
    if (path.contains('/genre/')) {
      return 2592000000; // 30 Days (Static genres)
    }
    if (path.contains('/watch/providers')) {
      return 86400000; // 1 Day / 24 Hours (Streaming availability is highly volatile)
    }
    return 604800000; // Default: 7 Days (details, cast, reviews)
  }

  /// Cache anahtarı sürümü. Cevap şekli veya sunucu davranışı değiştiğinde
  /// (örn. proxy'nin noktalı parametre düzeltmesi) bu sürümü artırmak, eski
  /// nesil cache'i tek hamlede geçersiz kılar: yeni anahtarlar eskileri
  /// okumaz, eski satırlar da [_ensureLegacyCachePurged] ile silinir.
  static const _kCacheVersion = 'v2';
  static bool _legacyCachePurged = false;

  String _cacheKey(String path, Map<String, String> params) =>
      '$_kCacheVersion:$path:'
      '${params.entries.map((e) => "${e.key}=${e.value}").join("&")}'
      ':locale=$_language';

  Future<void> _ensureLegacyCachePurged() async {
    if (_legacyCachePurged) return;
    _legacyCachePurged = true;
    try {
      await DatabaseHelper().deleteTmdbCacheNotPrefixed('$_kCacheVersion:');
    } catch (e) {
      debugPrint('Legacy TMDB cache purge failed: $e');
    }
  }

  Future<dynamic> _fetchRawWithCache({
    required String path,
    required Map<String, String> params,
    bool isCacheable = true,
  }) async {
    await _ensureLegacyCachePurged();
    final cacheKey = _cacheKey(path, params);

    if (isCacheable) {
      try {
        final cacheRecord = await DatabaseHelper().getTmdbCache(cacheKey);
        if (cacheRecord != null) {
          final payload = cacheRecord['payload'] as String;
          final fetchedAt = cacheRecord['fetched_at'] as int;
          final parsedJson = jsonDecode(payload);

          final ttl = _getTtlForPath(path);
          final isStale =
              DateTime.now().millisecondsSinceEpoch - fetchedAt > ttl;

          if (isStale) {
            _performBackgroundRawReload(path, params, cacheKey);
          }
          return parsedJson;
        }
      } catch (e) {
        debugPrint('Cache read error: $e');
      }
    }

    try {
      final uri = _tmdbUri(path, params);
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final parsedJson = jsonDecode(response.body);

      if (isCacheable) {
        await DatabaseHelper().saveTmdbCache(
          cacheKey,
          response.body,
          _language,
        );
      }
      return parsedJson;
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to fetch raw data: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }
  }

  void _performBackgroundRawReload(
    String path,
    Map<String, String> params,
    String cacheKey,
  ) {
    unawaited(
      Future(() async {
        try {
          final uri = _tmdbUri(path, params);
          final response = await _client.get(uri).timeout(_kTimeout);
          if (response.statusCode == 200) {
            await DatabaseHelper().saveTmdbCache(
              cacheKey,
              response.body,
              _language,
            );
          }
        } catch (e) {
          debugPrint('Background raw SWR reload failed for key $cacheKey: $e');
        }
      }),
    );
  }

  void _performBackgroundReload(
    String path,
    Map<String, String> params,
    bool isTV,
    String cacheKey,
  ) {
    unawaited(
      Future(() async {
        try {
          final uri = _tmdbUri(path, params);
          final response = await _client.get(uri).timeout(_kTimeout);
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final results = (data['results'] as List<dynamic>?) ?? [];
            final rawResults = results.cast<Map<String, dynamic>>();
            await DatabaseHelper().saveTmdbCache(
              cacheKey,
              jsonEncode(rawResults),
              _language,
            );
          }
        } catch (e) {
          debugPrint('Background SWR reload failed for key $cacheKey: $e');
        }
      }),
    );
  }

  void _performBackgroundReloadMixed(
    String path,
    Map<String, String> params,
    String cacheKey,
  ) {
    unawaited(
      Future(() async {
        try {
          final uri = _tmdbUri(path, params);
          final response = await _client.get(uri).timeout(_kTimeout);
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final results = ((data['results'] as List<dynamic>?) ?? [])
                .cast<Map<String, dynamic>>();
            final cacheableData = results.where((e) {
              final t = e['media_type'] as String?;
              return t == 'movie' || t == 'tv';
            }).toList();
            await DatabaseHelper().saveTmdbCache(
              cacheKey,
              jsonEncode(cacheableData),
              _language,
            );
          }
        } catch (e) {
          debugPrint('Background SWR reload failed for key $cacheKey: $e');
        }
      }),
    );
  }

  Future<List<Movie>> _fetchListMixed(
    String path,
    Map<String, String> params,
  ) async {
    final isCacheable =
        !path.contains('/search/') && !path.contains('/social/');

    await _ensureLegacyCachePurged();
    final cacheKey = _cacheKey(path, params);

    if (isCacheable) {
      try {
        final cacheRecord = await DatabaseHelper().getTmdbCache(cacheKey);
        if (cacheRecord != null) {
          final payload = cacheRecord['payload'] as String;
          final fetchedAt = cacheRecord['fetched_at'] as int;
          final dynamic listData = jsonDecode(payload);
          final cachedList = (listData as List<dynamic>).map((e) {
            final isTV = (e['media_type'] as String?) == 'tv';
            return Movie.fromJson(e as Map<String, dynamic>, isTV: isTV);
          }).toList();

          final ttl = _getTtlForPath(path);
          final isStale =
              DateTime.now().millisecondsSinceEpoch - fetchedAt > ttl;

          if (isStale) {
            _performBackgroundReloadMixed(path, params, cacheKey);
          }
          return _sanitizeList(cachedList);
        }
      } catch (e) {
        debugPrint('Cache read error: $e');
      }
    }

    List<Movie> list;
    try {
      final uri = _tmdbUri(path, params);
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = ((data['results'] as List<dynamic>?) ?? [])
          .cast<Map<String, dynamic>>();
      list = results
          .where((e) {
            final t = e['media_type'] as String?;
            return t == 'movie' || t == 'tv';
          })
          .map((e) {
            final isTV = (e['media_type'] as String?) == 'tv';
            return Movie.fromJson(e, isTV: isTV);
          })
          .toList();

      if (isCacheable) {
        final cacheableData = results.where((e) {
          final t = e['media_type'] as String?;
          return t == 'movie' || t == 'tv';
        }).toList();
        await DatabaseHelper().saveTmdbCache(
          cacheKey,
          jsonEncode(cacheableData),
          _language,
        );
      }
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to fetch mixed list: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }

    return _sanitizeList(list);
  }

  Future<List<Movie>> _fetchList(
    String path,
    Map<String, String> params, {
    required bool isTV,
  }) async {
    final isCacheable =
        !path.contains('/search/') && !path.contains('/social/');

    await _ensureLegacyCachePurged();
    final cacheKey = _cacheKey(path, params);

    if (isCacheable) {
      try {
        final cacheRecord = await DatabaseHelper().getTmdbCache(cacheKey);
        if (cacheRecord != null) {
          final payload = cacheRecord['payload'] as String;
          final fetchedAt = cacheRecord['fetched_at'] as int;
          final dynamic listData = jsonDecode(payload);
          final cachedList = (listData as List<dynamic>)
              .map((e) => Movie.fromJson(e as Map<String, dynamic>, isTV: isTV))
              .toList();

          final ttl = _getTtlForPath(path);
          final isStale =
              DateTime.now().millisecondsSinceEpoch - fetchedAt > ttl;

          if (isStale) {
            _performBackgroundReload(path, params, isTV, cacheKey);
          }
          return _sanitizeList(cachedList);
        }
      } catch (e) {
        debugPrint('Cache read error: $e');
      }
    }

    List<Movie> list;
    try {
      final uri = _tmdbUri(path, params);
      final response = await _client.get(uri).timeout(_kTimeout);
      _handleNon200Response(response);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>?) ?? [];
      list = results
          .map((e) => Movie.fromJson(e as Map<String, dynamic>, isTV: isTV))
          .toList();

      if (isCacheable) {
        final rawResults = results.cast<Map<String, dynamic>>();
        await DatabaseHelper().saveTmdbCache(
          cacheKey,
          jsonEncode(rawResults),
          _language,
        );
      }
    } catch (e) {
      if (e is TmdbApiException) rethrow;
      throw TmdbApiException(
        'Failed to fetch list: ${_safeErrorMessage(e)}',
        originalError: e,
      );
    }

    return _sanitizeList(list);
  }

  Future<List<Movie>> _discoverMovies({
    String? genreStr,
    int? maxRuntime,
    int? providerId,
    String? originalLanguage,
    String? originCountry,
    double? minRating,
    String? decade,
    String? startDate,
    String? endDate,
    String sortBy = 'popularity.desc',
    int page = 1,
  }) async {
    startDate ??= _decadeStart(decade);
    endDate ??= _decadeEnd(decade, isMovie: true);

    final isFamily = await PrefsService.isFamilyMode();
    final params = {
      'api_key': _apiKey,
      'language': _language,
      'sort_by': sortBy,
      'include_adult': 'false',
      'vote_count.gte': '100',
      'watch_region': _region,
      'page': page.toString(),
      'with_genres': ?genreStr,
      if (genreStr == null || !genreStr.contains('16')) 'without_genres': '16',
      if (maxRuntime != null) 'with_runtime.lte': maxRuntime.toString(),
      if (providerId != null) 'with_watch_providers': providerId.toString(),
      'with_original_language': ?originalLanguage,
      'with_origin_country': ?originCountry,
      if (minRating != null) 'vote_average.gte': minRating.toString(),
      'primary_release_date.gte': ?startDate,
      'primary_release_date.lte': ?endDate,
      if (isFamily) 'certification_country': 'US',
      if (isFamily) 'certification.lte': 'PG-13',
    };

    return _fetchList('/3/discover/movie', params, isTV: false);
  }

  Future<List<Movie>> _discoverTv({
    String? genreStr,
    int? providerId,
    String? originalLanguage,
    String? originCountry,
    double? minRating,
    String? decade,
    String? startDate,
    String? endDate,
    String sortBy = 'popularity.desc',
    String? tvStatus,
    int page = 1,
  }) async {
    final tvGenreStr = genreStr
        ?.replaceAll('28', '10759')
        .replaceAll('878', '10765')
        .replaceAll('10751', '10762');

    startDate ??= _decadeStart(decade);
    endDate ??= _decadeEnd(decade, isMovie: false);

    final isFamily = await PrefsService.isFamilyMode();
    final params = {
      'api_key': _apiKey,
      'language': _language,
      'sort_by': sortBy,
      'include_adult': 'false',
      'vote_count.gte': '50',
      'watch_region': _region,
      'page': page.toString(),
      'with_genres': ?tvGenreStr,
      if (tvGenreStr == null || !tvGenreStr.contains('16'))
        'without_genres': '16',
      if (providerId != null) 'with_watch_providers': providerId.toString(),
      'with_original_language': ?originalLanguage,
      'with_origin_country': ?originCountry,
      if (minRating != null) 'vote_average.gte': minRating.toString(),
      'first_air_date.gte': ?startDate,
      'first_air_date.lte': ?endDate,
      'with_status': ?tvStatus,
      if (isFamily) 'certification_country': 'US',
      if (isFamily) 'certification.lte': 'TV-14',
    };

    return _fetchList('/3/discover/tv', params, isTV: true);
  }

  String? _decadeStart(String? decade) => switch (decade) {
    '2020' => '2020-01-01',
    '2010' => '2010-01-01',
    '2000' => '2000-01-01',
    '1990' => '1990-01-01',
    _ => null,
  };

  String? _decadeEnd(String? decade, {required bool isMovie}) =>
      switch (decade) {
        '2010' => '2019-12-31',
        '2000' => '2009-12-31',
        '1990' => '1999-12-31',
        'classic' => '1989-12-31',
        _ => null,
      };

  Future<List<Movie>> _sanitizeList(
    List<Movie> list, {
    bool isSearch = false,
    bool forceEnforce = false,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blocked = prefs.getStringList('blocked_movie_ids');
      if (blocked != null && blocked.isNotEmpty) {
        list = list.where((m) {
          final key = "${m.isTV ? 'tv' : 'movie'}_${m.id}";
          return !blocked.contains(key);
        }).toList();
      }
    } catch (e, st) {
      debugPrint(
        "Error loading blocked movies from SharedPreferences: $e\n$st",
      );
    }

    const int kMinVoteCountDefault = 15;
    const int kMinVoteCountSearch = 3;

    final minVote = isSearch ? kMinVoteCountSearch : kMinVoteCountDefault;

    return list.where((m) {
      // 1. Poster zorunlu (poster_path != null)
      if (m.posterPath == null || m.posterPath!.trim().isEmpty) {
        return false;
      }
      // 2. Oy sayısı (vote_count >= minVote)
      if (m.voteCount < minVote) {
        return false;
      }
      return true;
    }).toList();
  }

  @visibleForTesting
  Future<List<Movie>> sanitizeListForTesting(
    List<Movie> list, {
    bool isSearch = false,
  }) {
    return _sanitizeList(list, isSearch: isSearch, forceEnforce: true);
  }

  void _handleNon200Response(http.Response response) {
    if (response.statusCode == 200) return;
    String msg = 'API Request failed with status code ${response.statusCode}';
    try {
      final errBody = jsonDecode(response.body);
      if (errBody is Map && errBody['error'] != null) {
        msg = errBody['error'].toString();
      }
    } catch (e) {
      // response.body geçerli bir JSON değilse (örn. HTML hata sayfası), fallback olarak doğrudan body içeriğini kullanıyoruz.
      if (response.body.isNotEmpty) {
        msg = response.body;
      }
    }
    throw TmdbApiException(msg, statusCode: response.statusCode);
  }
}
