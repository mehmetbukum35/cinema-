<?php
declare(strict_types=1);

class Smtp
{
    private string $host;
    private int $port;
    private string $user;
    private string $pass;

    public function __construct(string $host, int $port, string $user, string $pass)
    {
        $this->host = $host;
        $this->port = $port;
        $this->user = $user;
        $this->pass = $pass;
    }

    public function send(string $to, string $subject, string $body): bool
    {
        // Sanitize to prevent CRLF injection in SMTP headers/commands
        $to = str_replace(["\r", "\n"], '', $to);
        $subject = str_replace(["\r", "\n"], '', $subject);

        $remote = 'ssl://' . $this->host;
        $socket = @stream_socket_client("$remote:{$this->port}", $errno, $errstr, 15);
        if (!$socket) {
            if (function_exists('cinema_error')) {
                cinema_error("SMTP connection failed: $errstr ($errno)");
            } else {
                error_log("SMTP connection failed: $errstr ($errno)");
            }
            return false;
        }
        $getResponse = function ($socket) {
            $data = '';
            while ($str = fgets($socket, 515)) {
                $data .= $str;
                if (substr($str, 3, 1) === ' ') {
                    break;
                }
            }
            return $data;
        };

        $sendCommand = function ($socket, $cmd) use ($getResponse) {
            fputs($socket, $cmd . "\r\n");
            return $getResponse($socket);
        };

        $getResponse($socket);

        $sendCommand($socket, "EHLO " . $this->host);

        $resp = $sendCommand($socket, "AUTH LOGIN");
        if (strpos($resp, '334') === false) {
            fclose($socket);
            return false;
        }

        $resp = $sendCommand($socket, base64_encode($this->user));
        if (strpos($resp, '334') === false) {
            fclose($socket);
            return false;
        }

        $resp = $sendCommand($socket, base64_encode($this->pass));
        if (strpos($resp, '235') === false) {
            fclose($socket);
            return false;
        }

        $sendCommand($socket, "MAIL FROM:<{$this->user}>");

        $resp = $sendCommand($socket, "RCPT TO:<{$to}>");
        if (strpos($resp, '250') === false && strpos($resp, '251') === false) {
            fclose($socket);
            return false;
        }

        $resp = $sendCommand($socket, "DATA");
        if (strpos($resp, '354') === false) {
            fclose($socket);
            return false;
        }

        $headers = [
            "MIME-Version: 1.0",
            "Content-Type: text/html; charset=UTF-8",
            "From: =?UTF-8?B?" . base64_encode("Ne İzlesem") . "?= <{$this->user}>",
            "To: <{$to}>",
            "Subject: =?UTF-8?B?" . base64_encode($subject) . "?=",
            "Date: " . date('r'),
            "Message-ID: <" . time() . "-" . md5($this->user . $to) . "@" . $this->host . ">",
        ];

        $message = implode("\r\n", $headers) . "\r\n\r\n" . $body . "\r\n.";
        $resp = $sendCommand($socket, $message);
        
        $sendCommand($socket, "QUIT");
        fclose($socket);

        return strpos($resp, '250') !== false;
    }
}
