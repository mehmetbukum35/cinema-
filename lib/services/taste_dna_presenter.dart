import '../models/taste_dna.dart';
import 'localization_service.dart';
import 'prefs_service.dart';

/// DNA sinyallerini lokalize, gösterilebilir metne çevirir. Ekranı metin
/// kurmaktan arındırır; arketip/sinyal metinleri tek yerde yaşar (web kartı
/// PHP tarafında ayrı render eder — snapshot anahtar taşır, her taraf çevirir).
class TasteDnaPresenter {
  final AppLocalizations? l10n;
  final TasteDna dna;

  TasteDnaPresenter(this.l10n, this.dna);

  String _t(String key, String fallback) => l10n?.get(key) ?? fallback;

  /// Yüzde biçimi dile göre: TR "%75", EN "75%".
  String _pct(double v) {
    final n = (v * 100).round();
    return l10n?.locale.languageCode == 'en' ? '$n%' : '%$n';
  }

  // ── Arketip ──
  String get archetypeName =>
      _t('dna_arch_${dna.archetypeKey}', _archetypeFallback);
  String get archetypeEmoji => _archetypeEmoji[dna.archetypeKey] ?? '🎬';
  String get archetypeEssence =>
      _t('dna_ess_${dna.archetypeKey}', _essenceFallback);

  static const _archetypeEmoji = {
    'dark_chronicler': '🕯️',
    'emotion_seeker': '🎭',
    'world_builder': '🌌',
    'adrenaline_junkie': '⚡',
    'joy_chaser': '✨',
    'truth_seeker': '🔍',
    'eternal_child': '🎈',
    'genre_nomad': '🧭',
  };

  String get _archetypeFallback => switch (dna.archetypeKey) {
    'dark_chronicler' => 'Karanlık Anlatıcı',
    'emotion_seeker' => 'Duygu Avcısı',
    'world_builder' => 'Dünya Kâşifi',
    'adrenaline_junkie' => 'Adrenalin Tutkunu',
    'joy_chaser' => 'Neşe Avcısı',
    'truth_seeker' => 'Gerçeğin Peşinde',
    'eternal_child' => 'Sonsuz Çocuk',
    _ => 'Tür Göçebesi',
  };

  String get _essenceFallback => switch (dna.archetypeKey) {
    'dark_chronicler' => 'Gölgelere, gerilime ve ahlaki griliğe çekiliyorsun.',
    'emotion_seeker' => 'Kalbe dokunan, insanı anlatan hikâyelerin peşindesin.',
    'world_builder' => 'Yeni evrenler, imkânsız dünyalar seni çağırıyor.',
    'adrenaline_junkie' => 'Tempo, aksiyon ve macera senin yakıtın.',
    'joy_chaser' => 'Kahkaha ve hafiflik senin sığınağın.',
    'truth_seeker' => 'Gerçek hikâyeler ve geçmişin dersleri ilgini çekiyor.',
    'eternal_child' => 'İçindeki çocuk hiç büyümedi — ve bu çok iyi.',
    _ => 'Tek bir türe sığmıyorsun; her renkten tadıyorsun.',
  };

  // ── Sinyal cümleleri (yalnızca anlamlı olanlar döner) ──
  List<TasteDnaSignal> get signals {
    final out = <TasteDnaSignal>[];

    // Çağ imzası
    out.add(
      TasteDnaSignal(
        icon: 'era',
        text: switch (dna.eraKey) {
          'modern' => _t(
            'dna_era_modern',
            'Modern çağ çocuğu — beğenilerinin {p}\'i 2015 sonrası.',
          ).replaceFirst('{p}', _pct(dna.modernShare)),
          'classic_soul' => _t(
            'dna_era_classic',
            'Klasik ruh — eski sinemanın büyüsünü kovalıyorsun.',
          ),
          _ => _t(
            'dna_era_traveler',
            'Zaman gezgini — her dönemde kendini evinde hissediyorsun.',
          ),
        },
      ),
    );

    // Derinlik
    out.add(
      TasteDnaSignal(
        icon: 'depth',
        text: switch (dna.depthKey) {
          'deep_digger' => _t(
            'dna_depth_deep',
            'Derin keşif avcısı — kalabalığın atladığı mücevherleri buluyorsun.',
          ),
          'zeitgeist' => _t(
            'dna_depth_zeit',
            'Zeitgeist takipçisi — anın nabzını tutuyorsun.',
          ),
          _ => _t(
            'dna_depth_balanced',
            'Dengeli keşifçi — hem gişeyi hem gizli kalanı seviyorsun.',
          ),
        },
      ),
    );

    // Eleştirmen profili
    out.add(
      TasteDnaSignal(
        icon: 'critic',
        text: switch (dna.criticKey) {
          'tough' => _t(
            'dna_critic_tough',
            'Sert eleştirmen — puanlarının yalnızca {p}\'i "Harika".',
          ).replaceFirst('{p}', _pct(dna.harikaShare)),
          'generous' => _t(
            'dna_critic_generous',
            'Cömert kalp — iyi bir hikâyeye "Harika" demekten çekinmiyorsun.',
          ),
          _ => _t(
            'dna_critic_balanced',
            'Ölçülü eleştirmen — övgün de eleştirin de yerini biliyor.',
          ),
        },
      ),
    );

    // Kör nokta
    if (dna.blindSpotGenre != null) {
      out.add(
        TasteDnaSignal(
          icon: 'blind',
          text: _t(
            'dna_blind',
            'Kör noktan: {g} — sana pek hitap etmiyor.',
          ).replaceFirst('{g}', PrefsService.genreName(dna.blindSpotGenre!)),
        ),
      );
    }

    // Zevk kayması
    if (dna.shiftFromGenre != null && dna.shiftToGenre != null) {
      out.add(
        TasteDnaSignal(
          icon: 'shift',
          text: _t('dna_shift', 'Zevkin {from}\'dan {to}\'a doğru kaydı.')
              .replaceFirst(
                '{from}',
                PrefsService.genreName(dna.shiftFromGenre!),
              )
              .replaceFirst('{to}', PrefsService.genreName(dna.shiftToGenre!)),
        ),
      );
    }

    return out;
  }

  // ── Tema çipleri (baş harf büyütülmüş) ──
  List<String> get themeChips => dna.themes
      .map((t) => t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}')
      .toList();

  // ── Tür çipleri ──
  List<String> get genreChips =>
      dna.topGenres.map(PrefsService.genreName).toList();

  // ── Kanıtlı isabet ──
  String? get accuracyText {
    final acc = dna.accuracy;
    if (acc == null) return null;
    return _t(
          'dna_accuracy',
          'Motor seni {p} isabetle tanıyor — {n} öneri üzerinden.',
        )
        .replaceFirst('{p}', _pct(acc))
        .replaceFirst('{n}', dna.accuracySample.toString());
  }

  // ── Paylaşım metni ──
  String shareText(String? profileUrl) {
    final header = _t(
      'dna_share_header',
      'Sinema DNA\'m: {a}',
    ).replaceFirst('{a}', archetypeName);
    final themesLine = themeChips.isNotEmpty
        ? '${_t('dna_share_themes', 'Temalarım')}: ${themeChips.take(3).join(', ')}'
        : '';
    final cta = profileUrl != null
        ? '${_t('dna_share_cta', 'DNA\'na bak')}: $profileUrl'
        : _t('dna_share_cta_none', 'Sen de Sinema DNA\'nı keşfet!');
    return '$archetypeEmoji $header\n'
        '$archetypeEssence\n'
        '${themesLine.isNotEmpty ? '$themesLine\n' : ''}'
        '\n$cta\n#NeIzlesem #SinemaDNA';
  }
}

/// Ekranda ikon + cümle olarak gösterilen tek sinyal.
class TasteDnaSignal {
  final String icon;
  final String text;
  TasteDnaSignal({required this.icon, required this.text});
}
