<?php
declare(strict_types=1);

// Sinema DNA snapshot'ını (cihazdan gelen anahtarlar) public web profili için
// gösterim metnine çevirir. Algoritma cihazda çalışır; burada yalnızca
// snapshot → metin eşlemesi vardır (Dart TasteDnaPresenter'ın PHP karşılığı).
class TasteDnaWebText
{
    private const ARCHETYPES_TR = [
        'dark_chronicler' => ['🕯️', 'Karanlık Anlatıcı', 'Gölgelere, gerilime ve ahlaki griliğe çekiliyor.'],
        'emotion_seeker' => ['🎭', 'Duygu Avcısı', 'Kalbe dokunan, insanı anlatan hikâyelerin peşinde.'],
        'world_builder' => ['🌌', 'Dünya Kâşifi', 'Yeni evrenler, imkânsız dünyalar onu çağırıyor.'],
        'adrenaline_junkie' => ['⚡', 'Adrenalin Tutkunu', 'Tempo, aksiyon ve macera onun yakıtı.'],
        'joy_chaser' => ['✨', 'Neşe Avcısı', 'Kahkaha ve hafiflik onun sığınağı.'],
        'truth_seeker' => ['🔍', 'Gerçeğin Peşinde', 'Gerçek hikâyeler ve geçmişin dersleri ilgisini çekiyor.'],
        'eternal_child' => ['🎈', 'Sonsuz Çocuk', 'İçindeki çocuk hiç büyümedi — ve bu çok iyi.'],
        'genre_nomad' => ['🧭', 'Tür Göçebesi', 'Tek bir türe sığmıyor; her renkten tadıyor.'],
    ];

    private const ARCHETYPES_EN = [
        'dark_chronicler' => ['🕯️', 'The Dark Chronicler', 'You are drawn to shadows, tension and moral grey.'],
        'emotion_seeker' => ['🎭', 'The Emotion Seeker', 'You chase stories that touch the heart and reveal people.'],
        'world_builder' => ['🌌', 'The World Explorer', 'New universes and impossible worlds call to you.'],
        'adrenaline_junkie' => ['⚡', 'The Adrenaline Seeker', 'Pace, action and adventure are your fuel.'],
        'joy_chaser' => ['✨', 'The Joy Chaser', 'Laughter and lightness are your refuge.'],
        'truth_seeker' => ['🔍', 'The Truth Seeker', 'True stories and the lessons of the past intrigue you.'],
        'eternal_child' => ['🎈', 'The Eternal Child', 'The child in you never grew up — and that rules.'],
        'genre_nomad' => ['🧭', 'The Genre Nomad', "You don't fit one genre; you taste every color."],
    ];

    private const GENRES_TR = [
        28 => 'Aksiyon', 12 => 'Macera', 16 => 'Animasyon', 35 => 'Komedi',
        80 => 'Suç', 99 => 'Belgesel', 18 => 'Dram', 10751 => 'Aile',
        14 => 'Fantastik', 36 => 'Tarih', 27 => 'Korku', 10402 => 'Müzik',
        9648 => 'Gizem', 10749 => 'Romantik', 878 => 'Bilim Kurgu',
        53 => 'Gerilim', 10752 => 'Savaş', 37 => 'Western',
        10759 => 'Aksiyon & Macera', 10762 => 'Çocuk', 10763 => 'Haber',
        10764 => 'Realite', 10765 => 'Bilim Kurgu & Fantastik',
        10766 => 'Pembe Dizi', 10767 => 'Program', 10768 => 'Savaş & Politika',
    ];

    private const GENRES_EN = [
        28 => 'Action', 12 => 'Adventure', 16 => 'Animation', 35 => 'Comedy',
        80 => 'Crime', 99 => 'Documentary', 18 => 'Drama', 10751 => 'Family',
        14 => 'Fantasy', 36 => 'History', 27 => 'Horror', 10402 => 'Music',
        9648 => 'Mystery', 10749 => 'Romance', 878 => 'Science Fiction',
        53 => 'Thriller', 10752 => 'War', 37 => 'Western',
        10759 => 'Action & Adventure', 10762 => 'Kids', 10763 => 'News',
        10764 => 'Reality', 10765 => 'Sci-Fi & Fantasy',
        10766 => 'Soap', 10767 => 'Talk Show', 10768 => 'War & Politics',
    ];

    // TMDB keyword'leri İngilizce döner; sık temalar için TR sözlüğü.
    // Dart karşılığı: lib/services/taste_dna_presenter.dart (themeTr) —
    // ikisi senkron tutulmalı.
    private static ?array $themesTr = null;

    private static function isEn(string $lang): bool
    {
        return $lang === 'en';
    }

    private static function archetypes(string $lang): array
    {
        return self::isEn($lang) ? self::ARCHETYPES_EN : self::ARCHETYPES_TR;
    }

    private static function getThemesTr(): array
    {
        if (self::$themesTr === null) {
            $jsonPath = dirname(__DIR__, 2) . '/assets/lexicon/theme_tr.json';
            if (!is_file($jsonPath)) {
                $jsonPath = __DIR__ . '/theme_tr.json';
            }
            if (is_file($jsonPath)) {
                self::$themesTr = json_decode(file_get_contents($jsonPath), true) ?? [];
            } else {
                self::$themesTr = [];
            }
        }
        return self::$themesTr;
    }

    private static function genreName(int $id, string $lang): string
    {
        $map = self::isEn($lang) ? self::GENRES_EN : self::GENRES_TR;
        return $map[$id] ?? (self::isEn($lang) ? 'Unknown' : 'Bilinmeyen');
    }

    private static function pct(float $v, string $lang): string
    {
        $n = (int) round($v * 100);
        return self::isEn($lang) ? ($n . '%') : ('%' . $n);
    }

    /**
     * TR iyelik ekli yüzde: "%75'i", "%12'si", "%10'u" — ek, sayının OKUNUŞUNA
     * göre seçilir. EN'de düz "75%". Dart karşılığı: TasteDnaPresenter._pctPossessive.
     */
    private static function pctPossessive(float $v, string $lang): string
    {
        $n = (int) round($v * 100);
        if (self::isEn($lang)) {
            return $n . '%';
        }
        $units = [1 => "'i", 2 => "'si", 3 => "'ü", 4 => "'ü", 5 => "'i",
                  6 => "'sı", 7 => "'si", 8 => "'i", 9 => "'u"];
        $tens = [10 => "'u", 20 => "'si", 30 => "'u", 40 => "'ı", 50 => "'si",
                 60 => "'ı", 70 => "'i", 80 => "'i", 90 => "'ı"];
        if ($n === 0) {
            $suffix = "'ı";
        } elseif ($n % 100 === 0) {
            $suffix = "'ü";
        } elseif ($n % 10 !== 0) {
            $suffix = $units[$n % 10];
        } else {
            $suffix = $tens[$n % 100];
        }
        return '%' . $n . $suffix;
    }

    /**
     * Snapshot'ı gösterim dizisine çevirir. DNA hazır değilse (yetersiz veri)
     * null döner. Dönen tüm metinler ham (template htmlspecialchars uygular).
     */
    public static function build(?array $dna, string $lang = 'tr'): ?array
    {
        if (!is_array($dna)) {
            return null;
        }
        $total = (int) ($dna['total_rated'] ?? 0);
        if ($total < 5) {
            return null;
        }

        $en = self::isEn($lang);
        $archetypes = self::archetypes($lang);

        $archKey = (string) ($dna['archetype'] ?? 'genre_nomad');
        $arch = $archetypes[$archKey] ?? $archetypes['genre_nomad'];
        $archetypeName = $arch[1];
        $essence = $arch[2];

        if (!empty($dna['secondary_archetype'])) {
            $secKey = (string) $dna['secondary_archetype'];
            $secArch = $archetypes[$secKey] ?? null;
            if ($secArch) {
                $archetypeName .= ' + ' . $secArch[1];
                $essence .= ' ' . self::secondaryEssence($secKey, $lang);
            }
        }

        $themes = [];
        $seenNames = [];
        foreach ((array) ($dna['themes'] ?? []) as $t) {
            $key = strtolower(trim((string) $t));
            if ($key === '') {
                continue;
            }
            if ($en) {
                $raw = self::cleanRawKeyword($key);
            } else {
                $themesTr = self::getThemesTr();
                // TMDB anahtarları İngilizcedir. Türkçe profilde sözlük dışı
                // anahtarı ham göstermek iki dili karıştırıyordu; kontrollü
                // taksonominin dışında kalanları sessizce atla.
                if (!isset($themesTr[$key])) {
                    continue;
                }
                $raw = $themesTr[$key];
            }
            if ($raw === '') {
                continue;
            }
            $first = mb_substr($raw, 0, 1, 'UTF-8');
            if (!$en && $first === 'i') {
                $first = 'İ';
            } else {
                $first = mb_convert_case($first, MB_CASE_UPPER, 'UTF-8');
            }
            $display = $first . mb_substr($raw, 1, null, 'UTF-8');

            $norm = mb_strtolower($display, 'UTF-8');
            if (isset($seenNames[$norm])) {
                continue;
            }
            $seenNames[$norm] = true;
            $themes[] = ['key' => $key, 'name' => $display];
        }

        $genres = [];
        foreach ((array) ($dna['top_genres'] ?? []) as $g) {
            $genres[] = self::genreName((int) $g, $lang);
        }

        $signals = [];

        $era = isset($dna['era']) && $dna['era'] !== null ? (string) $dna['era'] : null;
        if ($era !== null) {
            $modernShare = (float) ($dna['modern_share'] ?? 0);
            $signals[] = match ($era) {
                'modern' => $en
                    ? 'A modern soul — ' . self::pctPossessive($modernShare, $lang) . ' of your loves are post-2015.'
                    : 'Modern çağ çocuğu — beğenilerinin ' . self::pctPossessive($modernShare, $lang) . ' 2015 sonrası.',
                'classic_soul' => $en
                    ? 'A classic soul — you chase the magic of old cinema.'
                    : 'Klasik ruh — eski sinemanın büyüsünü kovalıyor.',
                default => $en
                    ? 'A time traveler — you feel at home in every era.'
                    : 'Zaman gezgini — her dönemde kendini evinde hissediyor.',
            };
        }

        $depth = isset($dna['depth']) && $dna['depth'] !== null ? (string) $dna['depth'] : null;
        if ($depth !== null) {
            $signals[] = match ($depth) {
                'deep_digger' => $en
                    ? 'A deep-cut hunter — you find the gems the crowd skips.'
                    : 'Derin keşif avcısı — kalabalığın atladığı mücevherleri buluyor.',
                'zeitgeist' => $en
                    ? 'A zeitgeist rider — you keep your finger on the pulse.'
                    : 'Zeitgeist takipçisi — anın nabzını tutuyor.',
                default => $en
                    ? 'A balanced explorer — you love both blockbusters and hidden gems.'
                    : 'Dengeli keşifçi — hem gişeyi hem gizli kalanı seviyor.',
            };
        }

        $critic = isset($dna['critic']) && $dna['critic'] !== null ? (string) $dna['critic'] : null;
        if ($critic !== null) {
            $harikaShare = (float) ($dna['harika_share'] ?? 0);
            $signals[] = match ($critic) {
                'tough' => $en
                    ? 'A tough critic — only ' . self::pctPossessive($harikaShare, $lang) . ' of your ratings are "Great".'
                    : 'Sert eleştirmen — puanlarının yalnızca ' . self::pctPossessive($harikaShare, $lang) . ' "Harika".',
                'generous' => $en
                    ? 'A generous heart — you\'re never afraid to call it "Great".'
                    : 'Cömert kalp — iyi bir hikâyeye "Harika" demekten çekinmiyor.',
                default => $en
                    ? 'A measured critic — your praise and your criticism both land.'
                    : 'Ölçülü eleştirmen — övgüsü de eleştirisi de yerini biliyor.',
            };
        }

        if (isset($dna['blind_spot']) && $dna['blind_spot'] !== null) {
            $genre = self::genreName((int) $dna['blind_spot'], $lang);
            $signals[] = $en
                ? 'Your blind spot: ' . $genre . ' — it just doesn\'t reach you.'
                : 'Kör noktası: ' . $genre . ' — pek hitap etmiyor.';
        }

        if (isset($dna['shift_from'], $dna['shift_to']) && $dna['shift_from'] !== null && $dna['shift_to'] !== null) {
            $from = self::genreName((int) $dna['shift_from'], $lang);
            $to = self::genreName((int) $dna['shift_to'], $lang);
            $signals[] = $en
                ? 'Your taste has drifted from ' . $from . ' to ' . $to . '.'
                : 'Zevkinin rotası: ' . $from . ' → ' . $to . '.';
        }

        $accuracy = null;
        if (isset($dna['accuracy']) && $dna['accuracy'] !== null && (float)$dna['accuracy'] >= 0.40) {
            $sample = (int) ($dna['accuracy_sample'] ?? 0);
            $accuracy = $en
                ? 'Taste match rate in recent recommendations: ' . self::pct((float) $dna['accuracy'], $lang)
                    . ' — across ' . $sample . ' picks.'
                : 'Son önerilerdeki uyum oranı: ' . self::pct((float) $dna['accuracy'], $lang)
                    . ' — ' . $sample . ' öneri üzerinden.';
        }

        $themesWithEvidence = [];
        if (isset($dna['theme_evidence']) && is_array($dna['theme_evidence'])) {
            foreach ($themes as $tItem) {
                $engKey = $tItem['key'];
                if (isset($dna['theme_evidence'][$engKey])) {
                    $themesWithEvidence[] = [
                        'name' => $tItem['name'],
                        'movies' => $dna['theme_evidence'][$engKey],
                    ];
                }
            }
        }

        $themeNamesOnly = array_map(fn($t) => $t['name'], $themes);

        return [
            'emoji' => $arch[0],
            'archetype' => $archetypeName,
            'essence' => $essence,
            'themes' => array_slice($themeNamesOnly, 0, 5),
            'genres' => array_slice($genres, 0, 3),
            'signals' => $signals,
            'accuracy' => $accuracy,
            'themes_with_evidence' => $themesWithEvidence,
        ];
    }

    private static function secondaryEssence(string $key, string $lang): string
    {
        if (self::isEn($lang)) {
            return match ($key) {
                'dark_chronicler' => 'Shadows, suspense and moral ambiguity also feed your taste.',
                'emotion_seeker' => 'Emotional depth and human stories also captivate you.',
                'world_builder' => 'Extraordinary universes and highly imaginative worlds also draw your interest.',
                'adrenaline_junkie' => 'Pace, action and adventure are also sources of excitement for you.',
                'joy_chaser' => 'Lightness, joy and comedy are also among your safe havens.',
                'truth_seeker' => 'True stories and real-life experiences are also on your radar.',
                'eternal_child' => 'The child in you that never grows up also finds its place in stories.',
                default => 'Colors of different genres also show themselves in your taste.',
            };
        }
        return match ($key) {
            'dark_chronicler' => 'Gölgeler, gerilim ve ahlaki grilik de zevkini besliyor.',
            'emotion_seeker' => 'Duygusal derinlik ve insani hikâyeler de onu cezbediyor.',
            'world_builder' => 'Sıra dışı evrenler ve hayal gücü yüksek dünyalar da ilgisini çekiyor.',
            'adrenaline_junkie' => 'Tempo, aksiyon ve macera da onun heyecan kaynağı.',
            'joy_chaser' => 'Hafiflik, neşe ve komedi de sığındığı limanlar arasında.',
            'truth_seeker' => 'Gerçek hikâyeler ve yaşanmışlıklar da onun radarında.',
            'eternal_child' => 'İçindeki büyümeyen çocuk da hikâyelerde yerini buluyor.',
            default => 'Farklı türlerin renkleri de zevkinde kendini gösteriyor.',
        };
    }

    private static function cleanRawKeyword(string $keyword): string
    {
        $clean = preg_replace('/\s*\([^)]*\)/u', '', $keyword);
        if (strpos($clean, ',') !== false) {
            $parts = explode(',', $clean);
            $clean = $parts[0];
        }
        return trim($clean);
    }
}
