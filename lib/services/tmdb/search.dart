part of '../tmdb_service.dart';

mixin TmdbSearchMixin on TmdbServiceBase {
  Future<List<Movie>> searchMulti(String query) async {
    if (query.trim().isEmpty) return [];

    // Yalnızca sorgunun sonundaki bağımsız yılı filtre kabul et. Böylece
    // "2001: A Space Odyssey" gibi adların içindeki sayılar bozulmaz.
    final yearRegex = RegExp(r'(?:^|\s|[\(\[])(1[89]\d{2}|20\d{2})[\)\]]?\s*$');
    final match = yearRegex.firstMatch(query);

    if (match != null) {
      final yearStr = match.group(1)!;
      final year = int.tryParse(yearStr);
      if (year != null) {
        // Strip the year and any surrounding parentheses/brackets
        var cleanQuery = query.replaceAll(yearStr, '').trim();
        cleanQuery = cleanQuery
            .replaceAll(RegExp(r'\(\s*\)|\[\s*\]'), '')
            .trim();
        cleanQuery = cleanQuery
            .replaceAll(RegExp(r'^[\(\[,\-\s]+|[\)\]\s,\-\s]+$'), '')
            .trim();

        if (cleanQuery.isNotEmpty) {
          try {
            final results = await Future.wait([
              _searchMoviesWithYear(cleanQuery, year),
              _searchTvWithYear(cleanQuery, year),
            ]);
            final combined = [...results[0], ...results[1]];
            if (combined.isNotEmpty) {
              combined.sort((a, b) => b.popularity.compareTo(a.popularity));
              return _sanitizeList(combined, isSearch: true);
            }
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
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
    final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
    final response = await _client.get(uri).timeout(_kTmdbTimeout);
    _handleNon200Response(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final results = (data['results'] as List<dynamic>?) ?? [];
    return results
        .cast<Map<String, dynamic>>()
        .map((e) => Movie.fromJson(e, isTV: true))
        .toList();
  }

  Future<List<Movie>> searchMoviesOnly(String query) async {
    if (query.trim().isEmpty) return [];
    final uri = _tmdbUri('/3/search/movie', {
      'api_key': _apiKey,
      'language': _language,
      'query': query.trim(),
      'include_adult': 'false',
    });
    try {
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
      final response = await _client.get(uri).timeout(_kTmdbTimeout);
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
}
