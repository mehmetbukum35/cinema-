<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/TasteDnaWebText.php';

class TasteDnaWebTextTest extends TestCase
{
    public function testReturnsNullWhenNotReady(): void
    {
        $this->assertNull(TasteDnaWebText::build(null));
        $this->assertNull(TasteDnaWebText::build(['total_rated' => 3]));
    }

    public function testBuildsArchetypeThemesAndGenres(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'dark_chronicler',
            'total_rated' => 20,
            'themes' => ['revenge', 'dystopia'],
            'top_genres' => [27, 53],
            'era' => 'modern',
            'modern_share' => 0.75,
            'depth' => 'deep_digger',
            'critic' => 'tough',
            'harika_share' => 0.1,
        ]);

        $this->assertNotNull($view);
        $this->assertSame('Karanlık Anlatıcı', $view['archetype']);
        $this->assertSame('🕯️', $view['emoji']);
        // Temalar TR sözlüğünden çevrilir; baş harf Türkçe kurala göre (İ).
        $this->assertSame(['İntikam', 'Distopya'], $view['themes']);
        $this->assertSame(['Korku', 'Gerilim'], $view['genres']);
    }

    public function testUnknownThemeStaysEnglishCapitalized(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'themes' => ['obscurekeyword'],
        ]);
        $this->assertSame(['Obscurekeyword'], $view['themes']);
    }

    public function testEmbedsPercentagesInSignals(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'era' => 'modern',
            'modern_share' => 0.75,
            'critic' => 'tough',
            'harika_share' => 0.1,
        ]);

        $joined = implode(' | ', $view['signals']);
        // Türkçe iyelik eki sayının okunuşuna göre: %75'i (beş-i), %10'u (on-u).
        $this->assertStringContainsString("%75'i", $joined);
        $this->assertStringContainsString("%10'u", $joined);
    }

    public function testTurkishPossessiveSuffixMatchesPronunciation(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'critic' => 'tough',
            'harika_share' => 0.12,
        ]);
        $joined = implode(' | ', $view['signals']);
        $this->assertStringContainsString("%12'si", $joined); // %12'i DEĞİL
    }

    public function testBlindSpotAndShiftUseGenreNames(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'emotion_seeker',
            'total_rated' => 20,
            'blind_spot' => 35,
            'shift_from' => 28,
            'shift_to' => 18,
        ]);

        $joined = implode(' | ', $view['signals']);
        $this->assertStringContainsString('Komedi', $joined); // kör nokta
        // Kayma ek-siz ok biçiminde (hâl eki dilbilgisi riski taşır).
        $this->assertStringContainsString('Aksiyon → Dram', $joined);
        $this->assertStringNotContainsString("'dan", $joined);
    }

    public function testAccuracyOnlyWhenPresent(): void
    {
        $without = TasteDnaWebText::build([
            'archetype' => 'joy_chaser',
            'total_rated' => 20,
        ]);
        $this->assertNull($without['accuracy']);

        $with = TasteDnaWebText::build([
            'archetype' => 'joy_chaser',
            'total_rated' => 20,
            'accuracy' => 0.78,
            'accuracy_sample' => 20,
        ]);
        $this->assertStringContainsString('%78', $with['accuracy']);
        $this->assertStringContainsString('20', $with['accuracy']);

        // Accuracy below 40% should be null on public profile
        $low = TasteDnaWebText::build([
            'archetype' => 'joy_chaser',
            'total_rated' => 20,
            'accuracy' => 0.39,
            'accuracy_sample' => 20,
        ]);
        $this->assertNull($low['accuracy']);
    }

    public function testCleansRawKeywords(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'themes' => ['teheran (tehran), iran', 'tokyo, japan', 'family'],
        ]);
        
        $this->assertNotNull($view);
        // "teheran (tehran), iran" -> "Teheran"
        // "tokyo, japan" -> "Tokyo"
        // "family" -> "Aile" (translated)
        $this->assertSame(['Teheran', 'Tokyo', 'Aile'], $view['themes']);
    }

    public function testHandlesSecondaryArchetype(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'dark_chronicler',
            'secondary_archetype' => 'world_builder',
            'total_rated' => 20,
        ]);
        $this->assertNotNull($view);
        $this->assertSame('Karanlık Anlatıcı + Dünya Kâşifi', $view['archetype']);
        $this->assertStringContainsString('Sıra dışı evrenler ve hayal gücü yüksek dünyalar da ilgisini çekiyor.', $view['essence']);
    }

    public function testHandlesNullableDepthAndCritic(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'era' => 'time_traveler',
            'depth' => null,
            'critic' => null,
        ]);
        $this->assertNotNull($view);
        $this->assertCount(1, $view['signals']); // Era signal is still there, depth and critic are omitted
        $this->assertStringContainsString('Zaman gezgini', $view['signals'][0]);
    }

    public function testBuildsThemesWithEvidence(): void
    {
        $view = TasteDnaWebText::build([
            'archetype' => 'genre_nomad',
            'total_rated' => 20,
            'themes' => ['revenge'],
            'theme_evidence' => [
                'revenge' => [
                    ['id' => 101, 'title' => 'Oldboy', 'poster_path' => '/old.jpg']
                ]
            ]
        ]);
        $this->assertNotNull($view);
        $this->assertCount(1, $view['themes_with_evidence']);
        $this->assertSame('İntikam', $view['themes_with_evidence'][0]['name']);
        $this->assertSame('Oldboy', $view['themes_with_evidence'][0]['movies'][0]['title']);
    }

    public function testLexiconParityWithDart(): void
    {
        $dartPath = __DIR__ . '/../../lib/services/taste_dna_presenter.dart';
        if (!is_file($dartPath)) {
            $this->markTestSkipped('Dart presenter file not found.');
        }

        $dartContent = file_get_contents($dartPath);
        // Find: static const Map<String, String> themeTr = { ... };
        if (!preg_match('/themeTr\s*=\s*\{([^}]+)\}/s', $dartContent, $matches)) {
            $this->fail('Could not extract themeTr map from Dart presenter.');
        }

        $lines = explode("\n", $matches[1]);
        $dartMap = [];
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '//')) {
                continue;
            }
            // Match: 'key': 'value',
            if (preg_match('/\'([^\']+)\'\s*:\s*\'([^\']+)\'/', $line, $m)) {
                $dartMap[$m[1]] = $m[2];
            }
        }

        // Extract PHP map via reflection
        $ref = new ReflectionClass(TasteDnaWebText::class);
        $phpMap = $ref->getConstant('THEMES_TR');

        $this->assertEquals($dartMap, $phpMap, 'Lexicon drift detected! Dart themeTr and PHP THEMES_TR maps must be identical.');
    }
}
