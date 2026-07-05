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

    private static function genreName(int $id): string
    {
        return self::GENRES[$id] ?? 'Bilinmeyen';
    }

    private static function pct(float $v): string
    {
        return '%' . (int) round($v * 100);
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

        // Temalar (İngilizce keyword'ler; baş harf büyütülür)
        $themes = [];
        foreach ((array) ($dna['themes'] ?? []) as $t) {
            $t = (string) $t;
            if ($t !== '') {
                $themes[] = ucfirst($t);
            }
        }

        // Türler
        $genres = [];
        foreach ((array) ($dna['top_genres'] ?? []) as $g) {
            $genres[] = self::genreName((int) $g);
        }

        // Sinyal cümleleri
        $signals = [];

        $era = (string) ($dna['era'] ?? 'time_traveler');
        $modernShare = (float) ($dna['modern_share'] ?? 0);
        $signals[] = match ($era) {
            'modern' => 'Modern çağ çocuğu — beğenilerinin ' . self::pct($modernShare) . '\'i 2015 sonrası.',
            'classic_soul' => 'Klasik ruh — eski sinemanın büyüsünü kovalıyor.',
            default => 'Zaman gezgini — her dönemde kendini evinde hissediyor.',
        };

        $depth = (string) ($dna['depth'] ?? 'balanced');
        $signals[] = match ($depth) {
            'deep_digger' => 'Derin keşif avcısı — kalabalığın atladığı mücevherleri buluyor.',
            'zeitgeist' => 'Zeitgeist takipçisi — anın nabzını tutuyor.',
            default => 'Dengeli keşifçi — hem gişeyi hem gizli kalanı seviyor.',
        };

        $critic = (string) ($dna['critic'] ?? 'balanced');
        $harikaShare = (float) ($dna['harika_share'] ?? 0);
        $signals[] = match ($critic) {
            'tough' => 'Sert eleştirmen — puanlarının yalnızca ' . self::pct($harikaShare) . '\'i "Harika".',
            'generous' => 'Cömert kalp — iyi bir hikâyeye "Harika" demekten çekinmiyor.',
            default => 'Ölçülü eleştirmen — övgüsü de eleştirisi de yerini biliyor.',
        };

        if (isset($dna['blind_spot']) && $dna['blind_spot'] !== null) {
            $signals[] = 'Kör noktası: ' . self::genreName((int) $dna['blind_spot']) . ' — pek hitap etmiyor.';
        }

        if (isset($dna['shift_from'], $dna['shift_to']) && $dna['shift_from'] !== null && $dna['shift_to'] !== null) {
            $signals[] = 'Zevki ' . self::genreName((int) $dna['shift_from'])
                . '\'dan ' . self::genreName((int) $dna['shift_to']) . '\'a doğru kaydı.';
        }

        // Kanıtlı isabet
        $accuracy = null;
        if (isset($dna['accuracy']) && $dna['accuracy'] !== null) {
            $sample = (int) ($dna['accuracy_sample'] ?? 0);
            $accuracy = 'Öneri motoru onu ' . self::pct((float) $dna['accuracy'])
                . ' isabetle tanıyor — ' . $sample . ' öneri üzerinden.';
        }

        return [
            'emoji' => $arch[0],
            'archetype' => $arch[1],
            'essence' => $arch[2],
            'themes' => array_slice($themes, 0, 5),
            'genres' => array_slice($genres, 0, 3),
            'signals' => $signals,
            'accuracy' => $accuracy,
        ];
    }
}
