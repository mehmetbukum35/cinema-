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

part 'tmdb/lists.dart';
part 'tmdb/search.dart';
part 'tmdb/discover.dart';
part 'tmdb/media_extras.dart';
part 'tmdb/fetch.dart';

const Duration _kTmdbTimeout = Duration(seconds: 12);

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

class TmdbServiceBase {
  static const int _memoryCacheLimit = 200;

  final http.Client _client;
  final String _language;
  final String _region;

  final Map<String, List<int>> _keywordIdsCache = {};
  final Map<String, List<Movie>> _similarCache = {};
  final Map<String, List<Movie>> _recommendationsCache = {};

  TmdbServiceBase({
    http.Client? client,
    String? language,
    String? region,
  }) : _client = client ?? http.Client(),
       _language = language ?? 'tr-TR',
       _region = region ?? 'TR';

  V? _readMemoryCache<V>(Map<String, V> cache, String key) {
    final value = cache.remove(key);
    if (value != null) cache[key] = value;
    return value;
  }

  void _writeMemoryCache<V>(Map<String, V> cache, String key, V value) {
    cache.remove(key);
    cache[key] = value;
    while (cache.length > _memoryCacheLimit) {
      cache.remove(cache.keys.first);
    }
  }

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
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
          final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
          final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
          final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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

  Future<List<Movie>> _sanitizeList(
    List<Movie> list, {
    bool isSearch = false,
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

    // Family Mode: drop explicit-adult titles on endpoints that cannot take
    // certification query params (trending, airing_today, on_the_air, etc.).
    final isFamily = await PrefsService.isFamilyMode();
    if (isFamily) {
      list = list.where((m) => !m.adult).toList();
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
    return _sanitizeList(list, isSearch: isSearch);
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

class TmdbService extends TmdbServiceBase
    with
        TmdbFetchMixin,
        TmdbListsMixin,
        TmdbSearchMixin,
        TmdbDiscoverMixin,
        TmdbMediaExtrasMixin {
  TmdbService({super.client, super.language, super.region});

  @visibleForTesting
  int get similarMemoryCacheSize => _similarCache.length;

  @visibleForTesting
  int get recommendationsMemoryCacheSize => _recommendationsCache.length;

  @visibleForTesting
  int get keywordMemoryCacheSize => _keywordIdsCache.length;

  @visibleForTesting
  bool isSimilarMemoryCached(int id, {bool isTV = false}) =>
      _similarCache.containsKey("${isTV ? 'tv' : 'movie'}_$id");
}
