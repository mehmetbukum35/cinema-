import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ne_izlesem/services/localization_service.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';

/// Wraps a widget with MaterialApp, localizations and Riverpod overrides.
Widget pumpApp(
  Widget child, {
  List<Override> overrides = const [],
  Locale locale = const Locale('en', 'US'),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

/// TMDB client that returns empty result lists for browse/discover paths.
TmdbService emptyTmdbService() {
  final client = MockClient((request) async {
    if (request.url.path.contains('/3/')) {
      return http.Response(jsonEncode({'results': []}), 200);
    }
    return http.Response('Not Found', 404);
  });
  return TmdbService(client: client);
}

/// TMDB client with minimal detail responses for MovieDetailSheet smoke tests.
TmdbService detailTmdbService({required String title}) {
  final client = MockClient((request) async {
    final path = request.url.path;
    if (path.contains('/details')) {
      return http.Response(
        jsonEncode({
          'id': 42,
          'title': title,
          'overview': 'Test overview.',
          'vote_average': 7.5,
          'release_date': '2024-01-01',
          'genres': [],
          'runtime': 120,
        }),
        200,
      );
    }
    if (path.contains('/videos')) {
      return http.Response(jsonEncode({'results': []}), 200);
    }
    if (path.contains('/watch/providers') ||
        path.contains('/credits') ||
        path.contains('/similar') ||
        path.contains('/reviews') ||
        path.contains('/keywords')) {
      return http.Response(jsonEncode({'results': []}), 200);
    }
    return http.Response(jsonEncode({'results': []}), 200);
  });
  return TmdbService(client: client);
}
