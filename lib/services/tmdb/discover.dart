part of '../tmdb_service.dart';

mixin TmdbDiscoverMixin on TmdbServiceBase, TmdbListsMixin {
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

    final isFamily = await PrefsAppSettings.isFamilyMode();
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
      if (providerId != null) 'with_watch_monetization_types': 'flatrate',
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

    final isFamily = await PrefsAppSettings.isFamilyMode();
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
      if (providerId != null) 'with_watch_monetization_types': 'flatrate',
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

  Future<List<Movie>> discoverByGenres(
    List<int> genreIds, {
    bool isTV = false,
    int page = 1,
    int? maxRuntime,
  }) async {
    if (genreIds.isEmpty) return getPopular(isTV: isTV, page: page);
    final genreStr = genreIds.join('|');
    return isTV
        ? _discoverTv(genreStr: genreStr, page: page)
        : _discoverMovies(
            genreStr: genreStr,
            page: page,
            maxRuntime: maxRuntime,
          );
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
    final isFamily = await PrefsAppSettings.isFamilyMode();
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
    // TMDB `with_original_language` tek ISO kod bekler (genres'teki pipe-OR yok).
    // "Avrupa" gibi `fr|es|de|…` anahtarlarını dil başına fan-out edip birleştir.
    final List<String?> codes;
    if (originalLanguage == null || originalLanguage.isEmpty) {
      codes = const [null];
    } else {
      final parts = originalLanguage
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      codes = parts.isEmpty ? const [null] : parts;
    }

    final perLang = await Future.wait(
      codes.map(
        (lang) => _discoverSingleLanguage(
          genreStr: genreStr,
          maxRuntime: maxRuntime,
          providerId: providerId,
          originalLanguage: lang,
          originCountry: originCountry,
          minRating: minRating,
          decade: decade,
          startDate: startDate,
          endDate: endDate,
          sortBy: sortBy,
          tvStatus: tvStatus,
          includeMovies: includeMovies,
          includeTv: includeTv,
          page: page,
        ),
      ),
    );

    final seen = <String>{};
    final all = <Movie>[];
    for (final list in perLang) {
      for (final m in list) {
        final key = '${m.isTV ? 'tv' : 'movie'}_${m.id}';
        if (seen.add(key)) all.add(m);
      }
    }
    all.sort(_discoverComparator(sortBy));
    return all;
  }

  Future<List<Movie>> _discoverSingleLanguage({
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
    return results.expand((list) => list).toList();
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
}
