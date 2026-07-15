<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;
use PHPUnit\Framework\Attributes\DataProvider;

/**
 * Küfür/spam filtresi birim testleri (comment_flagged, sanitize_comment).
 */
class ProfanityFilterTest extends TestCase
{
    // ─── Masum Türkçe / İngilizce ────────────────────────────────────────────

    #[DataProvider('innocentCommentsProvider')]
    public function testInnocentCommentsAreNotFlagged(string $comment): void
    {
        $this->assertFalse(comment_flagged($comment));
    }

    public static function innocentCommentsProvider(): array
    {
        return [
            'tamam'           => ['Film gayet iyiydi, tamam mı?'],
            'sıkı'            => ['Sıkı bir gerilim filmi, tavsiye ederim.'],
            'klasik'          => ['Klasik bir başyapıt.'],
            'got_en'          => ['I got emotional at the ending.'],
            'topic'           => ['Great topic for a sequel.'],
            'boks'            => ['Boks sahnesi çok gerçekçiydi.'],
            'animal'          => ['Animal Kingdom çok etkileyiciydi.'],
            'aram'            => ['Aramızda kalsın, sonu şaşırtıcı.'],
            'normal'          => ['Normal bir aksiyon filmi, beklentimi karşıladı.'],
            'focus'           => ['The camera focus was excellent.'],
            'masum_tr'        => ['Harika bir yapım, kesinlikle izleyin.'],
        ];
    }

    // ─── Bariz küfür ─────────────────────────────────────────────────────────

    #[DataProvider('profaneCommentsProvider')]
    public function testProfaneCommentsAreFlagged(string $comment): void
    {
        $this->assertTrue(comment_flagged($comment));
    }

    public static function profaneCommentsProvider(): array
    {
        return [
            // TR — düz
            'amk'             => ['bu film amk berbat'],
            'orospu'          => ['ne orospu karakter'],
            'sikerim'         => ['sikerim böyle filmleri'],
            'yarrak'          => ['yarrak gibi senaryo'],
            'ibne'            => ['ibne karakter'],
            'oç'              => ['bu oç nasıl kahraman oldu'],
            'piç'             => ['piç gibi davranıyor'],
            'göt_tr'          => ['göt gibi film'],
            'aminakoyim'      => ['aminakoyim ne kötü'],
            // EN — düz
            'fuck'            => ['what the fuck was that ending'],
            'shit'            => ['total shit movie'],
            'bitch'           => ['bitch please'],
            'asshole'         => ['the director is an asshole'],
            'nigger'          => ['you nigger'],
            // spam
            'casino'          => ['bedava casino bonusu burada'],
            'porno'           => ['ücretsiz porno linki'],
        ];
    }

    // ─── Obfuscation ─────────────────────────────────────────────────────────

    public function testSpacedObfuscationIsCaught(): void
    {
        $this->assertTrue(comment_flagged('a m k ne film'));
        $this->assertTrue(comment_flagged('a.m.k berbat'));
        $this->assertTrue(comment_flagged('a-m-k'));
        $this->assertTrue(comment_flagged('f u c k this'));
        $this->assertTrue(comment_flagged('o r o s p u'));
    }

    public function testRepeatedCharsObfuscationIsCaught(): void
    {
        $this->assertTrue(comment_flagged('amkkk çok kötü'));
        $this->assertTrue(comment_flagged('orospppu'));
        $this->assertTrue(comment_flagged('fuuuuck'));
    }

    public function testLeetspeakObfuscationIsCaught(): void
    {
        $this->assertTrue(comment_flagged('4mk berbat'));
        $this->assertTrue(comment_flagged('f*ck')); // * stripped in compact? let me check
        $this->assertTrue(comment_flagged('sh1t film'));
        $this->assertTrue(comment_flagged('b1tch'));
    }

    public function testDiacriticFoldCatchesMisspellings(): void
    {
        $this->assertTrue(comment_flagged('orospu')); // baseline
        $this->assertTrue(comment_flagged('yavsak herif'));
        $this->assertTrue(comment_flagged('serefsiz'));
    }

    public function testEnglishGotIsNotFlaggedButTurkishGotIs(): void
    {
        $this->assertFalse(comment_flagged('I got scared'));
        $this->assertTrue(comment_flagged('götün gibi'));
        $this->assertTrue(comment_flagged('g0tune benziyor'));
    }

    // ─── sanitize_comment davranışı korunur ──────────────────────────────────

    public function testSanitizeCommentTruncatesTo280(): void
    {
        $long = str_repeat('ö', 400);
        $out  = sanitize_comment($long);
        $this->assertNotNull($out);
        $this->assertSame(280, mb_strlen($out, 'UTF-8'));
    }

    public function testSanitizeCommentStripsUrls(): void
    {
        $out = sanitize_comment('Güzel film https://evil.com/spam devam');
        $this->assertNotNull($out);
        $this->assertStringNotContainsString('http', $out);
        $this->assertStringContainsString('Güzel film', $out);
    }

    public function testSanitizeCommentStripsControlChars(): void
    {
        $out = sanitize_comment("satır\x00gizli");
        $this->assertSame('satırgizli', $out);
    }

    public function testSanitizeCommentEmptyBecomesNull(): void
    {
        $this->assertNull(sanitize_comment(''));
        $this->assertNull(sanitize_comment('   '));
        $this->assertNull(sanitize_comment('https://only-url.com'));
    }
}
