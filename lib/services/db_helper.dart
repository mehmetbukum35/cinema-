import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/movie.dart';

part 'db/schema.dart';
part 'db/ratings.dart';
part 'db/watchlist.dart';
part 'db/search_history.dart';
part 'db/watched_seasons.dart';
part 'db/favorites.dart';
part 'db/clear.dart';
part 'db/tmdb_cache.dart';

/// Yerel SQLite şemasının güncel sürümü.
///
/// Yeni bir migration eklerken burayı artır ve kolonu hem [DatabaseHelper.onCreate]
/// hem `onUpgrade` hem de `_migratedColumns` tanımına ekle; db_helper_test'teki
/// drift testi üçünün uyumunu doğrular.
const int kDbSchemaVersion = 10;

int _dbInt(Object? v, [int fallback = 0]) =>
    v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? fallback);

double _dbDouble(Object? v, [double fallback = 0]) => v is num
    ? v.toDouble()
    : (double.tryParse(v?.toString() ?? '') ?? fallback);

List<int> _dbIntList(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  return decoded
      .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
      .whereType<int>()
      .where((id) => id > 0)
      .toList();
}

List<String> _dbStringList(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  return decoded
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

class DatabaseHelper
    with
        DbSchemaMixin,
        DbRatingsMixin,
        DbWatchlistMixin,
        DbSearchHistoryMixin,
        DbWatchedSeasonsMixin,
        DbFavoritesMixin,
        DbClearMixin,
        DbTmdbCacheMixin {
  /// saveRating'te alan verilmediğinde mevcut DB değerini korumak için işaretçi.
  static const unset = Object();

  static DatabaseHelper? _instance;
  static Database? _database;
  static bool _useInMemoryMock = false;

  // In-memory mock storage for Web, Desktop (Windows) and unsupported platforms
  static final List<Map<String, dynamic>> _mockWatchlist = [];
  static final List<Map<String, dynamic>> _mockRatings = [];
  static final List<Map<String, dynamic>> _mockSearchHistory = [];
  static final List<Map<String, dynamic>> _mockWatchedSeasons = [];
  static final List<Map<String, dynamic>> _mockFavorites = [];
  static final List<Map<String, dynamic>> _mockTmdbCache = [];

  DatabaseHelper._internal();

  factory DatabaseHelper() {
    _instance ??= DatabaseHelper._internal();
    return _instance!;
  }

  static set databaseInstance(Database? db) {
    _database = db;
  }

  @override
  Future<Database?> get database async {
    if (_database != null) return _database;
    if (_useInMemoryMock) return null;
    if (kIsWeb) {
      _useInMemoryMock = true;
      return null;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _useInMemoryMock = true;
      return null;
    }
    try {
      _database ??= await _initDatabase();
      return _database;
    } catch (e) {
      debugPrint("SQLite initialization failed: $e");
      if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
        _useInMemoryMock = true;
        return null;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobilde sessizce in-memory mock'a düşmek yerine hata fırlatıyoruz.
        rethrow;
      }
      _useInMemoryMock = true;
      return null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final pathString = join(dbPath, 'ne_izlesem.db');

    return await openDatabase(
      pathString,
      version: kDbSchemaVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      onOpen: ensureSchema,
    );
  }
}
