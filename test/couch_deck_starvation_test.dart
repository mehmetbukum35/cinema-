import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ne_izlesem/models/social.dart';
import 'package:ne_izlesem/providers/auth_provider.dart';
import 'package:ne_izlesem/providers/couch_provider.dart';
import 'package:ne_izlesem/services/db_helper.dart';
import 'package:ne_izlesem/services/providers.dart';
import 'package:ne_izlesem/services/tmdb_service.dart';

import 'mocks/couch_api_mock.dart';
import 'mocks/secure_storage_mock.dart';

/// Deste, aday havuzuyla AYNI kaynaktan kuruluyor: trending + popular +
/// tohumlar. getUsedCouchMovies o havuzdan yenmiş anahtarları eleyince, çok
/// oynayan bir çiftte deste sunucunun alt sınırının (COUCH_MIN_DECK = 5)
/// altına düşüp 422 veriyordu — ve yeni oturum açılamadığı için "son 5 oturum"
/// penceresi donuyor, çıkmaz sokak kalıcı hâle geliyordu.
///
/// Buradaki havuz kasten dar (30 tekil) ve puanlama yok, yani tohum adayı da
/// yok: yeni/az puanlayan kullanıcı profili. Riskin gerçekleştiği yer orası.
void main() {
  setupSecureStorageMock();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().hardClearAllData();
  });

  Map<String, dynamic> tmdbItem(int id) => {
    'id': id,
    'title': 'Movie $id',
    'overview': 'o',
    'poster_path': '/p$id.jpg',
    'backdrop_path': '/b$id.jpg',
    'vote_average': 7.0,
    'vote_count': 500,
    'genre_ids': [18],
    'adult': false,
    'media_type': 'movie',
    'release_date': '2020-01-01',
    'popularity': 10.0,
  };

  /// trending: 1..20, popular: 11..30 → 30 tekil aday.
  TmdbService narrowPoolTmdb() {
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.contains('trending')) {
        return http.Response(
          jsonEncode({
            'results': [for (var i = 1; i <= 20; i++) tmdbItem(i)],
          }),
          200,
        );
      }
      if (path.contains('popular')) {
        return http.Response(
          jsonEncode({
            'results': [for (var i = 11; i <= 30; i++) tmdbItem(i)],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'results': []}), 200);
    });
    return TmdbService(client: client);
  }

  Future<List<String>> buildDeck(List<String> usedKeys) async {
    final mockApi = MockCouchApi()
      ..usedCouchMoviesResponse = List<String>.from(usedKeys);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => MockAuthNotifier(AuthState(accessToken: 't', user: {'id': 1})),
        ),
        tmdbServiceProvider.overrideWithValue(narrowPoolTmdb()),
        couchProvider.overrideWith(() => CouchNotifier(api: mockApi)),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(couchProvider.notifier)
        .start(Friend(id: 2, username: 'friend'));
    return [
      for (final d in mockApi.lastDeck ?? const <Map<String, dynamic>>[])
        "${d['is_tv'] == 1 ? 'tv' : 'movie'}_${d['movie_id']}",
    ];
  }

  test('a deck survives when every candidate was already used', () async {
    final everything = [for (var i = 1; i <= 30; i++) 'movie_$i'];

    final deck = await buildDeck(everything);

    expect(
      deck.length,
      greaterThanOrEqualTo(5),
      reason: 'havuzun tamamı kullanılmışsa bile sunucunun alt sınırı tutmalı',
    );
  });

  test('repeated sessions between the same pair never dead-end', () async {
    // Gerçek akış: kabul edilen her destenin anahtarları sunucunun döndürdüğü
    // "kullanılmış" listesine giriyor (son 5 oturum).
    final accepted = <List<String>>[];

    for (var session = 1; session <= 5; session++) {
      final used = accepted.reversed.take(5).expand((d) => d).toList();
      final deck = await buildDeck(used);

      expect(
        deck.length,
        greaterThanOrEqualTo(5),
        reason: '$session. oturumda deste 422 sınırının altına düştü',
      );
      accepted.add(deck);
    }
  });

  test('novelty still wins while the pool can afford it', () async {
    // 10 anahtar yenmiş, 20 taze aday kalmış: gevşetmeye gerek yok.
    final used = [for (var i = 1; i <= 10; i++) 'movie_$i'];

    final deck = await buildDeck(used);

    expect(deck, isNotEmpty);
    expect(
      deck.toSet().intersection(used.toSet()),
      isEmpty,
      reason: 'havuz yeterliyken son oturumların yapımları tekrar edilmemeli',
    );
  });
}
