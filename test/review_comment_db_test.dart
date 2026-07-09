import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/models/movie.dart';

/// Yorum yönetimi (Yorumlarım ekranı + bağımsız yorum silme) için gerçek
/// SQL yolunu test eder: ffi in-memory veritabanı DatabaseHelper'a enjekte
/// edilir; mock listeler devreye girmez.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  final helper = DatabaseHelper();

  Movie movie(int id, String title, {bool isTV = false}) => Movie(
    id: id,
    title: title,
    posterPath: '/p.jpg',
    backdropPath: null,
    overview: 'o',
    voteAverage: 7.0,
    releaseDate: '2020-01-01',
    isTV: isTV,
    genreIds: const [18],
    popularity: 1.0,
  );

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE ratings (
            movie_id INTEGER,
            is_tv INTEGER NOT NULL,
            rating INTEGER NOT NULL,
            genre_ids TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            poster_path TEXT,
            backdrop_path TEXT,
            overview TEXT,
            vote_average REAL,
            release_date TEXT,
            popularity REAL,
            comment TEXT,
            is_spoiler INTEGER NOT NULL DEFAULT 0,
            is_private INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (movie_id, is_tv)
          )
        ''');
      },
    );
    DatabaseHelper.databaseInstance = db;
  });

  tearDown(() async {
    DatabaseHelper.databaseInstance = null;
    await db.close();
  });

  group('Comment management', () {
    test('getCommentedRatings returns only rated titles with comments', () async {
      await helper.saveRating(
        movie: movie(1, 'With Comment'),
        rating: 3,
        comment: 'Harika bir film',
      );
      await helper.saveRating(movie: movie(2, 'No Comment'), rating: 2);
      await helper.saveRating(
        movie: movie(3, 'Blank Comment'),
        rating: 1,
        comment: '   ',
      );
      await helper.saveRating(
        movie: movie(4, 'Deleted', isTV: true),
        rating: 0,
        comment: 'Silinecek',
      );
      await helper.deleteRating(4, true);

      final rows = await helper.getCommentedRatings();
      expect(rows, hasLength(1));
      expect(rows.first['movie_id'], 1);
      expect(rows.first['comment'], 'Harika bir film');
    });

    test('getCommentedRatings sorts newest first', () async {
      await helper.saveRating(
        movie: movie(10, 'Old'),
        rating: 2,
        comment: 'eski',
      );
      await db.update(
        'ratings',
        {'updated_at': 1000},
        where: 'movie_id = 10',
      );
      await helper.saveRating(
        movie: movie(11, 'New'),
        rating: 2,
        comment: 'yeni',
      );

      final rows = await helper.getCommentedRatings();
      expect(rows, hasLength(2));
      expect(rows.first['movie_id'], 11);
    });

    test('deleteComment clears comment but keeps rating, bumps updated_at', () async {
      await helper.saveRating(
        movie: movie(20, 'Keep Rating'),
        rating: 3,
        comment: 'yorum',
        isSpoiler: 1,
      );
      final before = await helper.getRating(20, false);
      final beforeUpdatedAt = before!['updated_at'] as int;

      await Future<void>.delayed(const Duration(milliseconds: 2));
      await helper.deleteComment(20, false);

      final after = await helper.getRating(20, false);
      expect(after, isNotNull);
      expect(after!['rating'], 3);
      expect(after['comment'], isNull);
      expect(after['is_spoiler'], 0);
      expect(after['deleted'], 0);
      // Sync'in değişikliği yakalaması için updated_at ilerlemiş olmalı.
      expect(after['updated_at'] as int, greaterThan(beforeUpdatedAt));

      final rows = await helper.getCommentedRatings();
      expect(rows, isEmpty);
    });

    test('saveRating without comment preserves existing comment on rating change', () async {
      await helper.saveRating(
        movie: movie(30, 'Swipe Test'),
        rating: 3,
        comment: 'Önce yorum yazdım',
        isSpoiler: 1,
        isPrivate: 1,
      );

      // Swipe akışı yalnızca puan gönderir — yorum alanları unset kalır.
      await helper.saveRating(movie: movie(30, 'Swipe Test'), rating: 2);

      final row = await helper.getRating(30, false);
      expect(row, isNotNull);
      expect(row!['rating'], 2);
      expect(row['comment'], 'Önce yorum yazdım');
      expect(row['is_spoiler'], 1);
      expect(row['is_private'], 1);
    });
  });
}
