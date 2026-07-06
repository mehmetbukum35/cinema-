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

  bool get _isEn => l10n?.locale.languageCode == 'en';

  /// Yüzde biçimi dile göre: TR "%75", EN "75%".
  String _pct(double v) {
    final n = (v * 100).round();
    return _isEn ? '$n%' : '%$n';
  }

  /// TR iyelik ekli yüzde: "%75'i", "%12'si", "%10'u", "%40'ı" — ek, sayının
  /// OKUNUŞUNA göre seçilir (yetmiş beş-İ, on iki-Sİ, on-U). EN'de düz "75%".
  String _pctPossessive(double v) {
    final n = (v * 100).round();
    if (_isEn) return '$n%';
    return '%$n${trNumberPossessiveSuffix(n)}';
  }

  /// 0-100 arası sayının Türkçe iyelik eki ("'i/'si/'u/..."). Son söylenen
  /// basamağa göre: birler basamağı doluysa o, değilse onlar; 100 → yüz.
  static String trNumberPossessiveSuffix(int n) {
    const units = {
      1: "'i", 2: "'si", 3: "'ü", 4: "'ü", 5: "'i",
      6: "'sı", 7: "'si", 8: "'i", 9: "'u", //
    };
    const tens = {
      10: "'u", 20: "'si", 30: "'u", 40: "'ı", 50: "'si",
      60: "'ı", 70: "'i", 80: "'i", 90: "'ı", //
    };
    if (n == 0) return "'ı"; // sıfır-ı
    if (n % 100 == 0) return "'ü"; // yüz-ü
    if (n % 10 != 0) return units[n % 10]!;
    return tens[n % 100]!;
  }

  /// TMDB keyword'leri yalnızca İngilizce döner; sık temalar için TR sözlüğü.
  /// PHP karşılığı: backend/src/TasteDnaWebText.php — ikisi senkron tutulmalı.
  static const Map<String, String> themeTr = {
    'revenge': 'intikam',
    'dystopia': 'distopya',
    'time travel': 'zaman yolculuğu',
    'heist': 'soygun',
    'serial killer': 'seri katil',
    'based on true story': 'gerçek hikâye',
    'love': 'aşk',
    'friendship': 'dostluk',
    'betrayal': 'ihanet',
    'survival': 'hayatta kalma',
    'space': 'uzay',
    'alien': 'uzaylı',
    'artificial intelligence': 'yapay zekâ',
    'artificial intelligence (a.i.)': 'yapay zekâ',
    'superhero': 'süper kahraman',
    'magic': 'büyü',
    'vampire': 'vampir',
    'zombie': 'zombi',
    'ghost': 'hayalet',
    'haunted house': 'perili ev',
    'murder': 'cinayet',
    'detective': 'dedektif',
    'police': 'polis',
    'mafia': 'mafya',
    'gangster': 'gangster',
    'prison': 'hapishane',
    'escape': 'kaçış',
    'war': 'savaş',
    'world war ii': '2. Dünya Savaşı',
    'soldier': 'asker',
    'spy': 'casus',
    'espionage': 'casusluk',
    'assassin': 'suikastçı',
    'martial arts': 'dövüş sanatları',
    'road trip': 'yol hikâyesi',
    'coming of age': 'büyüme hikâyesi',
    'high school': 'lise',
    'family': 'aile',
    'father son relationship': 'baba-oğul ilişkisi',
    'mother daughter relationship': 'anne-kız ilişkisi',
    'marriage': 'evlilik',
    'divorce': 'boşanma',
    'wedding': 'düğün',
    'childhood': 'çocukluk',
    'memory': 'hafıza',
    'dream': 'rüya',
    'nightmare': 'kâbus',
    'parallel world': 'paralel evren',
    'post-apocalyptic future': 'kıyamet sonrası',
    'apocalypse': 'kıyamet',
    'virus': 'virüs',
    'pandemic': 'pandemi',
    'monster': 'canavar',
    'dragon': 'ejderha',
    'kingdom': 'krallık',
    'medieval': 'ortaçağ',
    'pirate': 'korsan',
    'treasure': 'hazine',
    'island': 'ada',
    'ocean': 'okyanus',
    'desert': 'çöl',
    'jungle': 'orman',
    'small town': 'kasaba',
    'new york city': 'New York',
    'london, england': 'Londra',
    'paris, france': 'Paris',
    'robbery': 'soygun',
    'kidnapping': 'kaçırılma',
    'conspiracy': 'komplo',
    'corruption': 'yolsuzluk',
    'investigation': 'soruşturma',
    'courtroom': 'mahkeme',
    'lawyer': 'avukat',
    'journalist': 'gazeteci',
    'boxing': 'boks',
    'football (soccer)': 'futbol',
    'basketball': 'basketbol',
    'music': 'müzik',
    'musician': 'müzisyen',
    'dance': 'dans',
    'cooking': 'yemek',
    'chef': 'şef',
    'romance': 'romantizm',
    'forbidden love': 'yasak aşk',
    'love triangle': 'aşk üçgeni',
    'loss': 'kayıp',
    'grief': 'yas',
    'redemption': 'kefaret',
    'identity': 'kimlik',
    'loneliness': 'yalnızlık',
    'obsession': 'takıntı',
    'addiction': 'bağımlılık',
    'mental illness': 'ruh sağlığı',
    'psychopath': 'psikopat',
    'cult': 'tarikat',
    'religion': 'din',
    'mythology': 'mitoloji',
    'fairy tale': 'masal',
    'anime': 'anime',
    'video game': 'video oyunu',
    'hacker': 'hacker',
    'cyberpunk': 'siberpunk',
    'noir': 'kara film',
    'satire': 'hiciv',
    'dark comedy': 'kara mizah',
    'parody': 'parodi',
  };

  // ── Arketip ──
  // ── Arketip ──
  String get archetypeName {
    final primary = _t('dna_arch_${dna.archetypeKey}', _archetypeFallback);
    if (dna.secondaryArchetypeKey != null) {
      final secondary = _t('dna_arch_${dna.secondaryArchetypeKey!}', _secondaryFallback);
      return "$primary + $secondary";
    }
    return primary;
  }
  String get archetypeEmoji => _archetypeEmoji[dna.archetypeKey] ?? '🎬';
  String get archetypeEssence {
    final primary = _t('dna_ess_${dna.archetypeKey}', _essenceFallback);
    if (dna.secondaryArchetypeKey != null) {
      final secondary = _t('dna_ess_sec_${dna.secondaryArchetypeKey!}', _secondaryEssenceFallback(dna.secondaryArchetypeKey!));
      return "$primary $secondary";
    }
    return primary;
  }

  String _secondaryEssenceFallback(String key) => switch (key) {
    'dark_chronicler' => 'Gölgeler, gerilim ve ahlaki grilik de zevkini besliyor.',
    'emotion_seeker' => 'Duygusal derinlik ve insani hikâyeler de seni cezbediyor.',
    'world_builder' => 'Sıra dışı evrenler ve hayal gücü yüksek dünyalar da ilgini çekiyor.',
    'adrenaline_junkie' => 'Tempo, aksiyon ve macera da senin heyecan kaynağın.',
    'joy_chaser' => 'Hafiflik, neşe ve komedi de sığındığın limanlar arasında.',
    'truth_seeker' => 'Gerçek hikâyeler ve yaşanmışlıklar da radarında.',
    'eternal_child' => 'İçindeki büyümeyen çocuk da hikâyelerde yerini buluyor.',
    _ => 'Farklı türlerin renkleri de zevkinde kendini gösteriyor.',
  };

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

  String _fallbackNameFor(String key) => switch (key) {
    'dark_chronicler' => 'Karanlık Anlatıcı',
    'emotion_seeker' => 'Duygu Avcısı',
    'world_builder' => 'Dünya Kâşifi',
    'adrenaline_junkie' => 'Adrenalin Tutkunu',
    'joy_chaser' => 'Neşe Avcısı',
    'truth_seeker' => 'Gerçeğin Peşinde',
    'eternal_child' => 'Sonsuz Çocuk',
    _ => 'Tür Göçebesi',
  };

  String get _archetypeFallback => _fallbackNameFor(dna.archetypeKey);
  String get _secondaryFallback => dna.secondaryArchetypeKey != null ? _fallbackNameFor(dna.secondaryArchetypeKey!) : '';

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
    if (dna.eraKey != null) {
      out.add(
        TasteDnaSignal(
          icon: 'era',
          text: switch (dna.eraKey!) {
            'modern' => _t(
              'dna_era_modern',
              'Modern çağ çocuğu — beğenilerinin {p} 2015 sonrası.',
            ).replaceFirst('{p}', _pctPossessive(dna.modernShare)),
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
    }

    // Derinlik
    if (dna.depthKey != null) {
      out.add(
        TasteDnaSignal(
          icon: 'depth',
          text: switch (dna.depthKey!) {
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
    }

    // Eleştirmen profili
    if (dna.criticKey != null) {
      out.add(
        TasteDnaSignal(
          icon: 'critic',
          text: switch (dna.criticKey!) {
            'tough' => _t(
              'dna_critic_tough',
              'Sert eleştirmen — puanlarının yalnızca {p} "Harika".',
            ).replaceFirst('{p}', _pctPossessive(dna.harikaShare)),
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
    }

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

    // Zevk kayması — tür adlarına Türkçe hâl eki takmak (Komedi'den,
    // Gerilim'e...) hataya açık; ok'lu biçim hem dilbilgisi-güvenli hem net.
    if (dna.shiftFromGenre != null && dna.shiftToGenre != null) {
      out.add(
        TasteDnaSignal(
          icon: 'shift',
          text: _t('dna_shift', 'Zevkinin rotası: {from} → {to}.')
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

  // ── Tema çipleri: TR'de sözlükten çevrilir, EN'de olduğu gibi;
  //    eşleşme yoksa İngilizce kalır (baş harf büyütülmüş).
  List<String> get themeChips => dna.themes.map((t) {
    final raw = _isEn ? t : (themeTr[t.toLowerCase().trim()] ?? t);
    if (raw.isEmpty) return raw;
    // Dart toUpperCase() İngilizce kural uygular ('i'→'I'); Türkçe kelimede
    // baş harf 'i' → 'İ' olmalı (intikam → İntikam).
    final first = !_isEn && raw[0] == 'i' ? 'İ' : raw[0].toUpperCase();
    return '$first${raw.substring(1)}';
  }).toList();

  // ── Tür çipleri ──
  List<String> get genreChips =>
      dna.topGenres.map(PrefsService.genreName).toList();

  // ── Kanıtlı isabet ──
  String? get accuracyText {
    final acc = dna.accuracy;
    if (acc == null) return null;
    return _t(
          'dna_accuracy',
          'Son önerilerdeki uyum oranınız: {p} — {n} öneri üzerinden.',
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
