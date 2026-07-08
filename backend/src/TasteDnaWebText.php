<?php
declare(strict_types=1);

// Sinema DNA snapshot'ını (cihazdan gelen anahtarlar) public web profili için
// Türkçe gösterim metnine çevirir. Algoritma cihazda çalışır; burada yalnızca
// snapshot → metin eşlemesi vardır (Dart TasteDnaPresenter'ın PHP karşılığı;
// web profili Türkçe olduğundan metinler Türkçedir).
class TasteDnaWebText
{
    private const ARCHETYPES = [
        'dark_chronicler' => ['🕯️', 'Karanlık Anlatıcı', 'Gölgelere, gerilime ve ahlaki griliğe çekiliyor.'],
        'emotion_seeker' => ['🎭', 'Duygu Avcısı', 'Kalbe dokunan, insanı anlatan hikâyelerin peşinde.'],
        'world_builder' => ['🌌', 'Dünya Kâşifi', 'Yeni evrenler, imkânsız dünyalar onu çağırıyor.'],
        'adrenaline_junkie' => ['⚡', 'Adrenalin Tutkunu', 'Tempo, aksiyon ve macera onun yakıtı.'],
        'joy_chaser' => ['✨', 'Neşe Avcısı', 'Kahkaha ve hafiflik onun sığınağı.'],
        'truth_seeker' => ['🔍', 'Gerçeğin Peşinde', 'Gerçek hikâyeler ve geçmişin dersleri ilgisini çekiyor.'],
        'eternal_child' => ['🎈', 'Sonsuz Çocuk', 'İçindeki çocuk hiç büyümedi — ve bu çok iyi.'],
        'genre_nomad' => ['🧭', 'Tür Göçebesi', 'Tek bir türe sığmıyor; her renkten tadıyor.'],
    ];

    private const GENRES = [
        28 => 'Aksiyon', 12 => 'Macera', 16 => 'Animasyon', 35 => 'Komedi',
        80 => 'Suç', 99 => 'Belgesel', 18 => 'Dram', 10751 => 'Aile',
        14 => 'Fantastik', 36 => 'Tarih', 27 => 'Korku', 10402 => 'Müzik',
        9648 => 'Gizem', 10749 => 'Romantik', 878 => 'Bilim Kurgu',
        53 => 'Gerilim', 10752 => 'Savaş', 37 => 'Western',
        10759 => 'Aksiyon & Macera', 10762 => 'Çocuk', 10763 => 'Haber',
        10764 => 'Realite', 10765 => 'Bilim Kurgu & Fantastik',
        10766 => 'Pembe Dizi', 10767 => 'Program', 10768 => 'Savaş & Politika',
    ];

    // TMDB keyword'leri İngilizce döner; sık temalar için TR sözlüğü.
    // Dart karşılığı: lib/services/taste_dna_presenter.dart (themeTr) —
    // ikisi senkron tutulmalı.
    private static ?array $themesTr = null;

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

    private static function genreName(int $id): string
    {
        return self::GENRES[$id] ?? 'Bilinmeyen';
    }

    private static function pct(float $v): string
    {
        return '%' . (int) round($v * 100);
    }

    /**
     * TR iyelik ekli yüzde: "%75'i", "%12'si", "%10'u" — ek, sayının OKUNUŞUNA
     * göre seçilir. Dart karşılığı: TasteDnaPresenter.trNumberPossessiveSuffix.
     */
    private static function pctPossessive(float $v): string
    {
        $n = (int) round($v * 100);
        $units = [1 => "'i", 2 => "'si", 3 => "'ü", 4 => "'ü", 5 => "'i",
                  6 => "'sı", 7 => "'si", 8 => "'i", 9 => "'u"];
        $tens = [10 => "'u", 20 => "'si", 30 => "'u", 40 => "'ı", 50 => "'si",
                 60 => "'ı", 70 => "'i", 80 => "'i", 90 => "'ı"];
        if ($n === 0) {
            $suffix = "'ı"; // sıfır-ı
        } elseif ($n % 100 === 0) {
            $suffix = "'ü"; // yüz-ü
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
    public static function build(?array $dna): ?array
    {
        if (!is_array($dna)) {
            return null;
        }
        $total = (int) ($dna['total_rated'] ?? 0);
        if ($total < 5) {
            return null;
        }

        $archKey = (string) ($dna['archetype'] ?? 'genre_nomad');
        $arch = self::ARCHETYPES[$archKey] ?? self::ARCHETYPES['genre_nomad'];
        $archetypeName = $arch[1];
        $essence = $arch[2];

        if (!empty($dna['secondary_archetype'])) {
            $secKey = (string) $dna['secondary_archetype'];
            $secArch = self::ARCHETYPES[$secKey] ?? null;
            if ($secArch) {
                $archetypeName .= ' + ' . $secArch[1];
                $essence .= ' ' . self::secondaryEssence($secKey);
            }
        }

        // Temalar: sözlükten Türkçeye çevrilir. Sözlükte olmayan ham TMDB
        // keyword'leri TEMİZLENİR (parantezli takılar ve ", ülke" kuyrukları
        // atılır; ör. "teheran (tehran), iran" → "Teheran") ve görünen ada
        // göre tekilleştirilir ki "İran" ile "Teheran, iran" gibi yakın
        // kopyalar çip listesini şişirmesin. Kanıt eşlemesi için her temanın
        // orijinal İngilizce anahtarı yanında taşınır.
        $themes = []; // her öğe: ['key' => ingilizce anahtar, 'name' => görünen ad]
        $seenNames = [];
        foreach ((array) ($dna['themes'] ?? []) as $t) {
            $key = strtolower(trim((string) $t));
            if ($key === '') {
                continue;
            }
            $themesTr = self::getThemesTr();
            $tr = $themesTr[$key] ?? self::cleanRawKeyword($key);
            if ($tr === '') {
                continue;
            }
            // Türkçe baş harf: 'i' → 'İ' (mb_convert_case İngilizce 'I' üretir).
            $first = mb_substr($tr, 0, 1, 'UTF-8');
            $first = $first === 'i'
                ? 'İ'
                : mb_convert_case($first, MB_CASE_UPPER, 'UTF-8');
            $display = $first . mb_substr($tr, 1, null, 'UTF-8');

            $norm = mb_strtolower($display, 'UTF-8');
            if (isset($seenNames[$norm])) {
                continue;
            }
            $seenNames[$norm] = true;
            $themes[] = ['key' => $key, 'name' => $display];
        }

        // Türler
        $genres = [];
        foreach ((array) ($dna['top_genres'] ?? []) as $g) {
            $genres[] = self::genreName((int) $g);
        }

        // Sinyal cümleleri
        $signals = [];

        $era = isset($dna['era']) && $dna['era'] !== null ? (string) $dna['era'] : null;
        if ($era !== null) {
            $modernShare = (float) ($dna['modern_share'] ?? 0);
            $signals[] = match ($era) {
                'modern' => 'Modern çağ çocuğu — beğenilerinin ' . self::pctPossessive($modernShare) . ' 2015 sonrası.',
                'classic_soul' => 'Klasik ruh — eski sinemanın büyüsünü kovalıyor.',
                default => 'Zaman gezgini — her dönemde kendini evinde hissediyor.',
            };
        }

        $depth = isset($dna['depth']) && $dna['depth'] !== null ? (string) $dna['depth'] : null;
        if ($depth !== null) {
            $signals[] = match ($depth) {
                'deep_digger' => 'Derin keşif avcısı — kalabalığın atladığı mücevherleri buluyor.',
                'zeitgeist' => 'Zeitgeist takipçisi — anın nabzını tutuyor.',
                default => 'Dengeli keşifçi — hem gişeyi hem gizli kalanı seviyor.',
            };
        }

        $critic = isset($dna['critic']) && $dna['critic'] !== null ? (string) $dna['critic'] : null;
        if ($critic !== null) {
            $harikaShare = (float) ($dna['harika_share'] ?? 0);
            $signals[] = match ($critic) {
                'tough' => 'Sert eleştirmen — puanlarının yalnızca ' . self::pctPossessive($harikaShare) . ' "Harika".',
                'generous' => 'Cömert kalp — iyi bir hikâyeye "Harika" demekten çekinmiyor.',
                default => 'Ölçülü eleştirmen — övgüsü de eleştirisi de yerini biliyor.',
            };
        }

        if (isset($dna['blind_spot']) && $dna['blind_spot'] !== null) {
            $signals[] = 'Kör noktası: ' . self::genreName((int) $dna['blind_spot']) . ' — pek hitap etmiyor.';
        }

        // Tür adlarına hâl eki takmak (Komedi'den, Gerilim'e...) hataya açık;
        // ok'lu biçim hem dilbilgisi-güvenli hem net.
        if (isset($dna['shift_from'], $dna['shift_to']) && $dna['shift_from'] !== null && $dna['shift_to'] !== null) {
            $signals[] = 'Zevkinin rotası: ' . self::genreName((int) $dna['shift_from'])
                . ' → ' . self::genreName((int) $dna['shift_to']) . '.';
        }

        // Kanıtlı isabet - Uyum oranı >= %40 ise gösterilir
        $accuracy = null;
        if (isset($dna['accuracy']) && $dna['accuracy'] !== null && (float)$dna['accuracy'] >= 0.40) {
            $sample = (int) ($dna['accuracy_sample'] ?? 0);
            $accuracy = 'Son önerilerdeki uyum oranı: ' . self::pct((float) $dna['accuracy'])
                . ' — ' . $sample . ' öneri üzerinden.';
        }

        // Temalar ve kanıt filmleri
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

    private static function secondaryEssence(string $key): string
    {
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
        // Parantez içindeki metni ve parantezleri temizle
        $clean = preg_replace('/\s*\([^)]*\)/u', '', $keyword);
        // Virgülden sonrasını (örn. ", ülke") at
        if (strpos($clean, ',') !== false) {
            $parts = explode(',', $clean);
            $clean = $parts[0];
        }
        return trim($clean);
    }
}
