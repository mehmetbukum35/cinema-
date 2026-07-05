<?php
declare(strict_types=1);

class SocialWebRenderer
{
    public function __construct(private PDO $db) {}

    public function renderPublicWebProfile(string $username): void
    {
        // Kullanıcıyı bul
        $st = $this->db->prepare('SELECT id, display_name, username, is_public FROM users WHERE username = ?');
        $st->execute([$username]);
        $user = $st->fetch();

        if (!$user) {
            $this->renderWebError('Kullanıcı bulunamadı', 'Aradığınız profil sistemimizde kayıtlı görünmüyor.');
            return;
        }

        if ((int) $user['is_public'] !== 1) {
            $this->renderWebError('Gizli Profil', 'Bu kullanıcı profilini dış dünyaya kapatmayı tercih etmiş.');
            return;
        }

        $userId = (int) $user['id'];

        // Beğendikleri (Rating = 3 "Harika")
        $stRatings = $this->db->prepare(
            'SELECT movie_id, is_tv, title, poster_path, vote_average, release_date
             FROM ratings
             WHERE user_id = ? AND rating = 3 AND deleted = 0
             ORDER BY updated_at DESC
             LIMIT 12'
        );
        $stRatings->execute([$userId]);
        $ratings = $stRatings->fetchAll();

        // Watchlist
        $stWatch = $this->db->prepare(
            'SELECT id as movie_id, is_tv, title, poster_path, vote_average, release_date
             FROM watchlist
             WHERE user_id = ? AND deleted = 0
             ORDER BY created_at DESC
             LIMIT 12'
        );
        $stWatch->execute([$userId]);
        $watchlist = $stWatch->fetchAll();

        $displayName = htmlspecialchars($user['display_name'] ?? $user['username']);
        $userHandle = htmlspecialchars($user['username']);

        // HTML & CSS (Out of the box premium glassmorphism, responsive, Google Fonts)
        ?>
        <!DOCTYPE html>
        <html lang="tr">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title><?php echo $displayName; ?> Neler İzliyor? | Ne İzlesem</title>
            <link rel="preconnect" href="https://fonts.googleapis.com">
            <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
            <style>
                :root {
                    --bg: #0B0F19;
                    --surface: #151D30;
                    --red: #E50914;
                    --gold: #FFB300;
                    --ink: #FFFFFF;
                    --dim: #94A3B8;
                    --border: rgba(255, 255, 255, 0.08);
                }

                * {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                }

                body {
                    background-color: var(--bg);
                    color: var(--ink);
                    font-family: 'Outfit', sans-serif;
                    line-height: 1.6;
                    padding-bottom: 80px;
                }

                .container {
                    max-width: 1000px;
                    margin: 0 auto;
                    padding: 20px;
                }

                /* Header / Profile Card */
                header {
                    margin-top: 40px;
                    margin-bottom: 40px;
                    text-align: center;
                    padding: 40px 20px;
                    background: linear-gradient(135deg, rgba(21, 29, 48, 0.6) 0%, rgba(11, 15, 25, 0.8) 100%);
                    border-radius: 24px;
                    border: 1px solid var(--border);
                    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
                    backdrop-filter: blur(10px);
                }

                .avatar {
                    width: 90px;
                    height: 90px;
                    border-radius: 50%;
                    background: linear-gradient(45deg, var(--red), var(--gold));
                    margin: 0 auto 16px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 36px;
                    font-weight: 800;
                    color: white;
                    box-shadow: 0 8px 24px rgba(229, 9, 20, 0.3);
                }

                h1 {
                    font-size: 28px;
                    font-weight: 800;
                    letter-spacing: -0.5px;
                    margin-bottom: 6px;
                }

                .handle {
                    color: var(--gold);
                    font-weight: 600;
                    font-size: 16px;
                    margin-bottom: 24px;
                    display: inline-block;
                }

                .cta-btn {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    background-color: var(--red);
                    color: white;
                    text-decoration: none;
                    font-weight: 700;
                    padding: 14px 28px;
                    border-radius: 12px;
                    font-size: 15px;
                    transition: transform 0.2s, box-shadow 0.2s;
                    box-shadow: 0 10px 20px rgba(229, 9, 20, 0.25);
                }

                .cta-btn:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 15px 25px rgba(229, 9, 20, 0.4);
                }

                /* Sections */
                section {
                    margin-bottom: 48px;
                }

                h2 {
                    font-size: 20px;
                    font-weight: 700;
                    margin-bottom: 20px;
                    border-left: 4px solid var(--gold);
                    padding-left: 12px;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                }

                /* Grid Layout */
                .grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
                    gap: 20px;
                }

                .card {
                    background-color: var(--surface);
                    border-radius: 16px;
                    overflow: hidden;
                    border: 1px solid var(--border);
                    transition: transform 0.3s, box-shadow 0.3s;
                    position: relative;
                }

                .card:hover {
                    transform: translateY(-5px);
                    box-shadow: 0 10px 20px rgba(0, 0, 0, 0.4);
                }

                .poster-wrap {
                    aspect-ratio: 2/3;
                    width: 100%;
                    background-color: #0d121f;
                    position: relative;
                    overflow: hidden;
                }

                .poster {
                    width: 100%;
                    height: 100%;
                    object-fit: cover;
                }

                .poster-placeholder {
                    width: 100%;
                    height: 100%;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 12px;
                    color: var(--dim);
                    text-align: center;
                    padding: 10px;
                    background-color: #0e1422;
                }

                .card-info {
                    padding: 12px;
                }

                .card-title {
                    font-size: 13px;
                    font-weight: 600;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                    margin-bottom: 4px;
                }

                .card-meta {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    font-size: 11px;
                    color: var(--dim);
                }

                .rating-badge {
                    display: inline-flex;
                    align-items: center;
                    background-color: rgba(255, 179, 0, 0.15);
                    color: var(--gold);
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-weight: 700;
                }

                .empty-text {
                    color: var(--dim);
                    font-size: 14px;
                    padding: 20px 0;
                }

                @media (max-width: 480px) {
                    .grid {
                        grid-template-columns: repeat(3, 1fr);
                        gap: 10px;
                    }
                    .card-info {
                        display: none; /* Mobilde sadece afişleri göstererek temiz görünüm */
                    }
                    header {
                        padding: 30px 15px;
                    }
                    h1 {
                        font-size: 24px;
                    }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header>
                    <div class="avatar"><?php echo mb_substr($displayName, 0, 1, 'UTF-8'); ?></div>
                    <h1><?php echo $displayName; ?></h1>
                    <span class="handle">@<?php echo $userHandle; ?></span>
                    <div>
                        <a href="https://foodlabeldetective.com.tr/cinema/download" class="cta-btn">
                            <?php echo $displayName; ?> ile Eşleş ve İzle
                        </a>
                    </div>
                </header>

                <!-- Harika Buldukları (Favorites / Top Rated) -->
                <section>
                    <h2>🍿 Harika Buldukları</h2>
                    <?php if (empty($ratings)): ?>
                        <p class="empty-text">Henüz "Harika" olarak puanlanmış bir film veya dizi yok.</p>
                    <?php else: ?>
                        <div class="grid">
                            <?php foreach ($ratings as $r): ?>
                                <div class="card">
                                    <div class="poster-wrap">
                                        <?php if (!empty($r['poster_path'])): ?>
                                            <img src="https://image.tmdb.org/t/p/w300<?php echo $r['poster_path']; ?>" alt="<?php echo htmlspecialchars($r['title']); ?>" class="poster" loading="lazy">
                                        <?php else: ?>
                                            <div class="poster-placeholder"><?php echo htmlspecialchars($r['title']); ?></div>
                                        <?php endif; ?>
                                    </div>
                                    <div class="card-info">
                                        <div class="card-title"><?php echo htmlspecialchars($r['title']); ?></div>
                                        <div class="card-meta">
                                            <span><?php echo $r['is_tv'] ? 'Dizi' : 'Film'; ?></span>
                                            <?php if (!empty($r['vote_average'])): ?>
                                                <span class="rating-badge">★ <?php echo round((float) $r['vote_average'], 1); ?></span>
                                            <?php endif; ?>
                                        </div>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>
                </section>

                <!-- İzleme Listesi (Watchlist) -->
                <section>
                    <h2>📝 İzleme Listesi</h2>
                    <?php if (empty($watchlist)): ?>
                        <p class="empty-text">İzleme listesinde henüz bir şey yok.</p>
                    <?php else: ?>
                        <div class="grid">
                            <?php foreach ($watchlist as $w): ?>
                                <div class="card">
                                    <div class="poster-wrap">
                                        <?php if (!empty($w['poster_path'])): ?>
                                            <img src="https://image.tmdb.org/t/p/w300<?php echo $w['poster_path']; ?>" alt="<?php echo htmlspecialchars($w['title']); ?>" class="poster" loading="lazy">
                                        <?php else: ?>
                                            <div class="poster-placeholder"><?php echo htmlspecialchars($w['title']); ?></div>
                                        <?php endif; ?>
                                    </div>
                                    <div class="card-info">
                                        <div class="card-title"><?php echo htmlspecialchars($w['title']); ?></div>
                                        <div class="card-meta">
                                            <span><?php echo $w['is_tv'] ? 'Dizi' : 'Film'; ?></span>
                                            <?php if (!empty($w['vote_average'])): ?>
                                                <span class="rating-badge">★ <?php echo round((float) $w['vote_average'], 1); ?></span>
                                            <?php endif; ?>
                                        </div>
                                    </div>
                                </div>
                            <?php endforeach; ?>
                        </div>
                    <?php endif; ?>
                </section>
            </div>
        </body>
        </html>
        <?php
        exit;
    }

    // Yardımcı: Şık Hata Sayfası oluşturucu (Web için)
    private function renderWebError(string $title, string $desc): void
    {
        ?>
        <!DOCTYPE html>
        <html lang="tr">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title><?php echo $title; ?> | Ne İzlesem</title>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;700&display=swap" rel="stylesheet">
            <style>
                body {
                    background-color: #0B0F19;
                    color: white;
                    font-family: 'Outfit', sans-serif;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    margin: 0;
                    text-align: center;
                    padding: 20px;
                }
                .card {
                    background-color: #151D30;
                    padding: 40px;
                    border-radius: 20px;
                    border: 1px solid rgba(255,255,255,0.08);
                    max-width: 450px;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.3);
                }
                h1 {
                    color: #FFB300;
                    font-size: 24px;
                    margin-bottom: 16px;
                }
                p {
                    color: #94A3B8;
                    font-size: 15px;
                    line-height: 1.5;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <h1><?php echo htmlspecialchars($title); ?></h1>
                <p><?php echo htmlspecialchars($desc); ?></p>
            </div>
        </body>
        </html>
        <?php
        exit;
    }

    // ─── GET /social/friends/signals ────────────────────────────────────────
    public function renderDownloadPage(): void
    {
        ?>
        <!DOCTYPE html>
        <html lang="tr">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Uygulamayı İndir | Ne İzlesem</title>
            <link rel="preconnect" href="https://fonts.googleapis.com">
            <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
            <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@300;400;600;800&display=swap" rel="stylesheet">
            <style>
                :root {
                    --bg: #0B0F19;
                    --surface: #151D30;
                    --red: #E50914;
                    --gold: #FFB300;
                    --ink: #FFFFFF;
                    --dim: #94A3B8;
                    --border: rgba(255, 255, 255, 0.08);
                }

                * {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                }

                body {
                    background-color: var(--bg);
                    color: var(--ink);
                    font-family: 'Outfit', sans-serif;
                    line-height: 1.6;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    min-height: 100vh;
                    padding: 40px 20px;
                }

                .container {
                    max-width: 500px;
                    width: 100%;
                    text-align: center;
                    padding: 40px 24px;
                    background: linear-gradient(135deg, rgba(21, 29, 48, 0.6) 0%, rgba(11, 15, 25, 0.8) 100%);
                    border-radius: 28px;
                    border: 1px solid var(--border);
                    box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
                    backdrop-filter: blur(12px);
                }

                .logo-wrap {
                    font-size: 48px;
                    margin-bottom: 20px;
                    animation: pulse 2s infinite alternate;
                }

                h1 {
                    font-size: 28px;
                    font-weight: 800;
                    letter-spacing: -0.5px;
                    margin-bottom: 12px;
                }

                p {
                    color: var(--dim);
                    font-size: 15px;
                    margin-bottom: 30px;
                }

                .download-btn {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    background-color: var(--red);
                    color: white;
                    text-decoration: none;
                    font-weight: 700;
                    padding: 16px 32px;
                    border-radius: 14px;
                    font-size: 16px;
                    width: 100%;
                    transition: transform 0.2s, box-shadow 0.2s;
                    box-shadow: 0 10px 20px rgba(229, 9, 20, 0.3);
                    margin-bottom: 16px;
                    cursor: pointer;
                }

                .download-btn:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 15px 25px rgba(229, 9, 20, 0.45);
                }

                .download-btn svg {
                    margin-right: 10px;
                    fill: currentColor;
                    width: 20px;
                    height: 20px;
                }

                .store-btn {
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    background-color: transparent;
                    color: var(--dim);
                    text-decoration: none;
                    font-weight: 600;
                    padding: 14px 32px;
                    border-radius: 14px;
                    font-size: 14px;
                    width: 100%;
                    border: 1px solid var(--border);
                    cursor: not-allowed;
                    margin-bottom: 30px;
                }

                .store-btn svg {
                    margin-right: 10px;
                    fill: currentColor;
                    width: 18px;
                    height: 18px;
                }

                .instructions {
                    text-align: left;
                    background-color: rgba(255, 255, 255, 0.02);
                    border-radius: 16px;
                    padding: 20px;
                    border: 1px solid var(--border);
                }

                .instructions-title {
                    font-size: 14px;
                    font-weight: 700;
                    color: var(--gold);
                    margin-bottom: 12px;
                    text-transform: uppercase;
                    letter-spacing: 1px;
                }

                .instructions ol {
                    padding-left: 20px;
                    font-size: 13.5px;
                    color: var(--dim);
                }

                .instructions li {
                    margin-bottom: 8px;
                }

                .instructions li strong {
                    color: var(--ink);
                }

                @keyframes pulse {
                    from { transform: scale(1); }
                    to { transform: scale(1.05); }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="logo-wrap">🎬</div>
                <h1>Ne İzlesem?</h1>
                <p>Arkadaşlarınla ortak film ve dizilerini bulup karar felcinden kurtulmak için hemen uygulamayı indir!</p>

                <!-- Android APK Download -->
                <a href="https://foodlabeldetective.com.tr/cinema/app-release.apk" class="download-btn">
                    <svg viewBox="0 0 24 24">
                        <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM17 13l-5 5-5-5h3V9h4v4h3z"/>
                    </svg>
                    Android (.APK) İndir
                </a>

                <!-- iOS Store Button (Disabled/Soon) -->
                <div class="store-btn">
                    <svg viewBox="0 0 24 24">
                        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 4.17c.66-.81 1.11-1.93.99-3.06-1 .04-2.22.67-2.94 1.51-.64.74-1.2 1.88-1.05 3 .1.01.21.02.32.02.89 0 2.02-.66 2.68-1.47z"/>
                    </svg>
                    App Store (Yakında)
                </div>

                <!-- Installation Guide -->
                <div class="instructions">
                    <div class="instructions-title">Yükleme Kılavuzu</div>
                    <ol>
                        <li>Yukarıdaki <strong>Android (.APK) İndir</strong> butonuna basarak dosyayı indirin.</li>
                        <li>İndirme tamamlandığında bildirimden veya dosya yöneticinizden dosyaya tıklayın.</li>
                        <li>Eğer sistem güvenlik uyarısı verirse, <strong>Ayarlar</strong> seçeneğine tıklayıp <strong>"Bu kaynaktan izin ver"</strong> seçeneğini aktif edin.</li>
                        <li>Geri dönerek <strong>Yükle</strong> butonuna basın ve uygulamanın tadını çıkarın!</li>
                    </ol>
                </div>
            </div>
        </body>
        </html>
        <?php
        exit;
    }
}
