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

        /* Sinema DNA kartı */
        .dna {
            background: linear-gradient(135deg, rgba(255, 179, 0, 0.14) 0%, rgba(229, 9, 20, 0.12) 100%);
            border: 1px solid rgba(255, 179, 0, 0.35);
            border-radius: 24px;
            padding: 32px 24px;
            text-align: center;
            margin-bottom: 40px;
        }
        .dna-emoji { font-size: 48px; line-height: 1; }
        .dna-label {
            color: var(--gold);
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 3px;
            margin-top: 12px;
            /* lang="tr" sayesinde i→İ doğru; PHP'de uppercase entity bozar. */
            text-transform: uppercase;
        }
        .dna-name {
            font-size: 30px;
            font-weight: 800;
            margin: 6px 0 10px;
        }
        .dna-essence { color: var(--dim); font-size: 15px; }
        .dna-chips {
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
            justify-content: center;
            margin-top: 18px;
        }
        .dna-chip {
            padding: 7px 14px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 600;
            background: rgba(255, 179, 0, 0.12);
            color: var(--gold);
            border: 1px solid rgba(255, 179, 0, 0.4);
        }
        .dna-chip.genre {
            background: var(--surface);
            color: var(--ink);
            border-color: var(--border);
        }
        .dna-themes-evidence {
            margin-top: 24px;
            text-align: left;
            display: flex;
            flex-direction: column;
            gap: 16px;
        }
        .dna-theme-row {
            display: flex;
            flex-direction: column;
            gap: 8px;
        }
        .dna-theme-row .theme-name {
            align-self: flex-start;
        }
        .dna-theme-posters {
            display: flex;
            gap: 8px;
            overflow-x: auto;
            padding-bottom: 4px;
        }
        .dna-theme-poster-wrapper {
            position: relative;
            width: 50px;
            height: 75px;
            border-radius: 6px;
            overflow: hidden;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
            border: 1px solid var(--border);
            flex-shrink: 0;
            background-color: var(--surface);
        }
        .dna-theme-poster {
            width: 100%;
            height: 100%;
            object-fit: cover;
            display: block;
        }
        .dna-theme-poster.empty {
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 18px;
            color: var(--dim);
        }
        .dna-signals {
            text-align: left;
            margin-top: 22px;
            display: grid;
            gap: 10px;
        }
        .dna-signal {
            color: var(--ink);
            font-size: 14px;
            line-height: 1.4;
            padding-left: 18px;
            position: relative;
        }
        .dna-signal::before {
            content: '';
            position: absolute;
            left: 0;
            top: 8px;
            width: 7px;
            height: 7px;
            border-radius: 50%;
            background: var(--gold);
        }
        .dna-accuracy {
            margin-top: 18px;
            padding: 12px 16px;
            border-radius: 14px;
            background: rgba(52, 199, 89, 0.12);
            border: 1px solid rgba(52, 199, 89, 0.4);
            color: #E8FFF0;
            font-size: 13.5px;
            font-weight: 600;
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

        <!-- Sinema DNA -->
        <?php if (!empty($dna)): ?>
            <div class="dna">
                <div class="dna-emoji"><?php echo $dna['emoji']; ?></div>
                <div class="dna-label"><?php echo $displayName; ?></div>
                <div class="dna-name"><?php echo htmlspecialchars($dna['archetype']); ?></div>
                <div class="dna-essence"><?php echo htmlspecialchars($dna['essence']); ?></div>

                <?php if (!empty($dna['themes_with_evidence'])): ?>
                    <div class="dna-themes-evidence">
                        <?php foreach ($dna['themes_with_evidence'] as $item): ?>
                            <div class="dna-theme-row">
                                <span class="dna-chip theme-name"><?php echo htmlspecialchars($item['name']); ?></span>
                                <div class="dna-theme-posters">
                                    <?php foreach ($item['movies'] as $m): ?>
                                        <div class="dna-theme-poster-wrapper" title="<?php echo htmlspecialchars($m['title']); ?>">
                                            <?php if (!empty($m['poster_path'])): ?>
                                                <img class="dna-theme-poster" src="https://image.tmdb.org/t/p/w92<?php echo htmlspecialchars($m['poster_path']); ?>" alt="<?php echo htmlspecialchars($m['title']); ?>">
                                            <?php else: ?>
                                                <div class="dna-theme-poster empty">🎬</div>
                                            <?php endif; ?>
                                        </div>
                                    <?php endforeach; ?>
                                </div>
                            </div>
                        <?php endforeach; ?>
                    </div>
                <?php elseif (!empty($dna['themes'])): ?>
                    <div class="dna-chips">
                        <?php foreach ($dna['themes'] as $t): ?>
                            <span class="dna-chip"><?php echo htmlspecialchars($t); ?></span>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['genres'])): ?>
                    <div class="dna-chips">
                        <?php foreach ($dna['genres'] as $g): ?>
                            <span class="dna-chip genre"><?php echo htmlspecialchars($g); ?></span>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['signals'])): ?>
                    <div class="dna-signals">
                        <?php foreach ($dna['signals'] as $s): ?>
                            <div class="dna-signal"><?php echo htmlspecialchars($s); ?></div>
                        <?php endforeach; ?>
                    </div>
                <?php endif; ?>

                <?php if (!empty($dna['accuracy'])): ?>
                    <div class="dna-accuracy">✓ <?php echo htmlspecialchars($dna['accuracy']); ?></div>
                <?php endif; ?>
            </div>
        <?php endif; ?>

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
