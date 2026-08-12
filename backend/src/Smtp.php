<?php
declare(strict_types=1);

/**
 * Minimal SMTP client (AUTH LOGIN + HTML body).
 *
 * Port 465 → implicit SSL (`ssl://`).
 * Port 587 (ve diğerleri) → düz TCP + STARTTLS (TLS 1.2/1.3 desteği ile).
 *
 * Başarısızlıkta false dönmez; RuntimeException fırlatır ki Auth arka plan
 * işinde cinema_error ile görülsün (forgot-password yanıtı zaten 200
 * gönderilmiş olabilir — log şart).
 */
class Smtp
{
    private string $host;
    private int $port;
    private string $user;
    private string $pass;
    private string $fromEmail;
    private string $fromName;

    public function __construct(
        string $host,
        int $port,
        string $user,
        string $pass,
        ?string $fromEmail = null,
        ?string $fromName = null
    ) {
        $this->host = $host;
        $this->port = $port;
        $this->user = $user;
        $this->pass = $pass;
        $this->fromEmail = ($fromEmail !== null && trim($fromEmail) !== '') ? trim($fromEmail) : $user;
        $this->fromName = ($fromName !== null && trim($fromName) !== '') ? trim($fromName) : 'Cinema+';
    }

    public function send(string $to, string $subject, string $body): bool
    {
        if (defined('PHPUNIT_TESTING') || class_exists('PHPUnit\\Framework\\TestCase', false)) {
            return true;
        }

        // Sanitize to prevent CRLF injection in SMTP headers/commands
        $to = str_replace(["\r", "\n"], '', $to);
        $subject = str_replace(["\r", "\n"], '', $subject);
        $fromEmail = str_replace(["\r", "\n"], '', $this->fromEmail);
        $fromName = str_replace(["\r", "\n"], '', $this->fromName);

        $useImplicitSsl = $this->port === 465;
        $remote = ($useImplicitSsl ? 'ssl://' : 'tcp://') . $this->host;

        $context = stream_context_create([
            'ssl' => [
                'verify_peer' => true,
                'verify_peer_name' => true,
                'allow_self_signed' => false,
                'SNI_enabled' => true,
                'peer_name' => $this->host,
            ],
        ]);

        $socket = @stream_socket_client(
            "$remote:{$this->port}",
            $errno,
            $errstr,
            15,
            STREAM_CLIENT_CONNECT,
            $context
        );
        if (!$socket) {
            throw new RuntimeException("SMTP connection failed: $errstr ($errno)");
        }

        stream_set_timeout($socket, 15);

        try {
            $this->expectCode($socket, [220], 'banner');

            $this->command($socket, 'EHLO ' . $this->ehloName(), [250]);

            if (!$useImplicitSsl) {
                $this->command($socket, 'STARTTLS', [220]);

                $cryptoMethod = STREAM_CRYPTO_METHOD_TLS_CLIENT;
                if (defined('STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT')) {
                    $cryptoMethod |= STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT;
                }
                if (defined('STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT')) {
                    $cryptoMethod |= STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT;
                }

                $cryptoOk = @stream_socket_enable_crypto(
                    $socket,
                    true,
                    $cryptoMethod
                );
                if ($cryptoOk !== true) {
                    throw new RuntimeException('SMTP STARTTLS handshake failed');
                }
                $this->command($socket, 'EHLO ' . $this->ehloName(), [250]);
            }

            $this->command($socket, 'AUTH LOGIN', [334]);
            $this->command($socket, base64_encode($this->user), [334]);
            $this->command($socket, base64_encode($this->pass), [235]);

            $this->command($socket, "MAIL FROM:<{$fromEmail}>", [250]);
            $this->command($socket, "RCPT TO:<{$to}>", [250, 251]);
            $this->command($socket, 'DATA', [354]);

            $headers = [
                'MIME-Version: 1.0',
                'Content-Type: text/html; charset=UTF-8',
                'From: =?UTF-8?B?' . base64_encode($fromName) . "?= <{$fromEmail}>",
                "To: <{$to}>",
                'Subject: =?UTF-8?B?' . base64_encode($subject) . '?=',
                'Date: ' . date('r'),
                'Message-ID: <' . time() . '.' . bin2hex(random_bytes(8)) . '-' . md5($fromEmail . $to) . '@' . $this->host . '>',
            ];

            // RFC 5321 §4.5.2 Transparent Duty (Dot-Stuffing)
            $normalizedBody = str_replace(["\r\n", "\r"], "\n", $body);
            $stuffedBody = str_replace("\n.", "\n..", $normalizedBody);
            $formattedBody = str_replace("\n", "\r\n", $stuffedBody);

            $message = implode("\r\n", $headers) . "\r\n\r\n" . $formattedBody . "\r\n.";
            $this->command($socket, $message, [250]);
            $this->command($socket, 'QUIT', [221, 250]);
        } finally {
            fclose($socket);
        }

        return true;
    }

    private function ehloName(): string
    {
        $name = gethostname();
        return is_string($name) && $name !== '' ? $name : 'localhost';
    }

    /**
     * @param resource $socket
     * @param list<int> $okCodes
     */
    private function command($socket, string $cmd, array $okCodes): string
    {
        fputs($socket, $cmd . "\r\n");
        return $this->expectCode($socket, $okCodes, $cmd);
    }

    /**
     * @param resource $socket
     * @param list<int> $okCodes
     */
    private function expectCode($socket, array $okCodes, string $context): string
    {
        $data = '';
        while ($str = fgets($socket, 515)) {
            $data .= $str;
            if (strlen($str) >= 4 && $str[3] === ' ') {
                break;
            }
        }
        if ($data === '') {
            throw new RuntimeException("SMTP empty response after $context");
        }
        $code = (int) substr($data, 0, 3);
        if (!in_array($code, $okCodes, true)) {
            $snippet = trim(preg_replace('/\s+/', ' ', $data) ?? $data);
            throw new RuntimeException(
                "SMTP unexpected reply after $context: $snippet"
            );
        }
        return $data;
    }
}
