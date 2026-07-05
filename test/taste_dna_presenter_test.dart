import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/taste_dna.dart';
import 'package:ne_izlesem/services/taste_dna_presenter.dart';

TasteDna _dna({
  String archetype = 'dark_chronicler',
  List<int> topGenres = const [27, 53],
  int? blindSpot,
  List<String> themes = const [],
  String era = 'modern',
  double modernShare = 0.75,
  String depth = 'deep_digger',
  String critic = 'tough',
  double harikaShare = 0.12,
  int? shiftFrom,
  int? shiftTo,
  double? accuracy,
  int accuracySample = 0,
}) {
  return TasteDna(
    archetypeKey: archetype,
    topGenres: topGenres,
    blindSpotGenre: blindSpot,
    themes: themes,
    eraKey: era,
    modernShare: modernShare,
    depthKey: depth,
    criticKey: critic,
    harikaShare: harikaShare,
    shiftFromGenre: shiftFrom,
    shiftToGenre: shiftTo,
    accuracy: accuracy,
    accuracySample: accuracySample,
    totalRated: 20,
    generatedAt: 0,
  );
}

void main() {
  // l10n null → Türkçe fallback'ler kullanılır; yüzde TR biçiminde ("%75").

  group('TasteDnaPresenter — arketip', () {
    test('arketip adı ve öz metni fallback', () {
      final p = TasteDnaPresenter(null, _dna(archetype: 'world_builder'));
      expect(p.archetypeName, 'Dünya Kâşifi');
      expect(p.archetypeEmoji, '🌌');
      expect(p.archetypeEssence, contains('evren'));
    });
  });

  group('TasteDnaPresenter — sinyaller', () {
    test('modern çağ sinyali yüzdeyi TR biçiminde gömer', () {
      final p = TasteDnaPresenter(null, _dna(era: 'modern', modernShare: 0.75));
      final era = p.signals.firstWhere((s) => s.icon == 'era');
      expect(era.text, contains('%75'));
    });

    test('sert eleştirmen sinyali Harika oranını gömer', () {
      final p = TasteDnaPresenter(
        null,
        _dna(critic: 'tough', harikaShare: 0.1),
      );
      final critic = p.signals.firstWhere((s) => s.icon == 'critic');
      expect(critic.text, contains('%10'));
    });

    test('kör nokta yoksa sinyal listesinde yok', () {
      final p = TasteDnaPresenter(null, _dna(blindSpot: null));
      expect(p.signals.any((s) => s.icon == 'blind'), isFalse);
    });

    test('kör nokta varsa tür adıyla görünür', () {
      final p = TasteDnaPresenter(null, _dna(blindSpot: 35));
      final blind = p.signals.firstWhere((s) => s.icon == 'blind');
      expect(blind.text, contains('Komedi'));
    });

    test('zevk kayması iki tür adını gömer', () {
      final p = TasteDnaPresenter(null, _dna(shiftFrom: 28, shiftTo: 18));
      final shift = p.signals.firstWhere((s) => s.icon == 'shift');
      expect(shift.text, contains('Aksiyon'));
      expect(shift.text, contains('Dram'));
    });
  });

  group('TasteDnaPresenter — isabet', () {
    test('accuracy null ise metin null', () {
      final p = TasteDnaPresenter(null, _dna(accuracy: null));
      expect(p.accuracyText, isNull);
    });

    test('accuracy varsa yüzde ve örneklem gömülür', () {
      final p = TasteDnaPresenter(
        null,
        _dna(accuracy: 0.78, accuracySample: 20),
      );
      expect(p.accuracyText, contains('%78'));
      expect(p.accuracyText, contains('20'));
    });
  });

  group('TasteDnaPresenter — çipler ve paylaşım', () {
    test('tema çiplerinin baş harfi büyür (TMDB keyword\'leri İngilizce)', () {
      final p = TasteDnaPresenter(null, _dna(themes: ['revenge', 'dystopia']));
      expect(p.themeChips, ['Revenge', 'Dystopia']);
    });

    test('paylaşım metni arketip + link içerir', () {
      final p = TasteDnaPresenter(
        null,
        _dna(archetype: 'dark_chronicler', themes: ['revenge']),
      );
      final text = p.shareText('https://x.example/u/ali');
      expect(text, contains('Karanlık Anlatıcı'));
      expect(text, contains('https://x.example/u/ali'));
      expect(text, contains('#SinemaDNA'));
    });

    test('link yoksa keşif çağrısı düşer', () {
      final p = TasteDnaPresenter(null, _dna());
      final text = p.shareText(null);
      expect(text, contains('keşfet'));
    });
  });
}
