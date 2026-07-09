<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/../src/SocialWebRenderer.php';

class SocialWebRendererLangTest extends TestCase
{
    protected function tearDown(): void
    {
        unset($_GET['lang']);
        parent::tearDown();
    }

    public function testExplicitLangQueryParam(): void
    {
        $_GET['lang'] = 'en';
        $this->assertSame('en', SocialWebRenderer::resolveWebProfileLang());

        $_GET['lang'] = 'tr';
        $this->assertSame('tr', SocialWebRenderer::resolveWebProfileLang());
    }

    public function testAcceptLanguageTurkish(): void
    {
        unset($_GET['lang']);
        $this->assertSame('tr', SocialWebRenderer::langFromAcceptLanguage('tr-TR,tr;q=0.9,en-US;q=0.8'));
        $this->assertSame('tr', SocialWebRenderer::langFromAcceptLanguage('tr'));
    }

    public function testAcceptLanguageDefaultsToEnglish(): void
    {
        unset($_GET['lang']);
        $this->assertSame('en', SocialWebRenderer::langFromAcceptLanguage(''));
        $this->assertSame('en', SocialWebRenderer::langFromAcceptLanguage('en-US,en;q=0.9'));
        $this->assertSame('en', SocialWebRenderer::langFromAcceptLanguage('de-DE,de;q=0.9,en;q=0.8'));

        $_SERVER['HTTP_ACCEPT_LANGUAGE'] = 'en-US,en;q=0.9';
        $this->assertSame('en', SocialWebRenderer::resolveWebProfileLang());
        unset($_SERVER['HTTP_ACCEPT_LANGUAGE']);
    }
}
