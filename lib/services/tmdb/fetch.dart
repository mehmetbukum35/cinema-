part of '../tmdb_service.dart';

/// Fetch/cache helpers live on [TmdbServiceBase]; this mixin marks the
/// composition slot matching the ApiService split pattern.
mixin TmdbFetchMixin on TmdbServiceBase {}
