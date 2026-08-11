part of '../tmdb_service.dart';

mixin TmdbListsMixin on TmdbServiceBase {
  /// List endpoints (`/popular`, `/top_rated`, …) do **not** accept TMDB
  /// certification filters. When Family Mode is on we route through Discover
  /// (which does) so PG-13 / TV-14 caps apply. Trending / airing lists have no
  /// Discover equivalent with certs — those fall back to client `adult` filter
  /// in [_sanitizeList].
  Future<List<Movie>> getPopular({bool isTV = false, int page = 1}) async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      return _fetchList(isTV ? '/3/discover/tv' : '/3/discover/movie', {
        'api_key': _apiKey,
        'language': _language,
        'region': _region,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'page': page.toString(),
        'certification_country': 'US',
        'certification.lte': isTV ? 'TV-14' : 'PG-13',
      }, isTV: isTV);
    }
    final path = isTV ? '/3/tv/popular' : '/3/movie/popular';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
      'page': page.toString(),
    }, isTV: isTV);
  }

  Future<List<Movie>> getTopRated({bool isTV = false}) async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      return _fetchList(isTV ? '/3/discover/tv' : '/3/discover/movie', {
        'api_key': _apiKey,
        'language': _language,
        'region': _region,
        'sort_by': 'vote_average.desc',
        'include_adult': 'false',
        'vote_count.gte': isTV ? '50' : '100',
        'certification_country': 'US',
        'certification.lte': isTV ? 'TV-14' : 'PG-13',
      }, isTV: isTV);
    }
    final path = isTV ? '/3/tv/top_rated' : '/3/movie/top_rated';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: isTV);
  }

  Future<List<Movie>> getTrending() async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      // Trending API sertifika kabul etmez — family'de cert'li popular karışımı.
      final results = await Future.wait([
        getPopular(isTV: false),
        getPopular(isTV: true),
      ]);
      final mixed = <Movie>[];
      final movies = results[0];
      final shows = results[1];
      final n = movies.length > shows.length ? movies.length : shows.length;
      for (var i = 0; i < n; i++) {
        if (i < movies.length) mixed.add(movies[i]);
        if (i < shows.length) mixed.add(shows[i]);
      }
      return mixed;
    }
    return _fetchListMixed('/3/trending/all/week', {
      'api_key': _apiKey,
      'language': _language,
    });
  }

  Future<List<Movie>> getTrendingPaged({required bool isTV, int page = 1}) async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      return getPopular(isTV: isTV, page: page);
    }
    final path = isTV ? '/3/trending/tv/week' : '/3/trending/movie/week';
    return _fetchList(path, {
      'api_key': _apiKey,
      'language': _language,
      'page': page.toString(),
    }, isTV: isTV);
  }

  Future<List<Movie>> getUpcoming() async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return _fetchList('/3/discover/movie', {
        'api_key': _apiKey,
        'language': _language,
        'region': _region,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'primary_release_date.gte': today,
        'certification_country': 'US',
        'certification.lte': 'PG-13',
      }, isTV: false);
    }
    return _fetchList('/3/movie/upcoming', {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: false);
  }

  Future<List<Movie>> getNowPlaying() async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      // Theatrical now-playing window via Discover so certification applies.
      final now = DateTime.now();
      final gte = now
          .subtract(const Duration(days: 40))
          .toIso8601String()
          .substring(0, 10);
      final lte = now
          .add(const Duration(days: 7))
          .toIso8601String()
          .substring(0, 10);
      return _fetchList('/3/discover/movie', {
        'api_key': _apiKey,
        'language': _language,
        'region': _region,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'primary_release_date.gte': gte,
        'primary_release_date.lte': lte,
        'with_release_type': '2|3',
        'certification_country': 'US',
        'certification.lte': 'PG-13',
      }, isTV: false);
    }
    return _fetchList('/3/movie/now_playing', {
      'api_key': _apiKey,
      'language': _language,
      'region': _region,
    }, isTV: false);
  }

  Future<List<Movie>> getAiringToday() async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      return _fetchList('/3/discover/tv', {
        'api_key': _apiKey,
        'language': _language,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'air_date.gte': today,
        'air_date.lte': today,
        'certification_country': 'US',
        'certification.lte': 'TV-14',
      }, isTV: true);
    }
    return _fetchList('/3/tv/airing_today', {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: true);
  }

  Future<List<Movie>> getOnTheAir() async {
    final isFamily = await PrefsAppSettings.isFamilyMode();
    if (isFamily) {
      final now = DateTime.now();
      final gte = now.toIso8601String().substring(0, 10);
      final lte = now
          .add(const Duration(days: 7))
          .toIso8601String()
          .substring(0, 10);
      return _fetchList('/3/discover/tv', {
        'api_key': _apiKey,
        'language': _language,
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
        'air_date.gte': gte,
        'air_date.lte': lte,
        'certification_country': 'US',
        'certification.lte': 'TV-14',
      }, isTV: true);
    }
    return _fetchList('/3/tv/on_the_air', {
      'api_key': _apiKey,
      'language': _language,
    }, isTV: true);
  }
}
