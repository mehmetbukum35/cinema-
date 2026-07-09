<?php
declare(strict_types=1);
// Bu dosyayı "Config.php" olarak kopyala ve gerçek değerlerle doldur.
// Config.php'yi ASLA repoya ekleme (.gitignore'da olmalı) ve web kök dizini DIŞINDA tut.
return [
    'db' => [
        'host'    => 'localhost',
        'name'    => 'your_database_name',
        'user'    => 'your_database_user',
        'pass'    => 'your_database_password',
        'charset' => 'utf8mb4',
    ],

    // En az 32 karakter rastgele. Üret: bin2hex(random_bytes(32))
    'jwt_secret' => 'generate_a_random_32_bytes_hex_string_here',

    'access_ttl'  => 2 * 60 * 60,             // access token: 2 saat (saniye)
    'refresh_ttl' => 30 * 24 * 60 * 60,   // refresh token: 30 gün (saniye)

    // Basit brute-force koruması (giriş/kayıt için): IP başına dakikada deneme
    'rate_limit_per_min' => 20,

    // Opsiyonel — verilmezse parantez içindeki varsayılanlar kullanılır:
    // POST /auth/refresh ve /auth/logout için IP başına dakikalık sınır (60).
    // 'refresh_rate_limit_per_min' => 60,
    // GET/POST /sync için kullanıcı başına dakikalık sınır (120).
    // 'sync_rate_limit_per_min' => 120,

    'smtp' => [
        'host' => 'mail.example.com',
        'port' => 465,
        'user' => 'your_smtp_email',
        'pass' => 'your_smtp_password',
    ],

    // Google Sign-In (POST /auth/google). client_ids: ID token'ın "aud"
    // claim'inde kabul edilecek OAuth client ID'leri. Flutter'ın serverClientId
    // olarak kullandığı WEB client ID mutlaka burada olmalı (Google Cloud
    // Console > Credentials > OAuth 2.0 Client IDs > Web client).
    'google' => [
        'client_ids' => [
            'your_web_client_id.apps.googleusercontent.com',
        ],
    ],

    // Yalnızca sunucuda tutulur; client'a asla gönderilmez (bkz. src/Tmdb.php).
    'tmdb_api_key' => 'your_tmdb_api_key_here',
    // GET /tmdb/* proxy'si için IP başına dakikalık istek sınırı.
    'tmdb_rate_limit_per_min' => 120,

    // Yorum moderasyon paneli (GET /admin/moderation?key=...) için anahtar.
    // En az 32 karakter rastgele üret: bin2hex(random_bytes(32)).
    // Boş bırakılırsa panel tamamen devre dışı kalır (404 döner).
    'admin_key' => '',

    // Firebase Cloud Messaging (push bildirimleri).
    // service_account: Firebase Console > Project settings > Service accounts >
    //   "Generate new private key" ile inen JSON dosyasının tam yolu. Web kök DIŞINDA tut, repoya ekleme.
    // project_id: JSON içindeki project_id ile aynı olmalı (ör. cinema-6bdc3).
    // Bu blok yoksa/dosya bulunamazsa veya boş bırakılırsa push sessizce devre dışı kalır.
    'fcm' => [
        'service_account' => '/path/to/fcm-service-account.json',
        'project_id'      => 'your_firebase_project_id',
    ],
];
