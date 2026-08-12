import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/movie.dart';
import 'package:ne_izlesem/services/localization_service.dart';
import 'package:ne_izlesem/widgets/tonight_pick_card.dart';

Movie _movie({required String reasonType, String? reason}) =>
    Movie(id: 1, title: 'X', overview: '', voteAverage: 7.0)
      ..recoReasonType = reasonType
      ..recoReason = reason;

/// Verilen dilde [movie] için (uzun, kompakt) gerekçe etiketlerini döndürür.
Future<(String?, String?)> _labels(
  WidgetTester tester,
  Movie movie,
  String lang,
) async {
  String? long;
  String? short;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(lang),
      home: Builder(
        builder: (context) {
          long = recoReasonLabel(context, movie);
          short = recoReasonLabel(context, movie, compact: true);
          return const SizedBox();
        },
      ),
    ),
  );
  // Localizations delegate'i asenkron yüklenir; ilk kare çocukları çizmez.
  await tester.pumpAndSettle();
  return (long, short);
}

void main() {
  // Tema gerekçesi bir FİLM ADI değil; tohum şablonuna düşerse kullanıcı
  // "duringcreditsstinger beğendiğin için" okur.
  group('keyword gerekçesi kendi şablonunu kullanır', () {
    testWidgets('TR', (tester) async {
      final (long, short) = await _labels(
        tester,
        _movie(reasonType: 'keyword', reason: 'time travel'),
        'tr',
      );
      expect(long, "'time travel' temasını sevdiğin için");
      expect(short, "'time travel' teması");
    });

    testWidgets('EN', (tester) async {
      final (long, short) = await _labels(
        tester,
        _movie(reasonType: 'keyword', reason: 'time travel'),
        'en',
      );
      expect(long, "Because you like the theme 'time travel'");
      expect(short, "Theme: 'time travel'");
    });
  });

  testWidgets('tohum gerekçesi değişmedi', (tester) async {
    final (long, short) = await _labels(
      tester,
      _movie(reasonType: 'seed', reason: 'Inception'),
      'tr',
    );
    expect(long, 'Inception beğendiğin için');
    expect(short, 'Inception benzeri');
  });

  testWidgets('gerekçesiz keyword adayı rozet metni üretmez', (tester) async {
    final (long, short) = await _labels(
      tester,
      _movie(reasonType: 'keyword'),
      'tr',
    );
    expect(long, isNull);
    expect(short, isNull);
  });
}
