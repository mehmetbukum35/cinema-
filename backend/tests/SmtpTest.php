<?php
declare(strict_types=1);

use PHPUnit\Framework\TestCase;

final class SmtpTest extends TestCase
{
    public function testSendIsNoOpUnderPhpunit(): void
    {
        $smtp = new Smtp('mail.example.com', 465, 'u@example.com', 'secret');
        $this->assertTrue(
            $smtp->send('to@example.com', 'Konu', '<p>merhaba</p>')
        );
    }

    public function testConstructAcceptsStarttlsPort(): void
    {
        $smtp = new Smtp('smtp.example.com', 587, 'u@example.com', 'secret');
        $this->assertInstanceOf(Smtp::class, $smtp);
    }

    public function testConstructAcceptsCustomFromEmailAndName(): void
    {
        $smtp = new Smtp(
            'smtp.example.com',
            587,
            'smtp_user',
            'secret',
            'noreply@cinema.com',
            'Cinema+ Destek'
        );
        $this->assertInstanceOf(Smtp::class, $smtp);
        $this->assertTrue(
            $smtp->send('user@example.com', 'Test', '<p>.Dot test</p>')
        );
    }
}
